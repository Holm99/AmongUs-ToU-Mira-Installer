# Requires PowerShell 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ======================================================
# Config
# ======================================================
$script:AppId        = 945360
$script:AppName      = 'Among Us'
$script:LogPath      = Join-Path $env:USERPROFILE 'Downloads\au-installer-latest.log'
$script:Paths        = $null
$script:GameDir      = $null
$script:GameDirBck   = $null
$script:speed        = 1

$ProgressPreference = 'SilentlyContinue'
$script:LastLogLine = $null

# ======================================================
# Logging
# ======================================================
function New-Ts { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }

function Start-InstallerLog {
  try {
    $logDir = Split-Path -Parent $script:LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
      New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    "[{0}] [INFO] ===== Among Us Mod Installer — Session Start =====" -f (New-Ts) |
      Set-Content -LiteralPath $script:LogPath -Encoding UTF8
    "[{0}] [INFO] Log file: {1}" -f (New-Ts), $script:LogPath |
      Add-Content -LiteralPath $script:LogPath -Encoding UTF8

    # ---- Resolve script path robustly (handles file, module, irm|iex) ----
    $scriptPath = $null
    try {
      if ($MyInvocation.PSObject.Properties['PSCommandPath']) {
        $scriptPath = $MyInvocation.PSCommandPath
      }
      if (-not $scriptPath -and $MyInvocation.MyCommand) {
        $mc = $MyInvocation.MyCommand
        if ($mc.PSObject.Properties['Path']) {
          $scriptPath = $mc.Path
        } elseif ($mc.PSObject.Properties['ScriptBlock'] -and $mc.ScriptBlock) {
          $scriptPath = $mc.ScriptBlock.File
        } elseif ($mc.PSObject.Properties['Source']) {
          $scriptPath = $mc.Source
        }
      }
    } catch { }
    if (-not $scriptPath) { $scriptPath = '<inline/iex>' }

    # ---- Resolve working directory robustly (avoids StrictMode property errors) ----
    $wd = $null
    try {
      $loc = Get-Location
      if ($loc -is [string]) {
        $wd = $loc
      } elseif ($loc -and $loc.PSObject.Properties['Path']) {
        $wd = $loc.Path
      } else {
        $wd = $loc.ToString()
      }
    } catch {
      try { $wd = (Resolve-Path . -ErrorAction Stop).Path } catch { $wd = (Get-Item -LiteralPath .).FullName }
    }

    $envInfo = [pscustomobject]@{
      User              = "$env:USERNAME"
      Machine           = "$env:COMPUTERNAME"
      PSVersion         = ($PSVersionTable.PSVersion.ToString())
      OSVersion         = ([System.Environment]::OSVersion.VersionString)
      Culture           = (Get-Culture).Name
      UIculture         = (Get-UICulture).Name
      Is64BitProcess    = [Environment]::Is64BitProcess
      Is64BitOS         = [Environment]::Is64BitOperatingSystem
      ScriptPath        = $scriptPath
      WorkingDirectory  = $wd
    }

    "[{0}] [INFO] --- Environment ---------------------------------" -f (New-Ts) |
      Add-Content -LiteralPath $script:LogPath -Encoding UTF8
    $envInfo | ConvertTo-Json -Depth 3 | Add-Content -LiteralPath $script:LogPath -Encoding UTF8
    "[{0}] [INFO] --------------------------------------------------" -f (New-Ts) |
      Add-Content -LiteralPath $script:LogPath -Encoding UTF8
  } catch {
    Write-Host "Failed to initialize log: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('INFO','OK','WARN','ERROR','STATUS','STEP','CMD','NET','PATH','ACTION','RESULT','SECTION')]
    [string]$Level,
    [Parameter(Mandatory)][string]$Message
  )
  try {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    if ($script:LastLogLine -eq $line) { return }
    $script:LastLogLine = $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
  } catch {}
}

function Write-LogRaw {
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [AllowEmptyCollection()]
    [object]$Lines
  )
  try {
    if ($null -eq $Lines) { return }

    # Normalize to a string array and drop nulls (keep empty strings = intentional blank lines)
    $arr = @()
    if ($Lines -is [System.Collections.IEnumerable] -and -not ($Lines -is [string])) {
      foreach ($l in $Lines) { if ($null -ne $l) { $arr += [string]$l } }
    } else {
      $arr = @([string]$Lines)
    }

    if ($arr.Count -eq 0) { return }
    Add-Content -LiteralPath $script:LogPath -Value $arr -Encoding UTF8
  } catch {}
}

function Write-LogSection {
  param([Parameter(Mandatory)][string]$Title)
  $bar = ('-' * 66)
  Add-Content -LiteralPath $script:LogPath -Value $bar -Encoding UTF8
  Add-Content -LiteralPath $script:LogPath -Value ("[{0}] [SECTION] {1}" -f (New-Ts), $Title) -Encoding UTF8
  Add-Content -LiteralPath $script:LogPath -Value $bar -Encoding UTF8
}

function Write-TypeLines {
  param(
    [Parameter(Mandatory)][string[]]$Lines,
    [double]$TotalSeconds = $script:speed,   # default comes from the global knob
    [string[]]$Colors
  )

  # Instant mode: print whole lines without per-char delay
  if ($TotalSeconds -le 0) {
    for ($li=0; $li -lt $Lines.Count; $li++) {
      $line  = $Lines[$li]
      $color = if ($Colors -and $Colors.Count -gt $li) { $Colors[$li] } else { $null }
      if ($color) { Write-Host $line -ForegroundColor $color } else { Write-Host $line }
    }
    return
  }

  $totalChars = ($Lines | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum
  if ($totalChars -lt 1) { $totalChars = 1 }

  $minDelayMs = 5
  $maxDelayMs = 30
  $delayMs = [int][Math]::Round(($TotalSeconds * 1000) / $totalChars)
  $delayMs = [Math]::Max($minDelayMs, [Math]::Min($maxDelayMs, $delayMs))

  for ($li=0; $li -lt $Lines.Count; $li++) {
    $line  = $Lines[$li]
    $color = if ($Colors -and $Colors.Count -gt $li) { $Colors[$li] } else { $null }
    foreach ($ch in $line.ToCharArray()) {
      if ($color) { Write-Host -NoNewline $ch -ForegroundColor $color } else { Write-Host -NoNewline $ch }
      Start-Sleep -Milliseconds $delayMs
    }
    Write-Host ''
  }
}

function UiSleep {
  param([int]$Milliseconds)
  if ($script:speed -le 0) { return }
  Start-Sleep -Milliseconds $Milliseconds
}

function Write-Info  { param([string]$m) Write-TypeLines -Lines @($m) -Colors @('Cyan');    Write-Log -Level 'INFO'  -Message $m }
function Write-Ok    { param([string]$m) Write-TypeLines -Lines @($m) -Colors @('Green');   Write-Log -Level 'OK'    -Message $m }
function Write-Warn2 { param([string]$m) Write-TypeLines -Lines @($m) -Colors @('Yellow');  Write-Log -Level 'WARN'  -Message $m }
function Write-Err2  { param([string]$m) Write-TypeLines -Lines @($m) -Colors @('Red');     Write-Log -Level 'ERROR' -Message $m }

# ======================================================
# UI
# ======================================================
function Show-Banner {
@'

 /$$   /$$           /$$               /$$$$$$ /$$$$$$$$
| $$  | $$          | $$              |_  $$_/|__  $$__/
| $$  | $$  /$$$$$$ | $$ /$$$$$$/$$$$   | $$     | $$
| $$$$$$$$ /$$__  $$| $$| $$_  $$_  $$  | $$     | $$
| $$__  $$| $$  \ $$| $$| $$ \ $$ \ $$  | $$     | $$
| $$  | $$| $$  | $$| $$| $$ | $$ | $$  | $$     | $$
| $$  | $$|  $$$$$$/| $$| $$ | $$ | $$ /$$$$$$   | $$
|__/  |__/ \______/ |__/|__/ |__/ |__/|______/   |__/

           Among Us Mod Installer
'@ | Write-Host -ForegroundColor Green
}

function Show-ProgressDots {
  param([string]$Label = 'Working', [int]$Seconds = 3)

  if ($script:speed -le 0) {
    Write-Host ("{0} ..." -f $Label)
    return
  }

  $frames = @('....','.........','.............')
  $tickMs = 150
  $elapsed = 0
  while ($elapsed -lt ($Seconds * 1000)) {
    $i = [Math]::Min([int]([Math]::Floor($elapsed / $tickMs)), $frames.Count-1)
    $dots = $frames[$i]
    Write-Host -NoNewline ("`r{0} {1} " -f $Label, $dots)
    UiSleep -Milliseconds $tickMs
    $elapsed += $tickMs
  }
  Write-Host
}

function Read-Choice {
  param([string]$Prompt,[string[]]$Allowed,[string]$Default)
  while ($true) {
    $in = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($in)) { $in = $Default }
    if ($Allowed -contains $in) {
      Write-Log -Level 'ACTION' -Message ("Menu choice: {0}" -f $in)
      return $in
    }
    Write-Warn2 "Please enter one of: $($Allowed -join ', ') and press ENTER."
  }
}
function Read-YQ {
  param([string]$Prompt = 'Continue? (Y - Yes, q - Quit and press ENTER):')
  while ($true) {
    $in = (Read-Host $Prompt).Trim()
    if ($in -match '^(y|Y)$') { Write-Log -Level 'ACTION' -Message "Prompt accepted: $Prompt"; return 'y' }
    if ($in -match '^(q|Q)$') { Write-Log -Level 'ACTION' -Message "Prompt quit: $Prompt"; return 'q' }
    Write-Warn2 "Please type 'Y' to continue or 'Q' to quit."
  }
}
function Read-YN {
  param([string]$Prompt = 'Install Better-CrewLink now? (Y - for Yes, N - for No and press ENTER): ')
  while ($true) {
    $in = (Read-Host $Prompt).Trim()
    if ($in -match '^(y|Y)$') { Write-Log -Level 'ACTION' -Message "Answered YES: $Prompt"; return $true }
    if ($in -match '^(n|N)$') { Write-Log -Level 'ACTION' -Message "Answered NO: $Prompt";  return $false }
    Write-Warn2 "Please type 'y' or 'n' and press ENTER."
  }
}

