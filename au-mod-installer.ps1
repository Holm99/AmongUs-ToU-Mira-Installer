# Requires PowerShell 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ======================================================
# Config
# ======================================================
$script:AppName      = 'Among Us'
$script:LogPath      = Join-Path $env:USERPROFILE 'Downloads\au-installer-latest.log'
$script:Paths        = $null
$script:GameDir      = $null
$script:speed        = 1
$script:InstallerVersion = '2.0.0'
$script:__bannerShown = $false

$ProgressPreference = 'SilentlyContinue'
$script:LastLogLine = $null
$script:__TouMiraLatestCache = $null
$script:__BclLatestCache = $null

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

    "[{0}] [INFO] ===== Among Us Mod Installer -- Session Start =====" -f (New-Ts) |
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

function Write-Step {
  param([int]$Current, [int]$Total, [string]$Label, [switch]$Done)
  if ($Done) {
    Write-Host ' done' -ForegroundColor Green
  } else {
    Write-Host -NoNewline ("[$Current/$Total] $Label... ") -ForegroundColor Cyan
    Write-Log -Level 'STEP' -Message ("[$Current/$Total] $Label")
  }
}

# ======================================================
# UI
# ======================================================
function Show-Banner {
  $color = if ($script:__bannerShown) { 'DarkGreen' } else { 'Green' }
  $art = @'

 /$$   /$$           /$$               /$$$$$$ /$$$$$$$$
| $$  | $$          | $$              |_  $$_/|__  $$__/
| $$  | $$  /$$$$$$ | $$ /$$$$$$/$$$$   | $$     | $$
| $$$$$$$$ /$$__  $$| $$| $$_  $$_  $$  | $$     | $$
| $$__  $$| $$  \ $$| $$| $$ \ $$ \ $$  | $$     | $$
| $$  | $$| $$  | $$| $$| $$ | $$ | $$  | $$     | $$
| $$  | $$|  $$$$$$/| $$| $$ | $$ | $$ /$$$$$$   | $$
|__/  |__/ \______/ |__/|__/ |__/ |__/|______/   |__/
'@
  Write-Host $art -ForegroundColor $color
  Write-Host ("           Among Us Mod Installer v{0}" -f $script:InstallerVersion) -ForegroundColor $color
  $script:__bannerShown = $true
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

function Show-Separator {
  param([int]$Width = 50, [string]$Color = 'DarkGray')
  $line = [string]::new([char]0x2550, $Width)
  Write-Host $line -ForegroundColor $Color
}

function Show-SummaryBox {
  param(
    [string]$Title,
    [System.Collections.Specialized.OrderedDictionary]$Data,
    [string]$Color = 'DarkCyan'
  )
  $maxKey = 0
  $maxVal = 0
  foreach ($k in $Data.Keys) {
    if ($k.Length -gt $maxKey) { $maxKey = $k.Length }
    $v = [string]$Data[$k]
    if ($v.Length -gt $maxVal) { $maxVal = $v.Length }
  }
  $inner = $maxKey + 3 + $maxVal
  if ($Title.Length -gt $inner) { $inner = $Title.Length }
  $inner += 2
  $top    = [char]0x2554 + ([string]::new([char]0x2550, $inner)) + [char]0x2557
  $bottom = [char]0x255A + ([string]::new([char]0x2550, $inner)) + [char]0x255D
  $side   = [char]0x2551

  Write-Host ''
  Write-Host $top -ForegroundColor $Color
  $titlePad = $inner - $Title.Length
  $titleLeft = [Math]::Floor($titlePad / 2)
  $titleRight = $titlePad - $titleLeft
  Write-Host ($side + (' ' * $titleLeft) + $Title + (' ' * $titleRight) + $side) -ForegroundColor $Color
  Write-Host ($side + ([string]::new([char]0x2500, $inner)) + $side) -ForegroundColor $Color
  foreach ($k in $Data.Keys) {
    $v = [string]$Data[$k]
    $content = " $k : $v"
    $pad = $inner - $content.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host ($side + $content + (' ' * $pad) + $side) -ForegroundColor $Color
  }
  Write-Host $bottom -ForegroundColor $Color
  Write-Host ''
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

function Wait-KeyPress {
  param([string]$Message = 'Press any key to continue...')
  Write-Host $Message -ForegroundColor DarkGray
  try {
    if ($Host.Name -eq 'ConsoleHost') {
      $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } else {
      Read-Host
    }
  } catch {
    Read-Host
  }
}

function Invoke-CompletionBeep {
  if ($script:speed -le 0) { return }
  try { [Console]::Beep(800, 200) } catch {}
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

function Invoke-ApiWithSpinner {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [hashtable]$Headers = @{},
    [string]$Label = 'Fetching'
  )
  Ensure-Tls12
  $wc = New-Object System.Net.WebClient
  foreach ($k in $Headers.Keys) { $wc.Headers[$k] = $Headers[$k] }
  $task = $wc.DownloadStringTaskAsync([Uri]$Uri)

  if ($script:speed -le 0) {
    $task.Wait()
  } else {
    $frames = @('|','/','-','\')
    $i = 0
    while (-not $task.IsCompleted) {
      Write-Host -NoNewline ("`r {0} {1}" -f $frames[$i % $frames.Count], $Label)
      Start-Sleep -Milliseconds 120
      $i++
    }
    Write-Host ("`r {0} {1}" -f ' ', (' ' * ($Label.Length + 2)))
    Write-Host "`r" -NoNewline
  }

  if ($task.IsFaulted) {
    $wc.Dispose()
    throw $task.Exception.InnerException
  }
  $result = $task.Result
  $wc.Dispose()
  return $result
}

function Invoke-DownloadWithProgress {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$OutFile,
    [hashtable]$Headers = @{}
  )
  Ensure-Tls12
  $req = [System.Net.HttpWebRequest]::Create($Uri)
  $req.Method = 'GET'
  $req.AllowAutoRedirect = $true
  $req.UserAgent = 'AU-Installer'
  foreach ($k in $Headers.Keys) {
    switch ($k.ToLower()) {
      'accept'       { $req.Accept = $Headers[$k] }
      'content-type' { $req.ContentType = $Headers[$k] }
      'user-agent'   { $req.UserAgent = $Headers[$k] }
      default        { $req.Headers[$k] = $Headers[$k] }
    }
  }

  $resp = $null; $respStream = $null; $fs = $null
  try {
    $resp = $req.GetResponse()
    $totalBytes = $resp.ContentLength
    $respStream = $resp.GetResponseStream()
    $fs = [System.IO.File]::Create($OutFile)
    $buffer = New-Object byte[] 65536
    $downloaded = 0
    $lastPct = -1

    while ($true) {
      $read = $respStream.Read($buffer, 0, $buffer.Length)
      if ($read -le 0) { break }
      $fs.Write($buffer, 0, $read)
      $downloaded += $read

      if ($totalBytes -gt 0) {
        $pct = [int]([Math]::Floor(($downloaded / $totalBytes) * 100))
        if ($pct -ne $lastPct) {
          $lastPct = $pct
          $barLen = 30
          $filled = [int]([Math]::Floor($pct / 100 * $barLen))
          $empty  = $barLen - $filled
          $bar = '[' + ('#' * $filled) + (' ' * $empty) + ']'
          $dlMB = '{0:F1}' -f ($downloaded / 1MB)
          $totMB = '{0:F1}' -f ($totalBytes / 1MB)
          Write-Host -NoNewline ("`r  {0} {1,3}%  {2} / {3} MB" -f $bar, $pct, $dlMB, $totMB)
        }
      } else {
        $dlMB = '{0:F1}' -f ($downloaded / 1MB)
        Write-Host -NoNewline ("`r  Downloaded {0} MB..." -f $dlMB)
      }
    }
    Write-Host ''
  } catch {
    if ($fs) { $fs.Close(); $fs.Dispose() }
    if (Test-Path -LiteralPath $OutFile) {
      try { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue } catch {}
    }
    throw
  } finally {
    if ($fs)         { $fs.Close(); $fs.Dispose() }
    if ($respStream) { $respStream.Close(); $respStream.Dispose() }
    if ($resp)       { $resp.Close() }
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
# Manifest system
# ======================================================
function Get-ModManifest {
  param([Parameter(Mandatory)][string]$GameDir)
  $path = Join-Path $GameDir '.au_installer_manifest.json'
  if (Test-Path -LiteralPath $path) {
    try { return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json) } catch { return $null }
  }
  return $null
}

function Save-ModManifest {
  param(
    [Parameter(Mandatory)][string]$GameDir,
    [Parameter(Mandatory)][string]$ContentRoot,
    [Parameter(Mandatory)][string]$ModVersion,
    [Parameter(Mandatory)][string]$ModTag,
    [string]$GameVersion
  )

  $files = @()
  $topDirs = @()

  Get-ChildItem -LiteralPath $ContentRoot -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($ContentRoot.Length).TrimStart('\', '/')
    $files += $rel
  }

  Get-ChildItem -LiteralPath $ContentRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $topDirs += $_.Name
  }

  $manifest = [pscustomobject]@{
    installerVersion = '2.0.0'
    modVersion       = $ModVersion
    modTag           = $ModTag
    installedAt      = (Get-Date).ToUniversalTime().ToString('o')
    gameVersion      = $GameVersion
    gameDir          = $GameDir
    files            = $files
    directories      = $topDirs
  }

  $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $GameDir '.au_installer_manifest.json') -Encoding UTF8
  Write-Log -Level 'OK' -Message ("Manifest saved: {0} files, {1} directories" -f $files.Count, $topDirs.Count)
}

function Remove-ModFiles {
  param([Parameter(Mandatory)][string]$GameDir)

  $manifest = Get-ModManifest -GameDir $GameDir
  if (-not $manifest) {
    Write-Warn2 'No manifest found.'
    return $false
  }

  $removed = 0
  foreach ($f in $manifest.files) {
    $full = Join-Path $GameDir $f
    if (Test-Path -LiteralPath $full) {
      try { Remove-Item -LiteralPath $full -Force -ErrorAction Stop; $removed++ } catch { Write-Warn2 "Could not remove: $f" }
    }
  }

  # Remove top-level mod directories
  foreach ($d in $manifest.directories) {
    $full = Join-Path $GameDir $d
    if (Test-Path -LiteralPath $full) {
      try {
        Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
      } catch { Write-Warn2 "Could not fully remove directory: $d" }
    }
  }

  # Remove manifest file itself
  $manifestPath = Join-Path $GameDir '.au_installer_manifest.json'
  if (Test-Path -LiteralPath $manifestPath) {
    try { Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop } catch {}
  }

  Write-Log -Level 'OK' -Message ("Removed {0} mod files from {1}" -f $removed, $GameDir)
  Write-Ok "Removed $removed mod files."
  return $true
}

# ======================================================
# Config persistence
# ======================================================
function Get-InstallerConfig {
  param([string]$GameDir)
  if (-not $GameDir) { $GameDir = Resolve-GameDirSilent }
  if (-not $GameDir) { return $null }
  $path = Join-Path $GameDir '.au_installer_config.json'
  if (Test-Path -LiteralPath $path) {
    try { return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json) } catch { return $null }
  }
  return $null
}