# ======================================================
# Networking
# ======================================================
function Ensure-Tls12 {
  try {
    $cur = [Net.ServicePointManager]::SecurityProtocol
    [Net.ServicePointManager]::SecurityProtocol =
      $cur -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
  } catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  }
}


# ======================================================
# Steam discovery
# ======================================================
function Get-SteamRoot {
  $roots = @()
  $pairs = @(
    @{ Hive = 'CurrentUser';  View = 'Default';    Sub = @('Software','Valve','Steam') },
    @{ Hive = 'LocalMachine'; View = 'Registry32'; Sub = @('SOFTWARE','Valve','Steam') },
    @{ Hive = 'LocalMachine'; View = 'Registry64'; Sub = @('SOFTWARE','Valve','Steam') }
  )
  foreach ($p in $pairs) {
    try {
      $hive = [Microsoft.Win32.RegistryHive]::$($p.Hive)
      $view = [Microsoft.Win32.RegistryView]::$($p.View)
      $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
      $key  = $base.OpenSubKey(($p.Sub -join '\'))
      if ($key) {
        $path = $key.GetValue('SteamPath')
        if ($path -and (Test-Path $path)) { $roots += (Resolve-Path $path).Path }
      }
    } catch {}
  }
  if (-not $roots) {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $fallback = Join-Path $pf86 'Steam'
    if (Test-Path $fallback) { $roots += $fallback }
  }
  $roots | Select-Object -Unique
}

function Get-SteamLibraries {
  param([string[]]$SteamRoots)
  $libs = New-Object System.Collections.Generic.HashSet[string]
  foreach ($root in $SteamRoots) {
    foreach ($vdfRel in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')) {
      $vdf = Join-Path $root $vdfRel
      if (-not (Test-Path $vdf)) { continue }
      $content = Get-Content -Raw -LiteralPath $vdf
      $pattern = '(?i)"path"\s+"([^"]+)"'
      foreach ($m in [regex]::Matches($content, $pattern)) {
        $p = $m.Groups[1].Value -replace '\\\\','\'
        if ($p -and (Test-Path $p)) { $null = $libs.Add((Resolve-Path $p).Path) }
      }
      if (Test-Path $root) { $null = $libs.Add((Resolve-Path $root).Path) }
    }
  }
  if ($libs.Count -eq 0) {
    foreach ($root in $SteamRoots) { if (Test-Path $root) { $null = $libs.Add((Resolve-Path $root).Path) } }
  }
  $libs | ForEach-Object {
    $common = Join-Path $_ (Join-Path 'steamapps' 'common')
    if (Test-Path $common) { $common }
  } | Select-Object -Unique
}

# ======================================================
# Paths / Working folders
# ======================================================
function Initialize-Paths {
  $base = Join-Path $env:USERPROFILE 'Downloads\AmongUsModInstaller'

  $paths = [pscustomobject]@{
    Base      = $base
    Tools     = Join-Path $base 'tools'
    Temp      = Join-Path $base 'temp'
    Downloads = Join-Path $base 'downloads'
  }

  foreach ($p in $paths.PSObject.Properties.Value) {
    if (-not (Test-Path -LiteralPath $p)) {
      New-Item -ItemType Directory -Path $p | Out-Null
    }
  }
  $script:Paths = $paths
}

function Remove-WorkingFolder {
  $p = (Get-Variable -Name Paths -Scope Script -ErrorAction SilentlyContinue).Value
  if (-not $p) { return }
  if (-not (Test-Path $p.Base)) { return }

  Write-Info "Cleaning up: $($p.Base)"
  try {
    Get-ChildItem -LiteralPath $p.Base -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try { $_.Attributes = 'Normal' } catch {}
    }
    Remove-Item -LiteralPath $p.Base -Recurse -Force -ErrorAction Stop
    Write-Ok 'Cleanup complete.'
  } catch {
    Write-Warn2 "Cleanup failed: $($_.Exception.Message)"
  }
}

# ======================================================
# Generic helpers
# ======================================================
function Test-DirHasContent {
  param([Parameter(Mandatory)][string]$Path)
  try {
    $any = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop | Select-Object -First 1
    return [bool]$any
  } catch { return $false }
}

function Get-GamePath {
  param([string[]]$CommonRoots)
  $candidates = @()
  foreach ($root in $CommonRoots) {
    $exact = Join-Path $root $Script:AppName
    if (Test-Path $exact) { $candidates += (Resolve-Path $exact).Path }
    $wild = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Among Us*' } |
            Select-Object -ExpandProperty FullName
    if ($wild) { $candidates += $wild }
  }
  $candidates = $candidates | Select-Object -Unique
  if (-not $candidates) { return $null }
  foreach ($cand in $candidates) { if (Test-Path (Join-Path $cand 'Among Us.exe')) { return $cand } }
  foreach ($cand in $candidates) { if (Test-DirHasContent $cand) { return $cand } }
  return $null
}

function Select-Folder {
  param([string]$Description = "Select a folder",[string]$Initial = $env:USERPROFILE)
  try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') {
      Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
      $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
      $dlg.Description = $Description
      $dlg.ShowNewFolderButton = $false
      if ($Initial -and (Test-Path $Initial)) { $dlg.SelectedPath = $Initial }
      if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
      return $null
    }
  } catch {}
  try {
    $temp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), '.ps1')
@'
param([string]$Description,[string]$Initial)
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description         = $Description
$dlg.ShowNewFolderButton = $false
if ($Initial -and (Test-Path $Initial)) { $dlg.SelectedPath = $Initial }
if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::WriteLine($dlg.SelectedPath) }
'@ | Set-Content -LiteralPath $temp -Encoding UTF8
    $sel = & powershell.exe -NoProfile -STA -File $temp -Description $Description -Initial $Initial
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    if ($sel) { return $sel.Trim() }
  } catch {}
  Write-Warn2 "GUI folder picker unavailable. Paste the full path to the game folder (or leave blank to cancel)."
  $p = Read-Host 'Path'
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  return $p
}

# ======================================================
# Version helpers
# ======================================================
function Normalize-VersionTag { param([Parameter(Mandatory)][string]$Tag) ($Tag -replace '^[vV]', '').Trim() }

function Compare-Versions {
  param([string]$A,[string]$B)
  if ([string]::IsNullOrWhiteSpace($A) -and [string]::IsNullOrWhiteSpace($B)) { return 0 }
  if ([string]::IsNullOrWhiteSpace($A)) { return -1 }
  if ([string]::IsNullOrWhiteSpace($B)) { return 1 }
  try { return ([version]$A).CompareTo([version]$B) } catch { if ($A -eq $B) { 0 } else { -1 } }
}

# ======================================================
# Resolve game dir
# ======================================================
function Resolve-GameDirSilent {
  try {
    $roots = Get-SteamRoot
    $libs  = Get-SteamLibraries -SteamRoots $roots
    $auto  = Get-GamePath -CommonRoots $libs
    if ($auto) { return (Resolve-Path $auto).Path }
  } catch {}
  return $null
}
function Resolve-GameDirInteractive {
  Show-ProgressDots -Label 'Searching for Game Directory' -Seconds 3
  $roots = Get-SteamRoot
  $libs  = Get-SteamLibraries -SteamRoots $roots
  $auto  = Get-GamePath -CommonRoots $libs
  if ($auto) {
    Write-TypeLines -Lines @("Found '$($script:AppName)' Installation: $auto") -Colors @('Green')
    Write-Log -Level 'RESULT' -Message ("GameDir (auto): {0}" -f $auto)
    return (Resolve-Path $auto).Path
  }
  Write-TypeLines -Lines @("No '$($script:AppName)' installation detected automatically.") -Colors @('Red')
  while ($true) {
    $initial = if ($libs) { $libs | Select-Object -First 1 } else { $env:ProgramFiles }
    $pick = Select-Folder -Description "Select '$($script:AppName)' game folder (must contain 'Among Us.exe')" -Initial $initial
    if (-not $pick) {
      $ans = Read-YQ "No folder selected. Try again? (y/q): "
      if ($ans -eq 'q') { return $null } else { continue }
    }
    if (Test-Path (Join-Path $pick 'Among Us.exe')) {
      Write-Log -Level 'RESULT' -Message ("GameDir (manual): {0}" -f $pick)
      return (Resolve-Path $pick).Path
    }
    Write-Warn2 "Selected folder does NOT contain 'Among Us.exe'."
    $ans = Read-YQ "Pick another folder? (y/q): "
    if ($ans -eq 'q') { return $null }
  }
}

# ======================================================
# Backup detection + state
# ======================================================
function Find-BackupDirGlobal {
  try {
    $roots   = Get-SteamRoot
    $commons = Get-SteamLibraries -SteamRoots $roots
    foreach ($c in $commons) {
      $cand = Join-Path $c 'Among Us - Bck'
      if (Test-Path $cand) {
        if (Test-Path (Join-Path $cand 'Among Us.exe')) { return (Resolve-Path $cand).Path }
        try {
          $any = Get-ChildItem -LiteralPath $cand -Recurse -File -ErrorAction Stop | Select-Object -First 1
          if ($any) { return (Resolve-Path $cand).Path }
        } catch {}
      }
    }
  } catch {}
  return $null
}
function Test-BackupAvailable {
  param([string]$GameDir)
  try {
    if ($GameDir -and (Test-Path $GameDir)) {
      $parent = Split-Path -Parent $GameDir
      $sibling = Join-Path $parent 'Among Us - Bck'
      if (Test-Path $sibling) { return $true }
    }
  } catch {}
  return [bool](Find-BackupDirGlobal)
}
function Test-ModInstalled {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
  if (-not $GameDir) { return $false }
  return Test-Path (Join-Path $GameDir 'TownOfUsMira.dll')
}
function Get-ExeVersion {
  param([Parameter(Mandatory)][string]$GameDir)
  $exe = Join-Path $GameDir 'Among Us.exe'
  if (Test-Path $exe) { return (Get-Item $exe).VersionInfo.FileVersion }
  return $null
}
function Get-InstalledTouMiraVersion {
  param([string]$GameDir)
  try {
    if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
    if (-not $GameDir) { return $null }
    $dll = Join-Path $GameDir 'TownOfUsMira.dll'
    if (Test-Path $dll) {
      $v = (Get-Item $dll).VersionInfo.ProductVersion
      if ($v) { return $v.Trim() }
    }
  } catch {}
  return $null
}

# ======================================================
# BetterCrewLink helpers
# ======================================================
function Get-LatestBetterCrewLinkVersion {
  Ensure-Tls12
  try {
    $api  = 'https://api.github.com/repos/OhMyGuus/BetterCrewLink/releases/latest'
    $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }
    Write-Log -Level 'ACTION' -Message ("GET {0}" -f $api)
    $r = Invoke-WebRequest -UseBasicParsing -Uri $api -Headers $hdrs -ErrorAction Stop
    $j = $r.Content | ConvertFrom-Json
    if ($j.tag_name) { return $j.tag_name }
  } catch {}
  try {
    $url = 'https://github.com/OhMyGuus/BetterCrewLink/releases/latest'
    Write-Log -Level 'ACTION' -Message ("HEAD {0}" -f $url)
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse()
    $loc  = $resp.Headers['Location']
    $resp.Close()
    if ($loc -and ($loc -match '/tag/([^/]+)$')) { return $matches[1] }
  } catch {}
  throw "Unable to determine latest BetterCrewLink version."
}
function Get-BCLDownloadInfo {
  param([Parameter(Mandatory)][string]$Tag)
  $verNoV = if ($Tag.StartsWith('v')) { $Tag.Substring(1) } else { $Tag }
  $name   = "Better-CrewLink-Setup-$verNoV.exe"
  $url    = "https://github.com/OhMyGuus/BetterCrewLink/releases/download/$Tag/$name"
  Write-Log -Level 'STATUS' -Message ("BCL Download => Tag: {0}, Url: {1}, Name: {2}" -f $Tag, $url, $name)
  [pscustomobject]@{ Tag = $Tag; Version = $verNoV; Name = $name; Url = $url }
}
function Test-BCLInstalled {
  $defaultDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\bettercrewlink'),
    (Join-Path $env:LOCALAPPDATA 'Programs\BetterCrewLink')
  )
  foreach ($d in $defaultDirs) {
    $exe = Join-Path $d 'Better-CrewLink.exe'
    if (Test-Path $exe) { return $true }
  }
  try {
    $keys = @(
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $hit = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and ($_.DisplayName -match '(?i)\bBetter[- ]?CrewLink\b') } |
           Select-Object -First 1
    if ($hit) { return $true }
  } catch {}
  try {
    $pkg = Get-Package -ProviderName Programs -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match '(?i)\bBetter[- ]?CrewLink\b' } |
           Select-Object -First 1
    if ($pkg) { return $true }
  } catch {}
  return $false
}
function Get-BCLUninstallEntry {
  $keys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.PSObject.Properties['DisplayName'] -and ($_.DisplayName -match '(?i)\bBetter[- ]?CrewLink\b') } |
    Select-Object -First 1 DisplayName, UninstallString
}
function Get-BCLInstalledVersion {
  foreach ($root in @(
    (Join-Path $env:LOCALAPPDATA 'Programs\bettercrewlink'),
    (Join-Path $env:LOCALAPPDATA 'Programs\BetterCrewLink')
  )) {
    $exe = Join-Path $root 'Better-CrewLink.exe'
    if (Test-Path $exe) {
      try { return ((Get-Item $exe).VersionInfo.ProductVersion).Trim() } catch {}
    }
  }
  try {
    $entry = Get-BCLUninstallEntry
    if ($entry -and $entry.UninstallString) {
      $path = $entry.UninstallString
      $exeDir = $null
      if ($path -match '^\s*"(.*?)"') { $exeDir = Split-Path -Parent $matches[1] } else { $exeDir = Split-Path -Parent ($path.Split(' ',2)[0]) }
      foreach ($candidate in @($exeDir, (Split-Path -Parent $exeDir))) {
        if (-not $candidate) { continue }
        $exe = Join-Path $candidate 'Better-CrewLink.exe'
        if (Test-Path $exe) {
          try { return ((Get-Item $exe).VersionInfo.ProductVersion).Trim() } catch {}
        }
      }
    }
  } catch {}
  return $null
}
function Uninstall-BetterCrewLink {
  $entry = Get-BCLUninstallEntry
  if (-not $entry -or -not $entry.UninstallString) {
    Write-Warn2 "Could not find an uninstall entry for Better-CrewLink."
    return
  }
  Write-Info  "Uninstalling: $($entry.DisplayName)"
  Write-Info  "Command: $($entry.UninstallString) /S"
  Write-Log   -Level 'ACTION' -Message ("Executing uninstall: {0} /S" -f $entry.UninstallString)

  $cmdLine = $entry.UninstallString
  $exePath = $null; $exeArgs = $null
  if ($cmdLine -match '^\s*"(.*?)"\s*(.*)$') { $exePath = $matches[1]; $exeArgs = $matches[2] }
  else { $parts = $cmdLine.Split(' ',2); $exePath = $parts[0]; $exeArgs = if ($parts.Count -gt 1) { $parts[1] } else { '' } }
  $exeArgs = ($exeArgs + ' /S').Trim()

  try {
    $p = Start-Process -FilePath $exePath -ArgumentList $exeArgs -PassThru -WindowStyle Hidden -ErrorAction Stop
    $p.WaitForExit()
    UiSleep -Milliseconds 3000
    Write-Ok "Uninstall finished (code $($p.ExitCode))."
    Write-Log -Level 'RESULT' -Message ("Uninstall ExitCode: {0}" -f $p.ExitCode)

    if ($p.ExitCode -eq 0) {
      $bclDir = Join-Path $env:LOCALAPPDATA 'Programs\bettercrewlink'
      if (Test-Path $bclDir) {
        $hasFiles = $false
        try {
          $f = Get-ChildItem -LiteralPath $bclDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
          $hasFiles = [bool]$f
        } catch {}
        if (-not $hasFiles) {
          try {
            Get-ChildItem -LiteralPath $bclDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
            Remove-Item -LiteralPath $bclDir -Recurse -Force -ErrorAction Stop
            Write-Info "Removed empty folder: $bclDir"
          } catch {
            Write-Warn2 "Failed to remove folder ($bclDir): $($_.Exception.Message)"
          }
        } else {
          Write-Warn2 "Better-CrewLink folder contains files; leaving in place: $bclDir"
        }
      }
    }
  } catch {
    Write-Warn2 "Silent uninstall failed: $($_.Exception.Message)"
  }
}
function Install-BetterCrewLink {
  Initialize-Paths
  Ensure-Tls12

  if (Test-BCLInstalled) {
    function Read-YNLocal { param([string]$Prompt='Reinstall Better-CrewLink? (Y - for Yes, N - for No and press ENTER):')
      while ($true) { $in = (Read-Host $Prompt).Trim(); if ($in -match '^(y|Y)$'){ Write-Log -Level 'ACTION' -Message 'BCL reinstall: YES'; return $true}; if($in -match '^(n|N)$'){ Write-Log -Level 'ACTION' -Message 'BCL reinstall: NO'; return $false}; Write-Warn2 "Please type 'y' or 'n'." }
    }
    if (-not (Read-YNLocal)) { Write-Info "Skipping Better-CrewLink install."; return }
    try { Uninstall-BetterCrewLink } catch { Write-Warn2 "Uninstall step failed: $($_.Exception.Message)" }
  }

  Write-Info 'Resolving latest Better-CrewLink version from GitHub...'
  $tag   = Get-LatestBetterCrewLinkVersion
  $info  = Get-BCLDownloadInfo -Tag $tag
  Write-Ok "Latest Better-CrewLink: $($info.Tag)"

  $dest = Join-Path $script:Paths.Downloads $info.Name
  Write-Info "Downloading installer: $($info.Name)"
  Write-Log -Level 'ACTION' -Message ("GET {0}" -f $info.Url)
  try {
    $hdrs = @{ 'User-Agent'='AU-Installer' }
    Invoke-WebRequest -UseBasicParsing -Uri $info.Url -OutFile $dest -Headers $hdrs -ErrorAction Stop
    Write-Ok "Saved: $dest"
  } catch {
    Write-Err2 "Download failed ($($info.Url)): $($_.Exception.Message)"
    return
  }

  Write-Info "Launching installer..."
  Write-Log -Level 'ACTION' -Message ("Start-Process {0}" -f $dest)
  try {
    Start-Process -FilePath $dest -ErrorAction Stop | Out-Null
  } catch {
    Write-Err2 "Failed to launch installer: $($_.Exception.Message)"; return
  }

  $totalWait = 20; $step = 4; $elapsed = 0
  while ($elapsed -lt $totalWait) {
    Start-Sleep -Seconds $step; $elapsed += $step
    if (Test-BCLInstalled) { Write-Ok "Better-CrewLink detected as installed."; return }
  }

  while (-not (Test-BCLInstalled)) {
    function Read-YNLocal2 { param([string]$Prompt='Still not detected. Return to menu? (Y - for Yes, N - for No and press ENTER):')
      while ($true) { $in = (Read-Host $Prompt).Trim(); if ($in -match '^(y|Y)$'){ Write-Log -Level 'ACTION' -Message 'Return without BCL detection: YES'; return $true}; if($in -match '^(n|N)$'){ Write-Log -Level 'ACTION' -Message 'Return without BCL detection: NO'; return $false}; Write-Warn2 "Please type 'y' or 'n'." }
    }
    if (Read-YNLocal2) { Write-Warn2 "Returning to menu without confirming Better-CrewLink installation."; return }
    Write-Info "Waiting 30 seconds more..."; Start-Sleep -Seconds 30
  }
  Write-Ok "Better-CrewLink detected as installed."
}