function Save-InstallerConfig {
  param(
    [Parameter(Mandatory)][string]$GameDir,
    [int]$Speed = $script:speed
  )
  $config = [pscustomobject]@{
    installerVersion = $script:InstallerVersion
    gameDir          = $GameDir
    speed            = $Speed
    lastRun          = (Get-Date).ToUniversalTime().ToString('o')
  }
  $config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $GameDir '.au_installer_config.json') -Encoding UTF8
  Write-Log -Level 'OK' -Message ("Config saved to {0}" -f $GameDir)
}

function Show-WhatsNew {
  param([switch]$Force)

  $gd = $null
  $cfg = $null
  try {
    $gd = Resolve-GameDirSilent
    if ($gd) { $cfg = Get-InstallerConfig -GameDir $gd }
  } catch {}

  if (-not $Force) {
    $savedVer = $null
    if ($cfg -and $cfg.PSObject.Properties['installerVersion']) {
      $savedVer = $cfg.installerVersion
    }
    if ($savedVer -eq $script:InstallerVersion) { return }
  }

  Write-Host ''
  Show-Separator -Color 'Green'
  Write-Host "  What's New in v$($script:InstallerVersion)" -ForegroundColor Green
  Show-Separator -Color 'Green'
  Write-Host ''
  Write-Host '  Backend' -ForegroundColor Cyan
  Write-Host '    - Manifest-based installs: tracks every file for clean' -ForegroundColor Gray
  Write-Host '      uninstalls, updates, and repairs -- no leftover files' -ForegroundColor Gray
  Write-Host '    - Game version detection: reads actual game version' -ForegroundColor Gray
  Write-Host '      (e.g. 17.2.1) instead of Unity engine build number' -ForegroundColor Gray
  Write-Host '    - Compatibility checks: warns before installing if your' -ForegroundColor Gray
  Write-Host '      game version does not match the mod requirements' -ForegroundColor Gray
  Write-Host ''
  Write-Host '  User Experience' -ForegroundColor Cyan
  Write-Host '    - Live download progress bars with file size and percent' -ForegroundColor Gray
  Write-Host '    - Animated spinners during API calls' -ForegroundColor Gray
  Write-Host '    - Numbered step indicators during install/update/repair' -ForegroundColor Gray
  Write-Host '    - Summary boxes after every operation' -ForegroundColor Gray
  Write-Host '    - Auto-launch game offer after install' -ForegroundColor Gray
  Write-Host ''
  Show-Separator -Color 'Green'
  Write-Host ''
  Wait-KeyPress

  # Persist version so this only shows once
  if ($gd) { Save-InstallerConfig -GameDir $gd }
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
# State helpers
# ======================================================
function Find-TouMiraDll {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { return $null }
  foreach ($rel in @('BepInEx\plugins\TownOfUsMira.dll', 'TownOfUsMira.dll')) {
    $p = Join-Path $GameDir $rel
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}
function Test-ModInstalled {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
  return [bool](Find-TouMiraDll -GameDir $GameDir)
}
function Get-GameVersion {
  param([Parameter(Mandatory)][string]$GameDir)

  # Primary: parse from Unity Addressables settings.json (catalog_XX.YY.ZZ.hash)
  $settingsPath = Join-Path $GameDir 'Among Us_Data\StreamingAssets\aa\settings.json'
  if (Test-Path -LiteralPath $settingsPath) {
    try {
      $raw = Get-Content -Raw -LiteralPath $settingsPath
      if ($raw -match 'catalog_(\d+\.\d+(?:\.\d+)?)\.hash') {
        return $matches[1]
      }
    } catch {}
  }

  # Fallback: exe FileVersion (returns Unity engine version, not ideal)
  $exe = Join-Path $GameDir 'Among Us.exe'
  if (Test-Path $exe) { return (Get-Item $exe).VersionInfo.FileVersion }
  return $null
}
function Get-InstalledTouMiraVersion {
  param([string]$GameDir)
  try {
    if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
    if (-not $GameDir) { return $null }
    $dll = Find-TouMiraDll -GameDir $GameDir
    if ($dll) {
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
  # 10-minute session cache
  if ($script:__BclLatestCache -and $script:__BclLatestCache.Time -gt (Get-Date).AddMinutes(-10)) {
    return $script:__BclLatestCache.Value
  }

  Ensure-Tls12
  try {
    $api  = 'https://api.github.com/repos/OhMyGuus/BetterCrewLink/releases/latest'
    $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }
    Write-Log -Level 'ACTION' -Message ("GET {0}" -f $api)
    $raw = Invoke-ApiWithSpinner -Uri $api -Headers $hdrs -Label 'Checking for BetterCrewLink updates'
    $j = $raw | ConvertFrom-Json
    if ($j.tag_name) {
      $script:__BclLatestCache = @{ Time = Get-Date; Value = $j.tag_name }
      return $j.tag_name
    }
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
    if ($loc -and ($loc -match '/tag/([^/]+)$')) {
      $val = $matches[1]
      $script:__BclLatestCache = @{ Time = Get-Date; Value = $val }
      return $val
    }
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
    if (-not (Read-YN -Prompt 'Reinstall Better-CrewLink? (y/n): ')) { Write-Info "Skipping Better-CrewLink install."; return }
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
    Invoke-DownloadWithProgress -Uri $info.Url -OutFile $dest
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
    if (Read-YN -Prompt 'Still not detected. Return to menu? (y/n): ') { Write-Warn2 "Returning to menu without confirming Better-CrewLink installation."; return }
    Write-Info "Waiting 30 seconds more..."; Start-Sleep -Seconds 30
  }
  Write-Ok "Better-CrewLink detected as installed."
}

# ======================================================
# Robocopy helper (mod overlay)
# ======================================================
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

# ======================================================
# Mod download/install
# ======================================================

function Test-HttpUrlExists {
  param([Parameter(Mandatory)][string]$Url)

  Ensure-Tls12
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()

    # GitHub release assets often respond with 302 redirect to S3/CDN.
    return ($code -ge 200 -and $code -lt 400)
  } catch {
    return $false
  }
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

function Get-LatestTouMiraVersion {
  Ensure-Tls12

  # Simple in-session cache to avoid hammering GitHub every menu refresh
  if ($script:__TouMiraLatestCache -and $script:__TouMiraLatestCache.Time -gt (Get-Date).AddMinutes(-10)) {
    return $script:__TouMiraLatestCache.Value
  }

  $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }

  # 1) Try GitHub API with spinner
  try {
    $api = 'https://api.github.com/repos/AU-Avengers/TOU-Mira/releases/latest'
    Write-Log -Level 'ACTION' -Message ("GET {0}" -f $api)
    $raw = Invoke-ApiWithSpinner -Uri $api -Headers $hdrs -Label 'Checking for TOU-Mira updates'
    $j = $raw | ConvertFrom-Json

    $tag = $null
    if ($j.tag_name) { $tag = [string]$j.tag_name }
    elseif ($j.name) { $tag = [string]$j.name }

    if ($tag) {
      $val = Normalize-VersionTag $tag
      $body = if ($j.body) { [string]$j.body } else { $null }
      $script:__TouMiraLatestCache = @{ Time = Get-Date; Value = $val; Body = $body }
      return $val
    }
  } catch {
    # fall through to HTML/redirect method
  }

  # 2) Fallback: follow releases/latest redirect and parse /tag/<tag>
  try {
    $url = 'https://github.com/AU-Avengers/TOU-Mira/releases/latest'
    Write-Log -Level 'ACTION' -Message ("HEAD {0}" -f $url)

    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse()
    $loc  = $resp.Headers['Location']
    $resp.Close()

    if ($loc -and ($loc -match '/tag/([^/]+)$')) {
      $val = Normalize-VersionTag $matches[1]
      $script:__TouMiraLatestCache = @{ Time = Get-Date; Value = $val; Body = $null }
      return $val
    }
  } catch {}

  throw "Unable to determine latest TOU-Mira version."
}

# ======================================================
# Game version compatibility
# ======================================================
function Get-TouMiraCompatibleVersions {
  $body = $null
  if ($script:__TouMiraLatestCache -and $script:__TouMiraLatestCache.Body) {
    $body = $script:__TouMiraLatestCache.Body
  }
  if (-not $body) { return @() }

  $versions = @()
  # Match "SUPPORTS AMONG US 17.1 and 17.2.1"
  if ($body -match '(?i)supports\s+among\s+us\s+([\d.]+(?:\s+and\s+[\d.]+)*)') {
    $matches[1] -split '\s+and\s+' | ForEach-Object { $versions += $_.Trim() }
  }
  # Match "Among Us Version 17.1.0"
  elseif ($body -match '(?i)among\s+us\s+version\s+([\d.]+)') {
    $versions += $matches[1]
  }
  # Match "Among Us 17.0.1 - 17.1.0" (range)
  elseif ($body -match '(?i)among\s+us\s+([\d.]+)\s*-\s*([\d.]+)') {
    $versions += $matches[1]
    $versions += $matches[2]
  }

  return $versions
}

function Download-TouMiraAssets {
  param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$StageDir
  )

  Ensure-Tls12
  New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

  # Tag is WITHOUT 'v' (e.g. "1.4.1"), filename uses WITH 'v' (e.g. "v1.4.1")
  $verNoV  = Normalize-VersionTag $Version
  $tagNoV  = $verNoV
  $fileVer = "v$verNoV"

  $base = "https://github.com/AU-Avengers/TOU-Mira/releases/download/$tagNoV"

  # Primary (matches your link) + a couple reasonable fallbacks
  $candidateNames = @(
    "TouMira-$fileVer-x86-steam-itch.zip",
    "TouMira-$fileVer-x86-steam.zip",
    "TouMira-$fileVer-x86.zip",
    "TouMira-$fileVer.zip"
  )

  $picked = $null
  foreach ($name in $candidateNames) {
    $url = "$base/$name"
    Write-Log -Level 'ACTION' -Message ("HEAD {0}" -f $url)
    if (Test-HttpUrlExists -Url $url) {
      $picked = [pscustomobject]@{ Name = $name; Url = $url }
      break
    }
  }

  if (-not $picked) {
    throw "Unable to download TOU-Mira zip for version '$Version' (tag='$tagNoV', expected filename uses '$fileVer'). Tried: $($candidateNames -join ', ')"
  }

  $dest = Join-Path $StageDir $picked.Name
  Write-Info ("Downloading: {0}" -f $picked.Url)
  Write-Log  -Level 'ACTION' -Message ("GET {0}" -f $picked.Url)

  $hdrs = @{ 'Accept'='application/octet-stream' }
  Invoke-DownloadWithProgress -Uri $picked.Url -OutFile $dest -Headers $hdrs

  [pscustomobject]@{
    StageDir = $StageDir
    ZipPath  = $dest
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

  # Save manifest before copying (enumerate what we're about to add)
  $gameVer = Get-GameVersion -GameDir $GameDir
  Save-ModManifest -GameDir $GameDir -ContentRoot $contentRoot -ModVersion $Version -ModTag $Version -GameVersion $gameVer

  Write-Info 'Applying mod files to game directory...'
  Copy-TreeRobocopyQuiet -Source $contentRoot -Destination $GameDir -FileMask '*'

  Write-Ok 'Mod files applied.'
}

# ======================================================
# Install / Uninstall / Update orchestrations
# ======================================================
function Install-ToU {
  Initialize-Paths

  # Step 1: Find game directory
  Write-Step -Current 1 -Total 5 -Label 'Finding game directory'
  $gameDir = Resolve-GameDirInteractive
  if (-not $gameDir) { Write-Err2 "No valid '$($script:AppName)' instance found. Exiting."; return }
  $script:GameDir = $gameDir
  $gameVer = Get-GameVersion -GameDir $gameDir
  Write-Step -Current 1 -Total 5 -Label 'Finding game directory' -Done
  Write-Log -Level 'STATUS' -Message ("Install target: {0} (version {1})" -f $gameDir, $gameVer)

  # Step 2: Resolve latest TOU-Mira
  Write-Step -Current 2 -Total 5 -Label 'Resolving latest TOU-Mira'
  $modVersion = Get-LatestTouMiraVersion
  Write-Step -Current 2 -Total 5 -Label 'Resolving latest TOU-Mira' -Done

  # Step 3: Check compatibility
  Write-Step -Current 3 -Total 5 -Label 'Checking compatibility'
  $compatOk = $true
  try {
    $compatVersions = Get-TouMiraCompatibleVersions
    if ($compatVersions -and $compatVersions.Count -gt 0 -and $gameVer) {
      $gameVerNorm = Normalize-VersionTag $gameVer
      $isCompat = $false
      foreach ($cv in $compatVersions) {
        if ($gameVerNorm -like "$cv*") { $isCompat = $true; break }
      }
      if (-not $isCompat) {
        Write-Step -Current 3 -Total 5 -Label 'Checking compatibility' -Done
        Write-Warn2 "TOU-Mira $modVersion lists compatible versions: $($compatVersions -join ', ')"
        Write-Warn2 "Your game version ($gameVer) may not be compatible."
        Write-Host ''
        $ans = Read-YQ 'Continue anyway? (y/q): '
        if ($ans -eq 'q') { Write-TypeLines -Lines @('Aborted by user.') -Colors @('Yellow'); return }
        $compatOk = $false
      }
    }
  } catch {}
  if ($compatOk) { Write-Step -Current 3 -Total 5 -Label 'Checking compatibility' -Done }

  # Step 4: Download & install mod
  Write-Step -Current 4 -Total 5 -Label 'Downloading & installing mod'
  Install-TouMira -GameDir $gameDir -Version $modVersion
  $manifest = Get-ModManifest -GameDir $gameDir
  $fileCount = if ($manifest -and $manifest.files) { $manifest.files.Count } else { 0 }
  Write-Step -Current 4 -Total 5 -Label 'Downloading & installing mod' -Done

  # Summary box
  $summaryData = [ordered]@{
    'Mod version'    = $modVersion
    'Game version'   = $(if ($gameVer) { $gameVer } else { 'unknown' })
    'Files installed' = $fileCount
    'Game directory'  = $gameDir
  }
  Show-SummaryBox -Title 'Installation Complete' -Data $summaryData -Color 'Green'

  # Step 5: Save configuration
  Write-Step -Current 5 -Total 5 -Label 'Saving configuration'
  Save-InstallerConfig -GameDir $gameDir
  Write-Step -Current 5 -Total 5 -Label 'Saving configuration' -Done

  # Auto-launch offer
  Write-Host ''
  if (Read-YN -Prompt 'Launch Among Us now? (y/n): ') {
    Write-Info 'Launching Among Us...'
    try { Start-Process 'steam://rungameid/945360' } catch { Write-Warn2 "Could not launch: $($_.Exception.Message)" }
  }

  # Offer Better-CrewLink
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

function Uninstall-Mod {
  param([string]$GameDir)

  if (-not $GameDir) {
    $GameDir = Resolve-GameDirInteractive
    if (-not $GameDir) { Write-Err2 "No valid '$($script:AppName)' instance found."; return }
  }
  $script:GameDir = $GameDir

  $manifest = Get-ModManifest -GameDir $GameDir
  if (-not $manifest) {
    # Fallback: offer to remove known mod files
    Write-Warn2 'No install manifest found. Offering fallback removal of known mod files.'
    $knownFiles = @('winhttp.dll', 'doorstop_config.ini', '.doorstop_version')
    $knownDirs  = @('BepInEx', 'dotnet')
    $found = @()
    foreach ($f in $knownFiles) {
      $p = Join-Path $GameDir $f
      if (Test-Path -LiteralPath $p) { $found += $f }
    }
    foreach ($d in $knownDirs) {
      $p = Join-Path $GameDir $d
      if (Test-Path -LiteralPath $p) { $found += "$d/" }
    }
    # Also check for loose mod DLLs
    foreach ($dll in @('TownOfUsMira.dll', 'MiraAPI.dll')) {
      $p = Join-Path $GameDir $dll
      if (Test-Path -LiteralPath $p) { $found += $dll }
    }
    if (-not $found) { Write-Ok 'No mod files detected. Nothing to remove.'; return }
    Write-Info "Found mod files/folders: $($found -join ', ')"
    if (-not (Read-YN -Prompt 'Remove these files? (y/n): ')) { Write-Info 'Aborted.'; return }
    foreach ($f in ($knownFiles + @('TownOfUsMira.dll', 'MiraAPI.dll'))) {
      $p = Join-Path $GameDir $f
      if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch {} }
    }
    foreach ($d in $knownDirs) {
      $p = Join-Path $GameDir $d
      if (Test-Path -LiteralPath $p) {
        try {
          Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
          Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
        } catch {}
      }
    }
    $uninstSummary = [ordered]@{ 'Method' = 'Fallback (known files)'; 'Items removed' = $found.Count }
    Write-Ok 'Known mod files removed.'
  } else {
    $modVer = $manifest.modVersion
    $fileCount = $manifest.files.Count
    Write-Info "Manifest found: TOU-Mira $modVer, $fileCount files."
    if (-not (Read-YN -Prompt 'Uninstall TOU-Mira? This will remove all mod files. (y/n): ')) { Write-Info 'Aborted.'; return }
    Remove-ModFiles -GameDir $GameDir
    $uninstSummary = [ordered]@{ 'Mod version' = $modVer; 'Files removed' = $fileCount; 'Game directory' = $GameDir }
  }

  # Remove config
  $configPath = Join-Path $GameDir '.au_installer_config.json'
  if (Test-Path -LiteralPath $configPath) {
    try { Remove-Item -LiteralPath $configPath -Force -ErrorAction Stop } catch {}
  }

  Show-SummaryBox -Title 'Uninstall Complete' -Data $uninstSummary -Color 'Red'

  # Offer BCL uninstall
  try {
    if (Test-BCLInstalled) {
      Write-TypeLines -Lines @('Better-CrewLink is detected on this system. Do you want to uninstall it?') -Colors @('Magenta')
      if (Read-YN -Prompt 'Uninstall Better-CrewLink now? (y/n): ') {
        Uninstall-BetterCrewLink
      } else {
        Write-Info 'Keeping Better-CrewLink installed.'
      }
    }
  } catch {
    Write-Warn2 "Could not check/uninstall Better-CrewLink: $($_.Exception.Message)"
  }
}

function Update-ModPack {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
  if (-not $GameDir) { Write-Warn2 'Could not find game directory.'; return }

  Initialize-Paths

  # Step 1: Remove old mod files
  Write-Step -Current 1 -Total 3 -Label 'Removing current mod files'
  $manifest = Get-ModManifest -GameDir $GameDir
  if ($manifest) {
    Remove-ModFiles -GameDir $GameDir
  } else {
    Write-Info 'No manifest found; applying update as overlay.'
  }
  Write-Step -Current 1 -Total 3 -Label 'Removing current mod files' -Done

  # Step 2: Download and install latest
  Write-Step -Current 2 -Total 3 -Label 'Downloading & installing latest'
  $modVersion = Get-LatestTouMiraVersion
  Install-TouMira -GameDir $GameDir -Version $modVersion
  Write-Step -Current 2 -Total 3 -Label 'Downloading & installing latest' -Done

  # Step 3: Save config
  Write-Step -Current 3 -Total 3 -Label 'Saving configuration'
  Save-InstallerConfig -GameDir $GameDir
  Write-Step -Current 3 -Total 3 -Label 'Saving configuration' -Done

  $gameVer = Get-GameVersion -GameDir $GameDir
  $newManifest = Get-ModManifest -GameDir $GameDir
  $fileCount = if ($newManifest -and $newManifest.files) { $newManifest.files.Count } else { 0 }
  $summaryData = [ordered]@{
    'Mod version'     = $modVersion
    'Game version'    = $(if ($gameVer) { $gameVer } else { 'unknown' })
    'Files installed' = $fileCount
  }
  Show-SummaryBox -Title 'Update Complete' -Data $summaryData -Color 'Yellow'
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

  $modInstalled    = Test-ModInstalled -GameDir $gameDir
  $bclInstalled    = Test-BCLInstalled
  $manifest        = if ($gameDir) { Get-ModManifest -GameDir $gameDir } else { $null }
  $manifestExists  = [bool]$manifest
  $gameVersion     = if ($gameDir) { Get-GameVersion -GameDir $gameDir } else { $null }

  $modNeedsUpdate = $false
  if ($installedMod -and $latestMod) { if ((Compare-Versions $installedMod $latestMod) -lt 0) { $modNeedsUpdate = $true } }
  $bclNeedsUpdate = $false
  if ($installedBcl -and $latestBcl) { if ((Compare-Versions $installedBcl $latestBcl) -lt 0) { $bclNeedsUpdate = $true } }
  $anyUpdate = ($modNeedsUpdate -or $bclNeedsUpdate)

  [pscustomobject]@{
    GameDir          = $gameDir
    GameVersion      = $gameVersion
    ModInstalled     = $modInstalled
    BclInstalled     = $bclInstalled
    ManifestExists   = $manifestExists
    AnyUpdate        = $anyUpdate
    ModNeedsUpdate   = $modNeedsUpdate
    BclNeedsUpdate   = $bclNeedsUpdate
    RepairAvailable  = ($modInstalled -or $bclInstalled)
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
  Write-Log -Level 'STATUS' -Message ("GameVersion: {0}" -f (Coalesce $m.GameVersion '<n/a>'))
  Write-Log -Level 'STATUS' -Message ("ModInstalled: {0}, Version: {1}, Latest: {2}" -f $m.ModInstalled, (Coalesce $m.InstalledModVer '<n/a>'), (Coalesce $m.LatestMod '<n/a>'))
  Write-Log -Level 'STATUS' -Message ("BCL Installed: {0}, Version: {1}, Latest: {2}" -f $m.BclInstalled, (Coalesce $m.InstalledBclVer '<n/a>'), (Coalesce $m.LatestBcl '<n/a>'))
  Write-Log -Level 'STATUS' -Message ("ManifestExists: {0}" -f $m.ManifestExists)
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
  $modeText = if ($script:speed -le 0) { 'Fast' } else { 'Normal' }

  if ($m.GameVersion) {
    Write-Host -NoNewline 'Among Us: ' -ForegroundColor Cyan
    Write-Host $m.GameVersion -ForegroundColor Yellow
  }

  Write-Host -NoNewline 'TOU-Mira: ' -ForegroundColor Cyan
  if ($modBadge) { Write-Host -NoNewline $modText -ForegroundColor Yellow; Write-Host (' ' + $modBadge) -ForegroundColor Yellow }
  else { Write-Host $modText -ForegroundColor Yellow }

  Write-Host -NoNewline 'BetterCrewLink: ' -ForegroundColor Cyan
  if ($bclBadge) { Write-Host -NoNewline $bclText -ForegroundColor Yellow; Write-Host (' ' + $bclBadge) -ForegroundColor Yellow }
  else { Write-Host $bclText -ForegroundColor Yellow }

  Write-Host -NoNewline 'Display: ' -ForegroundColor Cyan
  Write-Host $modeText -ForegroundColor Yellow
}

function Show-Menu {
  param([psobject]$State)
  $m = if ($PSBoundParameters.ContainsKey('State') -and $State) { $State } else { Get-MenuAvailability }

  Write-Host ''
  Write-Host ''
  $line1 = if ($m.ModInstalled) { '  1) Install Among Us - ToU Mira (already installed)' } else { '  1) Install Among Us - ToU Mira' }
  $line2 = if ($m.AnyUpdate) { '  2) Update' } else { '  2) Update (no updates available)' }
  $line3 = if ($m.ModInstalled) { '  3) Uninstall TOU-Mira' } else { '  3) Uninstall TOU-Mira (not installed)' }
  $line4 = if ($m.BclInstalled) { '  4) Install BetterCrewLink (already installed)' } else { '  4) Install BetterCrewLink' }
  $line5 = if ($m.RepairAvailable) { '  5) Repair' } else { '  5) Repair (nothing to repair)' }

  Write-TypeLines -Lines @($line1,$line2,$line3,$line4,$line5,'  W) What''s New','  F) Toggle fast mode','  Q) Quit') -TotalSeconds $script:speed -Colors @(
    $(if ($m.ModInstalled) {'DarkGray'} else {'Green'}),
    $(if ($m.AnyUpdate) {'Yellow'} else {'DarkGray'}),
    $(if ($m.ModInstalled) {'Red'} else {'DarkGray'}),
    $(if ($m.BclInstalled) {'DarkGray'} else {'Magenta'}),
    $(if ($m.RepairAvailable) {'Yellow'} else {'DarkGray'}),
    'DarkCyan',
    'Cyan',
    'DarkGray'
  )
  Write-Host ''
  Write-Host ''
}

function Repair-Mod {
  param([string]$GameDir)
  if (-not $GameDir -or -not (Test-Path $GameDir)) { $GameDir = Resolve-GameDirSilent }
  if (-not $GameDir) { Write-Warn2 'Could not find game directory.'; return }

  Initialize-Paths

  # Step 1: Remove existing mod files
  Write-Step -Current 1 -Total 3 -Label 'Removing current mod files'
  $manifest = Get-ModManifest -GameDir $GameDir
  if ($manifest) {
    Remove-ModFiles -GameDir $GameDir
  }
  Write-Step -Current 1 -Total 3 -Label 'Removing current mod files' -Done

  # Step 2: Re-install latest
  Write-Step -Current 2 -Total 3 -Label 'Re-installing latest TOU-Mira'
  try {
    $modVersion = Get-LatestTouMiraVersion
    Install-TouMira -GameDir $GameDir -Version $modVersion
    Write-Step -Current 2 -Total 3 -Label 'Re-installing latest TOU-Mira' -Done
  } catch {
    Write-Err2 "Re-install failed: $($_.Exception.Message)"
    return
  }

  # Step 3: Save config
  Write-Step -Current 3 -Total 3 -Label 'Saving configuration'
  Save-InstallerConfig -GameDir $GameDir
  Write-Step -Current 3 -Total 3 -Label 'Saving configuration' -Done

  $gameVer = Get-GameVersion -GameDir $GameDir
  $newManifest = Get-ModManifest -GameDir $GameDir
  $fileCount = if ($newManifest -and $newManifest.files) { $newManifest.files.Count } else { 0 }
  $summaryData = [ordered]@{
    'Mod version'     = $modVersion
    'Game version'    = $(if ($gameVer) { $gameVer } else { 'unknown' })
    'Files installed' = $fileCount
  }
  Show-SummaryBox -Title 'Repair Complete' -Data $summaryData -Color 'Yellow'
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
  param([string]$GameDir)
  try { Repair-Mod -GameDir $GameDir } catch { Write-Warn2 "Mod repair encountered an issue: $($_.Exception.Message)" }
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
      '1' { Repair-All -GameDir $m.GameDir;  return }
      '2' { Repair-Mod -GameDir $m.GameDir;  return }
      '3' { Repair-BCL;                      return }
      '4' { Write-Info 'Aborted.';           return }
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
      '2' { Update-ToUMiraSmart -GameDir $gameDir; break }
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

# Load persisted config
try {
  $savedGameDir = Resolve-GameDirSilent
  if ($savedGameDir) {
    $cfg = Get-InstallerConfig -GameDir $savedGameDir
    if ($cfg) {
      if ($null -ne $cfg.speed) { $script:speed = $cfg.speed }
      if ($cfg.gameDir -and (Test-Path $cfg.gameDir)) { $script:GameDir = $cfg.gameDir }
      Write-Log -Level 'INFO' -Message ("Config loaded: speed={0}, gameDir={1}" -f $script:speed, $script:GameDir)
    }
  }
} catch {
  Write-Log -Level 'WARN' -Message ("Config load failed: {0}" -f $_.Exception.Message)
}

Show-WhatsNew

try {
  $state = Get-MenuAvailability
  Write-LogSection -Title "INITIAL INSTALLED COMPONENTS"
  Write-Log -Level 'STATUS' -Message ("TOU-Mira: {0}" -f ($(if ($state.InstalledModVer) { $state.InstalledModVer } else { 'Not installed' })))
  Write-Log -Level 'STATUS' -Message ("BetterCrewLink: {0}" -f ($(if ($state.InstalledBclVer) { $state.InstalledBclVer } else { 'Not installed' })))
} catch {
  Write-Log -Level 'ERROR' -Message ("Initial snapshot failed: {0}" -f $_.Exception.Message)
}

:MainMenu while ($true) {
  try {
    Clear-Host
    $m = Get-MenuAvailability
    Show-Banner
    Show-Separator
    Show-StatusPanel -State $m
    Show-Separator
    Show-Menu -State $m

    $allowed = @('1','2','3','4','5','w','W','f','F','q','Q')
    $choice  = Read-Choice -Prompt 'Select option (1-5, W, F, Q and press ENTER) [1]:' -Allowed $allowed -Default '1'

    switch -Regex ($choice) {
      '^1$' {
        if ($m.ModInstalled) { Write-Warn2 'Mod is already installed.' }
        else { try { Install-ToU } finally { Remove-WorkingFolder } }
      }
      '^2$' {
        if (-not $m.AnyUpdate) { Write-Ok 'No updates available.' }
        else { try { Invoke-UpdateFlow } finally { Remove-WorkingFolder } }
      }
      '^3$' {
        if (-not $m.ModInstalled) { Write-Warn2 'TOU-Mira is not installed -- nothing to uninstall.' }
        else { try { Uninstall-Mod -GameDir $m.GameDir } finally { Remove-WorkingFolder } }
      }
      '^4$' {
        if ($m.BclInstalled) { Write-Warn2 'Better-CrewLink is already installed.' }
        else { try { Install-BetterCrewLink } finally { Remove-WorkingFolder } }
      }
      '^5$' {
        if (-not $m.RepairAvailable) { Write-Ok 'Nothing to repair right now.' }
        else { try { Invoke-RepairFlow } finally { Remove-WorkingFolder } }
      }
      '^[wW]$' {
        Show-WhatsNew -Force
      }
      '^[fF]$' {
        if ($script:speed -le 0) { $script:speed = 1; Write-Ok 'Display mode: Normal' }
        else { $script:speed = 0; Write-Ok 'Display mode: Fast' }
        if ($m.GameDir) { Save-InstallerConfig -GameDir $m.GameDir }
      }
      '^[qQ]$' {
        Write-TypeLines -Lines @('Goodbye!') -TotalSeconds $script:speed -Colors @('Green')
        Remove-WorkingFolder
        break MainMenu
      }
    }

    if ($choice -notmatch '^[fFqQwW]$') {
      Invoke-CompletionBeep
      Wait-KeyPress
    }
  }
  catch {
    Write-Err2 "ERROR: $($_.Exception.Message)"
    Write-TypeLines -Lines @('Returning to menu...') -TotalSeconds $script:speed -Colors @('Yellow')
    Wait-KeyPress
  }
}

Write-Log -Level 'INFO' -Message ("===== Session End =====")