# ======================================================
# Backup helpers
# ======================================================
function Get-DirStat {
  param([Parameter(Mandatory)][string]$Path)
  $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue
  [PSCustomObject]@{
    Count = ($files | Measure-Object).Count
    Bytes = ($files | Measure-Object -Property Length -Sum).Sum
  }
}
function Read-BackupMeta {
  param([Parameter(Mandatory)][string]$BackupDir)
  $metaPath = Join-Path $BackupDir '.au_backup_meta.json'
  if (Test-Path $metaPath) {
    try { return (Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json) } catch { return $null }
  }
  return $null
}
function Save-BackupMeta {
  param([Parameter(Mandatory)][string]$BackupDir,[Parameter(Mandatory)][string]$GameDir,[Parameter(Mandatory)]$Stat,[string]$ExeVersion,[string]$ModVersion)
  $meta = [pscustomobject]@{
    created    = (Get-Date)
    gameDir    = $GameDir
    exeVersion = $ExeVersion
    count      = $Stat.Count
    bytes      = [int64]$Stat.Bytes
    modVersion = $ModVersion
  }
  $meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BackupDir '.au_backup_meta.json') -Encoding UTF8
}
function Save-BackupMetaModVersion {
  param([Parameter(Mandatory)][string]$BackupDir,[Parameter(Mandatory)][string]$Version)
  $metaPath = Join-Path $BackupDir '.au_backup_meta.json'
  $meta = if (Test-Path $metaPath) { Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json } else { [pscustomobject]@{} }
  $meta.modVersion = $Version
  $meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metaPath -Encoding UTF8
}
function Test-BackupIntegrity {
  param([Parameter(Mandatory)][string]$GameDir,[Parameter(Mandatory)][string]$BackupDir)
  $g = Get-DirStat -Path $GameDir
  $b = Get-DirStat -Path $BackupDir
  Write-Info ("Backup integrity - files: {0} vs {1}, bytes: {2:N0} vs {3:N0}" -f $g.Count,$b.Count,$g.Bytes,$b.Bytes)
  return (($g.Count -eq $b.Count) -and ([int64]$g.Bytes -eq [int64]$b.Bytes))
}

function Copy-TreeRobocopy {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )
  if (-not $script:Paths) { Initialize-Paths }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null

  $tempLog = Join-Path $script:Paths.Temp ('robocopy-backup-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
  $args    = @("$Source","$Destination","/E","/COPY:DAT","/R:2","/W:1","/MT:8","/ETA","/UNILOG:$tempLog")

  Write-Log -Level 'CMD' -Message ("robocopy {0} {1} /E /COPY:DAT /R:2 /W:1 /MT:8 /ETA /UNILOG:{2}" -f $Source,$Destination,$tempLog)
  & robocopy @args | Out-Null
  $code = $LASTEXITCODE

  $tsStart = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Write-LogRaw -Lines @('','------------------------------------------------------------',"[$tsStart] [ROBOCOPY] START (backup)")

  try {
    if ((Test-Path -LiteralPath $tempLog) -and ((Get-Item -LiteralPath $tempLog).Length -gt 0)) {
      $lines = Get-Content -LiteralPath $tempLog -Encoding Unicode
      # Normalize and filter truly empty lines so Write-LogRaw never gets a single empty string
      if ($lines -is [string]) {
        if ($lines.Length -gt 0) { Write-LogRaw -Lines @($lines) }
      } elseif ($lines) {
        $norm = @($lines | Where-Object { $_ -ne $null -and $_ -ne '' })
        if ($norm.Count -gt 0) { Write-LogRaw -Lines $norm }
      }
    } else {
      Write-Log -Level 'WARN' -Message "Robocopy temp log exists but is empty (or missing): $tempLog"
    }
  } catch {
    Write-Log -Level 'WARN' -Message "Failed reading robocopy temp log: $($_.Exception.Message)"
  }

  $tsEnd = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Write-LogRaw -Lines @("[$tsEnd] [ROBOCOPY] END (backup)",'------------------------------------------------------------','')

  if ($code -ge 8) { throw "Robocopy failed with code $code" }
  return $code
}

function Copy-TreeRobocopyQuiet {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [string]$FileMask = '*'
  )
  if (-not $script:Paths) { Initialize-Paths }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null

  $tempLog = Join-Path $script:Paths.Temp ('robocopy-mods-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
  $args    = @($Source, $Destination, $FileMask, "/E", "/R:2", "/W:1", "/MT:8", "/UNILOG:$tempLog")

  Write-Log -Level 'CMD' -Message ("robocopy {0} {1} {2} /E /R:2 /W:1 /MT:8 /UNILOG:{3}" -f $Source, $Destination, $FileMask, $tempLog)
  & robocopy @args | Out-Null
  $code = $LASTEXITCODE

  $tsStart = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Write-LogRaw -Lines @(
    ''
    '------------------------------------------------------------'
    "[$tsStart] [ROBOCOPY] START (mods apply)"
  )

  try {
    if ((Test-Path -LiteralPath $tempLog) -and ((Get-Item -LiteralPath $tempLog).Length -gt 0)) {
      $lines = Get-Content -LiteralPath $tempLog -Encoding Unicode
      if ($lines -is [string]) {
        if ($lines.Length -gt 0) { Write-LogRaw -Lines @($lines) }
      } elseif ($lines) {
        $norm = @($lines | Where-Object { $_ -ne $null -and $_ -ne '' })
        if ($norm.Count -gt 0) { Write-LogRaw -Lines $norm }
      }
    } else {
      Write-Log -Level 'WARN' -Message "Robocopy temp log exists but is empty (or missing): $tempLog"
    }
  } catch {
    Write-Log -Level 'WARN' -Message "Failed reading robocopy temp log: $($_.Exception.Message)"
  }

  $tsEnd = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Write-LogRaw -Lines @(
    "[$tsEnd] [ROBOCOPY] END (mods apply)"
    '------------------------------------------------------------'
    ''
  )

  if ($code -ge 8) { throw "Robocopy failed (mods) with code $code" }
}

function New-GameBackup {
  param([Parameter(Mandatory)][string]$GameDir)

  $backupDir = Join-Path (Split-Path -Parent $GameDir) 'Among Us - Bck'
  $script:GameDir    = (Resolve-Path $GameDir).Path
  $script:GameDirBck = $backupDir

  if (Test-Path $backupDir) {
    Write-Warn2 "Backup already exists at: $backupDir"
    $meta     = Read-BackupMeta -BackupDir $backupDir
    $current  = Get-DirStat -Path $GameDir
    $verNow   = Get-ExeVersion -GameDir $GameDir
    $upToDate = $false

    if ($meta) {
      $upToDate = ($meta.count -eq $current.Count) -and ([int64]$meta.bytes -eq [int64]$current.Bytes) -and ($meta.exeVersion -eq $verNow)
    }

    if ($upToDate) {
      Write-Ok "Backup matches current installation (exe $verNow). Skipping copy."
      return $backupDir
    }

    if ($meta -and $meta.exeVersion -ne $verNow) {
      Write-Info "Different game version detected (backup: $($meta.exeVersion) vs current: $verNow)."
    }

    if ((Read-YQ "Refresh backup with current game files? (y/q): ") -eq 'q') {
      Write-Info 'Keeping existing backup.'
      return $backupDir
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Write-Info "Archiving old backup -> $backupDir ($stamp)"
    Rename-Item -LiteralPath $backupDir -NewName (Split-Path -Leaf "$backupDir ($stamp)")
  }

  Write-Info "Starting backup with Robocopy..."
  Copy-TreeRobocopy -Source $GameDir -Destination $backupDir

  if (Test-BackupIntegrity -GameDir $GameDir -BackupDir $backupDir) {
    Write-Ok 'Backup looks good.'
  } else {
    Write-Warn2 'Backup mismatch; proceed with caution.'
  }

  $stat = Get-DirStat -Path $GameDir
  Save-BackupMeta -BackupDir $backupDir -GameDir $GameDir -Stat $stat -ExeVersion (Get-ExeVersion -GameDir $GameDir) -ModVersion $null
  return $backupDir
}

# ======================================================
# Mod download/install
# ======================================================
function Get-LatestTouMiraVersion {
  Ensure-Tls12
  try {
    $api  = 'https://api.github.com/repos/AU-Avengers/TOU-Mira/releases/latest'
    $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }
    Write-Log -Level 'ACTION' -Message ("GET {0}" -f $api)
    $r = Invoke-WebRequest -UseBasicParsing -Uri $api -Headers $hdrs -ErrorAction Stop
    $j = $r.Content | ConvertFrom-Json
    if ($j.tag_name) { return $j.tag_name }
  } catch {}
  try {
    $url = 'https://github.com/AU-Avengers/TOU-Mira/releases/latest'
    Write-Log -Level 'ACTION' -Message ("HEAD {0}" -f $url)
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse(); $loc = $resp.Headers['Location']; $resp.Close()
    if ($loc -and ($loc -match '/tag/([^/]+)$')) { return $matches[1] }
  } catch {}
  throw "Unable to determine latest TOU-Mira version."
}

function Expand-Zip {
  param([Parameter(Mandatory)][string]$ZipPath,[Parameter(Mandatory)][string]$Destination)
  if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
  } else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Destination) {
      Get-ChildItem -LiteralPath $Destination -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
      Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
  }
}

function Download-TouMiraAssets {
  param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$StageDir)
  Ensure-Tls12
  New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

  $base  = "https://github.com/AU-Avengers/TOU-Mira/releases/download/$Version"
  $items = @(
    @{ Name='MiraAPI.dll';                          Url="$base/MiraAPI.dll" },
    @{ Name='TownOfUsMira.dll';                     Url="$base/TownOfUsMira.dll" },
    @{ Name="TouMira-$Version-x86-steam-itch.zip";  Url="$base/TouMira-$Version-x86-steam-itch.zip" }
  )
  $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/octet-stream' }

  foreach ($it in $items) {
    $dest = Join-Path $StageDir $it.Name
    Write-Info ("Downloading: {0}" -f $it.Url)
    Write-Log -Level 'ACTION' -Message ("GET {0}" -f $it.Url)
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $it.Url -OutFile $dest -Headers $hdrs -ErrorAction Stop
    } catch {
      Write-Err2 "Download failed ($($it.Url)): $($_.Exception.Message)"
      throw
    }
  }

  [pscustomobject]@{
    StageDir = $StageDir
    MiraApi  = Join-Path $StageDir 'MiraAPI.dll'
    TouMira  = Join-Path $StageDir 'TownOfUsMira.dll'
    ZipPath  = Join-Path $StageDir "TouMira-$Version-x86-steam-itch.zip"
  }
}

function Install-TouMira {
  param([Parameter(Mandatory)][string]$GameDir,[Parameter(Mandatory)][string]$Version)
  $stage  = Join-Path $script:Paths.Temp ("TOU-Mira-$Version")
  $assets = Download-TouMiraAssets -Version $Version -StageDir $stage

  Write-Info 'Extracting mod zip...'
  $unz = Join-Path $stage 'unzipped'
  Expand-Zip -ZipPath $assets.ZipPath -Destination $unz

  $children = @(
    Get-ChildItem -LiteralPath $unz -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' -and $_.Name -ne '__MACOSX' -and $_.Name -ne '.DS_Store' }
  )
  $dirs  = @($children | Where-Object { $_.PSIsContainer })
  $files = @($children | Where-Object { -not $_.PSIsContainer })

  if (($dirs.Count -eq 1) -and ($files.Count -eq 0)) {
    $contentRoot = $dirs[0].FullName
    Write-Info "Zip contains wrapper folder '$($dirs[0].Name)'; copying its contents into the game directory."
  } else {
    $contentRoot = $unz
    Write-Info "Zip has files at root or multiple folders; copying from extraction root."
  }

  Write-Info 'Applying mod files to game directory...'
  Copy-TreeRobocopyQuiet -Source $contentRoot -Destination $GameDir -FileMask '*'
  Copy-Item -LiteralPath $assets.MiraApi -Destination (Join-Path $GameDir 'MiraAPI.dll') -Force
  Copy-Item -LiteralPath $assets.TouMira -Destination (Join-Path $GameDir 'TownOfUsMira.dll') -Force
  Write-Ok 'Mod files applied.'

  try {
    $installedBcl = Get-BCLInstalledVersion
    $latestTag    = $null
    try { $latestTag = Get-LatestBetterCrewLinkVersion } catch {}
    $latestBcl    = if ($latestTag) { Normalize-VersionTag $latestTag } else { $null }

    if ($installedBcl) {
      if ($latestBcl) {
        $cmp = Compare-Versions $installedBcl $latestBcl
        if ($cmp -ge 0) {
          Write-TypeLines -Lines @("Better-CrewLink is already installed ($installedBcl) and up-to-date. Skipping.") -TotalSeconds $script:speed -Colors @('Green')
        } else {
          Write-TypeLines -Lines @("Better-CrewLink is installed ($installedBcl). A newer version is available ($latestBcl).") -TotalSeconds $script:speed -Colors @('Yellow')
          if (Read-YN -Prompt 'Update Better-CrewLink now? (y/n): ') {
            Write-TypeLines -Lines @('Updating Better-CrewLink...') -TotalSeconds $script:speed -Colors @('Green')
            Install-BetterCrewLink
          } else {
            Write-TypeLines -Lines @('Skipping Better-CrewLink update.') -TotalSeconds $script:speed -Colors @('Yellow')
          }
        }
      } else {
        Write-TypeLines -Lines @("Better-CrewLink detected as installed ($installedBcl).") -TotalSeconds $script:speed -Colors @('Green')
      }
    } else {
      Write-Host ''
      Write-TypeLines -Lines @('Would you like to install Better-CrewLink (proximity voice chat) as well?') -TotalSeconds $script:speed -Colors @('Magenta')
      if (Read-YN -Prompt 'Install Better-CrewLink now? (y/n): ') {
        Write-TypeLines -Lines @('Launching Better-CrewLink installer...') -TotalSeconds $script:speed -Colors @('Green')
        Install-BetterCrewLink
      } else {
        Write-TypeLines -Lines @('Skipping Better-CrewLink.') -TotalSeconds $script:speed -Colors @('Yellow')
      }
    }
  } catch {
    Write-Warn2 "Better-CrewLink check failed: $($_.Exception.Message)"
  }
}

# ======================================================
# Install / Restore / Update orchestrations
# ======================================================
function Install-ToU {
  Initialize-Paths

  $gameDir = Resolve-GameDirInteractive
  if (-not $gameDir) { Write-Err2 "No valid '$($script:AppName)' instance found. Exiting."; return }

  $exe = Join-Path $gameDir 'Among Us.exe'
  Write-TypeLines -Lines @(
    "Using '$($script:AppName)' folder:",
    "  $gameDir",
    "Executable: $exe"
  ) -Colors @('Green',$null,'Cyan')
  Write-Log -Level 'STATUS' -Message ("Install target: {0}" -f $gameDir)

  Write-Host ''
  Write-TypeLines -Lines @('-' * 47) -Colors @('Red')
  Write-Host ''

  Write-TypeLines -Lines @(
    'Manual validation (Steam client):',
    "  Library -> Right-click '$($script:AppName)' -> Properties -> Installed Files -> Verify integrity of game files",
    'If you already verified before launching this script, press Y and ENTER to continue...'
  ) -Colors @('Cyan','DarkGray','Yellow')

  Write-Host ''
  $ans = Read-YQ 'When validation is finished, type y and press ENTER to continue (or q to quit): '
  if ($ans -eq 'q') { Write-TypeLines -Lines @('Aborted by user.') -Colors @('Yellow'); return }

  Write-Host ''
  Write-Info 'Pre-mod step: create/verify backup (Among Us -> Among Us - Bck)'
  $backupDir = New-GameBackup -GameDir $gameDir
  Write-Ok   "Backup folder: $backupDir"

  Write-Host ''
  Write-Info 'Resolving latest TOU-Mira version from GitHub...'
  $modVersion = Get-LatestTouMiraVersion
  Write-Ok "Latest version: $modVersion"

  Write-Info "Downloading & applying TOU-Mira ($modVersion)..."
  Install-TouMira -GameDir $gameDir -Version $modVersion
  Write-Ok "Mod installation complete."
}

function Restore-Vanilla {
  param([string]$GameDir)

  function Find-BackupDirLocal {
    $roots   = Get-SteamRoot
    $commons = Get-SteamLibraries -SteamRoots $roots
    foreach ($c in $commons) {
      $cand = Join-Path $c 'Among Us - Bck'
      if (Test-Path $cand) {
        $exe = Join-Path $cand 'Among Us.exe'
        if (Test-Path $exe) { return (Resolve-Path $cand).Path }
        try { if (Get-ChildItem -LiteralPath $cand -Recurse -File -ErrorAction Stop | Select-Object -First 1) { return (Resolve-Path $cand).Path } } catch {}
      }
    }
    return $null
  }

  if (-not $GameDir) {
    $GameDir = Resolve-GameDirInteractive
    if (-not $GameDir) {
      Write-Warn2 "Could not locate the current '$($script:AppName)' folder. Trying to locate backup instead..."
      $bckOnly = Find-BackupDirLocal
      if (-not $bckOnly) { Write-Err2 "No backup found. Nothing to restore."; return }
      $parent  = Split-Path -Parent $bckOnly
      $GameDir = Join-Path $parent 'Among Us'
    }
  }

  $GameDir   = (Resolve-Path $GameDir).Path
  $parentDir = Split-Path -Parent $GameDir
  $BackupDir = Join-Path $parentDir 'Among Us - Bck'

  if (-not (Test-Path $BackupDir)) {
    $found = Find-BackupDirLocal
    if ($found) {
      $BackupDir = $found
      $parentDir = Split-Path -Parent $BackupDir
      $GameDir   = Join-Path $parentDir 'Among Us'
    }
  }

  if (-not (Test-Path $BackupDir)) { Write-Err2 "Backup not found: $BackupDir"; return }

  Write-Info "This will restore vanilla by deleting:"
  Write-Host "  $GameDir" -ForegroundColor Yellow
  Write-Info "…and renaming backup:"
  Write-Host "  $BackupDir" -ForegroundColor Yellow
  if ((Read-YQ "Proceed? (y/q) type Y for yes and Q for quit and press ENTER: ") -eq 'q') { Write-Host 'Restore aborted.' -ForegroundColor Yellow; return }

  if (Test-Path $GameDir) {
    Write-Info "Removing current game folder..."
    try {
      Get-ChildItem -LiteralPath $GameDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
      Remove-Item -LiteralPath $GameDir -Recurse -Force -ErrorAction Stop
    } catch { Write-Warn2 "Direct delete failed: $($_.Exception.Message)"; Write-Err2 "Close the game/Steam and try again."; return }
  } else {
    Write-Warn2 "Current game folder not found (nothing to delete): $GameDir"
  }

  try {
    Write-Info "Restoring backup to: $GameDir"
    Rename-Item -LiteralPath $BackupDir -NewName 'Among Us' -ErrorAction Stop
  } catch { Write-Err2 "Failed to restore backup: $($_.Exception.Message)"; return }

  $restoredGameDir = Join-Path (Split-Path -Parent $BackupDir) 'Among Us'
  $metaPath        = Join-Path $restoredGameDir '.au_backup_meta.json'
  if (Test-Path $metaPath) {
    try { Remove-Item -LiteralPath $metaPath -Force -ErrorAction Stop; Write-Info "Removed metadata: $metaPath" } catch { Write-Warn2 "Could not remove metadata file ($metaPath): $($_.Exception.Message)" }
  }

  $restoredExe = Join-Path $restoredGameDir 'Among Us.exe'
  if (Test-Path $restoredExe) { Write-Ok "Restore complete."; Write-Info "Executable: $restoredExe" }
  else { Write-Warn2 "Restore finished, but 'Among Us.exe' was not found at:`n  $restoredGameDir" }

  $script:GameDir    = $restoredGameDir
  $script:GameDirBck = Join-Path (Split-Path -Parent $restoredGameDir) 'Among Us - Bck'

  try {
    if (Test-BCLInstalled) {
      Write-TypeLines -Lines @('Better-CrewLink is detected on this system. Do you want to uninstall it?') -Colors @('Magenta')
      if (Read-YN -Prompt 'Uninstall Better-CrewLink now? (y/n): ') {
        Uninstall-BetterCrewLink
      } else {
        Write-Info 'Keeping Better-CrewLink installed.'
      }
    } else {
      Write-Info 'Better-CrewLink is not detected.'
    }
  } catch {
    Write-Warn2 "Could not check/uninstall Better-CrewLink: $($_.Exception.Message)"
  }
}

function Update-ModPack {
  param([string]$GameDir)
  Write-Info "Update: restore vanilla, validate via Steam, and re-apply latest TOU-Mira."
  try { Restore-Vanilla -GameDir $GameDir } catch { Write-Err2 "Restore failed: $($_.Exception.Message)"; return }
  $restoredDir = $null
  if ($script:GameDir -and (Test-Path $script:GameDir)) { $restoredDir = $script:GameDir }
  if (-not $restoredDir -and $GameDir) {
    $parent = Split-Path -Parent $GameDir
    $cand   = Join-Path $parent 'Among Us'
    if (Test-Path $cand) { $restoredDir = $cand }
  }
  if (-not $restoredDir) { $restoredDir = Resolve-GameDirInteractive }
  if (-not $restoredDir -or -not (Test-Path (Join-Path $restoredDir 'Among Us.exe'))) {
    Write-Warn2 "Update aborted: restored game folder was not found (perhaps the restore was cancelled)."
    return
  }
  Install-ToU
}

# ======================================================
# Status, Availability, Repair/Update flows
# ======================================================
function Get-MenuAvailability {
  $gameDir      = Resolve-GameDirSilent
  $installedMod = Get-InstalledTouMiraVersion -GameDir $gameDir
  $installedBcl = Get-BCLInstalledVersion

  $latestModTag = $null; $latestBclTag = $null
  try { $latestModTag = Get-LatestTouMiraVersion } catch {}
  try { $latestBclTag = Get-LatestBetterCrewLinkVersion } catch {}

  $latestMod = if ($latestModTag) { Normalize-VersionTag $latestModTag } else { $null }
  $latestBcl = if ($latestBclTag) { Normalize-VersionTag $latestBclTag } else { $null }

  $modInstalled   = Test-ModInstalled -GameDir $gameDir
  $bclInstalled   = Test-BCLInstalled
  $backupAvailable= Test-BackupAvailable -GameDir $gameDir

  $modNeedsUpdate = $false
  if ($installedMod -and $latestMod) { if ((Compare-Versions $installedMod $latestMod) -lt 0) { $modNeedsUpdate = $true } }
  $bclNeedsUpdate = $false
  if ($installedBcl -and $latestBcl) { if ((Compare-Versions $installedBcl $latestBcl) -lt 0) { $bclNeedsUpdate = $true } }
  $anyUpdate = ($modNeedsUpdate -or $bclNeedsUpdate)

  [pscustomobject]@{
    GameDir          = $gameDir
    ModInstalled     = $modInstalled
    BclInstalled     = $bclInstalled
    BackupAvailable  = $backupAvailable
    AnyUpdate        = $anyUpdate
    ModNeedsUpdate   = $modNeedsUpdate
    BclNeedsUpdate   = $bclNeedsUpdate
    RepairAvailable  = ($backupAvailable -or $bclInstalled)
    InstalledModVer  = $installedMod
    InstalledBclVer  = $installedBcl
    LatestMod        = $latestMod
    LatestBcl        = $latestBcl
  }
}

function Coalesce { param($value, $fallback) if ($null -ne $value -and $value -ne '') { $value } else { $fallback } }

function Show-StatusPanel {
  param([psobject]$State)
  $m = if ($PSBoundParameters.ContainsKey('State') -and $State) { $State } else { Get-MenuAvailability }

  Write-LogSection -Title "CURRENT STATE SNAPSHOT"
  Write-Log -Level 'STATUS' -Message ("GameDir: {0}" -f (Coalesce $m.GameDir '<not found>'))
  Write-Log -Level 'STATUS' -Message ("ModInstalled: {0}, Version: {1}, Latest: {2}" -f $m.ModInstalled, (Coalesce $m.InstalledModVer '<n/a>'), (Coalesce $m.LatestMod '<n/a>'))
  Write-Log -Level 'STATUS' -Message ("BCL Installed: {0}, Version: {1}, Latest: {2}" -f $m.BclInstalled, (Coalesce $m.InstalledBclVer '<n/a>'), (Coalesce $m.LatestBcl '<n/a>'))
  Write-Log -Level 'STATUS' -Message ("BackupAvailable: {0}" -f $m.BackupAvailable)
  Write-Log -Level 'STATUS' -Message ("AnyUpdate: {0} (ModNeedsUpdate: {1}, BclNeedsUpdate: {2})" -f $m.AnyUpdate, $m.ModNeedsUpdate, $m.BclNeedsUpdate)

  $modBadge = ''
  if ($m.InstalledModVer -and $m.LatestMod) {
    if ((Compare-Versions $m.InstalledModVer $m.LatestMod) -lt 0) { $modBadge = '<--- Update available --->' }
  }
  $bclBadge = ''
  if ($m.InstalledBclVer -and $m.LatestBcl) {
    if ((Compare-Versions $m.InstalledBclVer $m.LatestBcl) -lt 0) { $bclBadge = '<--- Update available --->' }
  }

  $modText = if ($m.InstalledModVer) { $m.InstalledModVer } else { 'Not installed' }
  $bclText = if ($m.InstalledBclVer) { $m.InstalledBclVer } else { 'Not installed' }

  Write-Host -NoNewline 'Among Us Mod: ' -ForegroundColor Cyan
  if ($modBadge) { Write-Host -NoNewline $modText -ForegroundColor Yellow; Write-Host (' ' + $modBadge) -ForegroundColor Yellow }
  else { Write-Host $modText -ForegroundColor Yellow }

  Write-Host -NoNewline 'BetterCrewLink: ' -ForegroundColor Cyan
  if ($bclBadge) { Write-Host -NoNewline $bclText -ForegroundColor Yellow; Write-Host (' ' + $bclBadge) -ForegroundColor Yellow }
  else { Write-Host $bclText -ForegroundColor Yellow }
}

function Show-Menu {
  param([psobject]$State)
  $m = if ($PSBoundParameters.ContainsKey('State') -and $State) { $State } else { Get-MenuAvailability }

  Write-Host ''
  Write-Host ''
  $line1 = if ($m.ModInstalled) { '  1) Install Among Us - ToU Mira (already installed)' } else { '  1) Install Among Us - ToU Mira' }
  $line2 = if ($m.AnyUpdate) { '  2) Update' } else { '  2) Update (no updates available)' }
  $line3 = if ($m.BackupAvailable) { '  3) Restore Vanilla' } else { '  3) Restore Vanilla (no backup found)' }
  $line4 = if ($m.BclInstalled) { '  4) Install BetterCrewLink (already installed)' } else { '  4) Install BetterCrewLink' }
  $line5 = if ($m.RepairAvailable) { '  5) Repair' } else { '  5) Repair (nothing to repair)' }

  Write-TypeLines -Lines @($line1,$line2,$line3,$line4,$line5,'  Q) Quit') -TotalSeconds $script:speed -Colors @(
    $(if ($m.ModInstalled) {'DarkGray'} else {'Green'}),
    $(if ($m.AnyUpdate) {'Yellow'} else {'DarkGray'}),
    $(if ($m.BackupAvailable) {'Red'} else {'DarkGray'}),
    $(if ($m.BclInstalled) {'DarkGray'} else {'Magenta'}),
    $(if ($m.RepairAvailable) {'Yellow'} else {'DarkGray'}),
    'DarkGray'
  )
  Write-Host ''
  Write-Host ''
}

function Repair-Mod {
  param([string]$GameDir)
  $backup = Find-BackupDirGlobal
  if (-not $backup) {
    Write-Warn2 'No backup found — cannot repair the mod safely.'
    if (Read-YN -Prompt 'Would you like to perform a fresh install of TOU-Mira instead? (y/n): ') {
      try { Install-ToU } catch { Write-Err2 "Fresh install failed: $($_.Exception.Message)" }
    } else {
      Write-Info 'Okay — when you are ready, choose "Install Among Us - ToU Mira" from the main menu.'
    }
    return
  }
  try {
    Write-Info 'Repairing Mod: restoring vanilla from backup...'
    Restore-Vanilla -GameDir $GameDir
  } catch {
    Write-Err2 "Restore step failed: $($_.Exception.Message)"
    return
  }
  try {
    Write-Info 'Re-applying the latest TOU-Mira...'
    Install-ToU
  } catch {
    Write-Err2 "Re-install step failed: $($_.Exception.Message)"
  }
}
function Repair-BCL {
  if (-not (Test-BCLInstalled)) {
    Write-Warn2 'Better-CrewLink is not installed.'
    if (Read-YN -Prompt 'Install Better-CrewLink now? (y/n): ') {
      try { Install-BetterCrewLink } catch { Write-Err2 "BCL install failed: $($_.Exception.Message)" }
    }
    return
  }
  Write-Info 'Repairing Better-CrewLink: uninstalling...'
  try { Uninstall-BetterCrewLink } catch { Write-Warn2 "Uninstall step failed: $($_.Exception.Message)" }
  Write-Info 'Re-installing Better-CrewLink...'
  try { Install-BetterCrewLink } catch { Write-Err2 "Reinstall step failed: $($_.Exception.Message)" }
}
function Repair-All {
  try { Repair-Mod } catch { Write-Warn2 "Mod repair encountered an issue: $($_.Exception.Message)" }
  try { Repair-BCL } catch { Write-Warn2 "BCL repair encountered an issue: $($_.Exception.Message)" }
}
function Invoke-RepairFlow {
  $m = Get-MenuAvailability
  if (-not $m.RepairAvailable) { Write-Ok 'Nothing to repair right now.'; return }

  Write-Host ''
  Write-TypeLines -Lines @('Repair Menu:','  1) Repair All','  2) Repair Mod (TOU-Mira)','  3) Repair BetterCrewLink','  4) Abort') -TotalSeconds $script:speed -Colors @('Green','Yellow','Yellow','Yellow','DarkGray')
  Write-Host ''

  while ($true) {
    $sel = (Read-Host 'Choose 1/2/3/4').Trim()
    switch ($sel) {
      '1' { Repair-All;            return }
      '2' { Repair-Mod;            return }
      '3' { Repair-BCL;            return }
      '4' { Write-Info 'Aborted.'; return }
      default { Write-Warn2 'Please enter 1, 2, 3 or 4.' }
    }
  }
}

function Update-ToUMiraSmart {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
  if (-not $GameDir) { Write-Warn2 "Could not find game directory; skipping mod update."; return }

  $installed = Get-InstalledTouMiraVersion -GameDir $GameDir
  $latestTag = $null
  try { $latestTag = Get-LatestTouMiraVersion } catch { Write-Warn2 "Could not resolve latest TOU-Mira version: $($_.Exception.Message)"; return }
  $latest    = Normalize-VersionTag $latestTag

  if ($installed -and (Compare-Versions $installed $latest) -ge 0) { Write-Ok "TOU-Mira is already up-to-date ($installed)."; return }

  Write-Info ("Updating TOU-Mira (installed: {0}, latest: {1})..." -f ($(if ($installed) { $installed } else { 'none' }), $latest))
  try { Update-ModPack -GameDir $GameDir } catch { Write-Err2 "TOU-Mira update failed: $($_.Exception.Message)" }
}
function Update-AllSmart {
  $gameDir = Resolve-GameDirSilent
  $installedMod = Get-InstalledTouMiraVersion -GameDir $gameDir
  $installedBcl = Get-BCLInstalledVersion

  $latestModTag = $null; $latestBclTag = $null
  try { $latestModTag = Get-LatestTouMiraVersion } catch {}
  try { $latestBclTag = Get-LatestBetterCrewLinkVersion } catch {}

  $needMod = $false
  if ($latestModTag) { $latestMod = Normalize-VersionTag $latestModTag; $needMod = -not $installedMod -or ((Compare-Versions $installedMod $latestMod) -lt 0) }
  $needBcl = $false
  if ($latestBclTag) { $latestBcl = Normalize-VersionTag $latestBclTag; $needBcl = -not $installedBcl -or ((Compare-Versions $installedBcl $latestBcl) -lt 0) }

  if (-not $needMod -and -not $needBcl) { Write-Ok 'Everything is already up-to-date.'; return }

  if ($needMod) { Update-ToUMiraSmart -GameDir $gameDir }
  if ($needBcl) { Install-BetterCrewLink }
}
function Invoke-UpdateFlow {
  $gameDir = Resolve-GameDirSilent
  $installedMod = Get-InstalledTouMiraVersion -GameDir $gameDir
  $installedBcl = Get-BCLInstalledVersion

  $latestModTag = $null; $latestBclTag = $null
  try { $latestModTag = Get-LatestTouMiraVersion } catch {}
  try { $latestBclTag = Get-LatestBetterCrewLinkVersion } catch {}

  $needMod = $false; $needBcl = $false
  if ($latestModTag) { $latestMod = Normalize-VersionTag $latestModTag; $needMod = -not $installedMod -or ((Compare-Versions $installedMod $latestMod) -lt 0) }
  if ($latestBclTag) { $latestBcl = Normalize-VersionTag $latestBclTag; $needBcl = -not $installedBcl -or ((Compare-Versions $installedBcl $latestBcl) -lt 0) }

  if ($needMod -xor $needBcl) { Write-Info 'One update available; running Update All...'; Update-AllSmart; return }
  if (-not $needMod -and -not $needBcl) { Write-Ok 'No updates detected for Mod or Better-CrewLink.'; return }

  Write-Host ''
  Write-TypeLines -Lines @('Update Menu:','  1) Update All','  2) Update Mod (TOU-Mira)','  3) Update BetterCrewLink','  4) Abort') -TotalSeconds $script:speed -Colors @('Green','Yellow','Yellow','Yellow','DarkGray')
  Write-Host ''

  while ($true) {
    $sel = (Read-Host 'Choose 1/2/3/4').Trim()
    switch ($sel) {
      '1' { Update-AllSmart; break }
      '2' { Update-ToUMiraSmart; break }
      '3' { Install-BetterCrewLink; break }
      '4' { Write-Info 'Aborted.'; break }
      default { Write-Warn2 'Please enter 1, 2, 3 or 4.' }
    }
  }
}

# ======================================================
# MAIN
# ======================================================
Start-InstallerLog
try {
  $state = Get-MenuAvailability
  Write-LogSection -Title "INITIAL INSTALLED COMPONENTS"
  Write-Log -Level 'STATUS' -Message ("Among Us Mod: {0}" -f ($(if ($state.InstalledModVer) { $state.InstalledModVer } else { 'Not installed' })))
  Write-Log -Level 'STATUS' -Message ("BetterCrewLink: {0}" -f ($(if ($state.InstalledBclVer) { $state.InstalledBclVer } else { 'Not installed' })))
} catch {
  Write-Log -Level 'ERROR' -Message ("Initial snapshot failed: {0}" -f $_.Exception.Message)
}

:MainMenu while ($true) {
  try {
    #Clear-Host
    $m = Get-MenuAvailability
    Show-Banner
    Show-StatusPanel
    Show-Menu

    $allowed = @('1','2','3','4','5','q','Q')
    $choice  = Read-Choice -Prompt 'Select option (1/2/3/4/5 or Q to quit and press ENTER) [1]:' -Allowed $allowed -Default '1'

    switch ($choice) {
      '1' {
        if ($m.ModInstalled) { Write-Warn2 'Mod is already installed.' }
        else { try { Install-ToU } finally { Remove-WorkingFolder } }
        Write-TypeLines -Lines @('Done. Returning to menu...') -TotalSeconds $script:speed -Colors @('Green')
      }
      '2' {
        if (-not $m.AnyUpdate) { Write-Ok 'No updates available.' }
        else { try { Invoke-UpdateFlow } finally { Remove-WorkingFolder } }
        Write-TypeLines -Lines @('Done. Returning to menu...') -TotalSeconds $script:speed -Colors @('Green')
      }
      '3' {
        if (-not $m.BackupAvailable) { Write-Warn2 'No backup found — nothing to restore.' }
        else { try { Restore-Vanilla } finally { Remove-WorkingFolder } }
        Write-TypeLines -Lines @('Done. Returning to menu...') -TotalSeconds $script:speed -Colors @('Green')
      }
      '4' {
        if ($m.BclInstalled) { Write-Warn2 'Better-CrewLink is already installed.' }
        else { try { Install-BetterCrewLink } finally { Remove-WorkingFolder } }
        Write-TypeLines -Lines @('Done. Returning to menu...') -TotalSeconds $script:speed -Colors @('Green')
      }
      '5' {
        if (-not $m.RepairAvailable) { Write-Ok 'Nothing to repair right now.' }
        else { try { Invoke-RepairFlow } finally { Remove-WorkingFolder } }
        Write-TypeLines -Lines @('Done. Returning to menu...') -TotalSeconds $script:speed -Colors @('Green')
      }
      'q' {
        Write-TypeLines -Lines @('Goodbye!') -TotalSeconds $script:speed -Colors @('Green')
        Remove-WorkingFolder
        break MainMenu
      }
      'Q' {
        Write-TypeLines -Lines @('Goodbye!') -TotalSeconds $script:speed -Colors @('Green')
        Remove-WorkingFolder
        break MainMenu
      }
    }

    UiSleep -Milliseconds 700
  }
  catch {
    Write-Err2 "ERROR: $($_.Exception.Message)"
    Write-TypeLines -Lines @('Returning to menu...') -TotalSeconds $script:speed -Colors @('Yellow')
    UiSleep -Milliseconds 900
  }
}

Write-Log -Level 'INFO' -Message ("===== Session End =====")



