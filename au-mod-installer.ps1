# Requires PowerShell 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

# -------------------------
# Config / Constants
# -------------------------
$script:AppId   = 945360
$script:AppName = 'Among Us'

# -------------------------
# UI helpers
# -------------------------
function Show-ProgressDots {
  param([string]$Label = 'Working', [int]$Seconds = 3)
  $frames = @('....','.........','.............')
  for ($i=0; $i -lt $Seconds; $i++) {
    $dots = if ($i -lt $frames.Count) { $frames[$i] } else { '.' * (4 + 4*$i) }
    Write-Host -NoNewline ("`r{0} {1} " -f $Label, $dots)
    Start-Sleep -Seconds 1
  }
  Write-Host
}

function Write-TypeLines {
  param(
    [Parameter(Mandatory)][string[]]$Lines,
    [double]$TotalSeconds = 1.4,
    [string[]]$Colors
  )
  $totalChars = ($Lines | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum
  if ($totalChars -lt 1) { $totalChars = 1 }
  $delayMs = [int][Math]::Round(($TotalSeconds * 1000) / $totalChars)
  $delayMs = [Math]::Max(5, [Math]::Min(30, $delayMs))
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

# Route all info/warn/ok/err through typewriter (1.4s lines)
function Write-Info  { param([string]$m) Write-TypeLines -Lines @($m) -TotalSeconds 1 -Colors @('Cyan') }
function Write-Ok    { param([string]$m) Write-TypeLines -Lines @($m) -TotalSeconds 1 -Colors @('Green') }
function Write-Warn2 { param([string]$m) Write-TypeLines -Lines @($m) -TotalSeconds 1 -Colors @('Yellow') }
function Write-Err2  { param([string]$m) Write-TypeLines -Lines @($m) -TotalSeconds 1 -Colors @('Red') }

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

function Read-Choice {
  param([string]$Prompt,[ValidateSet('1','2','3','4','q','Q')]$Default)
  while ($true) {
    $in = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($in)) { $in = $Default }
    switch ($in) { '1' {return '1'} '2' {return '2'} '3' {return '3'} '4' {return '4'} 'q' {return 'q'} 'Q' {return 'q'} }
    Write-Warn2 'Please enter 1, 2, 3, 4 or Q. and press ENTER'
  }
}


function Read-YQ {
  param([string]$Prompt = 'Continue? (Y - Yes, q - Quit and press ENTER):')
  while ($true) {
    $in = (Read-Host $Prompt).Trim()
    if ($in -match '^(y|Y)$') { return 'y' }
    if ($in -match '^(q|Q)$') { return 'q' }
    Write-Warn2 "Please type 'Y' to continue or 'Q' to quit."
  }
}

function Read-YN {
  param([string]$Prompt = 'Install Better-CrewLink now? (Y - for Yes, N - for No and press ENTER): ')
  while ($true) {
    $in = (Read-Host $Prompt).Trim()
    if ($in -match '^(y|Y)$') { return $true }
    if ($in -match '^(n|N)$') { return $false }
    Write-Warn2 "Please type 'y' or 'n' and press ENTER."
  }
}


function Show-Menu {
  Write-Host ''
  Write-Host ''
  Write-TypeLines -Lines @(
    '  1) Install Among Us - ToU Mira',
    '  2) Update',
    '  3) Restore Vanilla',
    '  4) Install BetterCrewLink',
    '  Q) Quit'
  ) -Colors @('Green','Yellow','Red','Magenta','DarkGray')
  Write-Host ''
  Write-Host ''
}

# -------------------------
# Paths / Folders
# -------------------------
function Initialize-Paths {
  $base = Join-Path $env:USERPROFILE 'Downloads\AmongUsModInstaller'
  $paths = [pscustomobject]@{
    Base      = $base
    Tools     = Join-Path $base 'tools'
    Temp      = Join-Path $base 'temp'
    Downloads = Join-Path $base 'downloads'
  }
  foreach ($p in $paths.PSObject.Properties.Value) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
  }
  $script:Paths = $paths
}

function Remove-WorkingFolder {
  if (-not $script:Paths -or -not (Test-Path $script:Paths.Base)) { return }
  Write-Info "Cleaning up: $($script:Paths.Base)"
  try {
    Get-ChildItem -LiteralPath $script:Paths.Base -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try { $_.Attributes = 'Normal' } catch {}
    }
    Remove-Item -LiteralPath $script:Paths.Base -Recurse -Force -ErrorAction Stop
    Write-Ok 'Cleanup complete.'
  } catch {
    Write-Warn2 "Cleanup failed: $($_.Exception.Message)"
  }
}

# -------------------------
# Networking
# -------------------------
function Ensure-Tls12 {
  try {
    [Net.ServicePointManager]::SecurityProtocol = `
      [Net.SecurityProtocolType]::Tls12 -bor `
      [Net.SecurityProtocolType]::Tls13
  } catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  }
}

# -------------------------
# Steam discovery
# -------------------------
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

function Test-DirHasContent {
  param([Parameter(Mandatory)][string]$Path)
  try {
    $any = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop | Select-Object -First 1
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

# -------------------------
# Folder picker
# -------------------------
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

# -------------------------
# Backup helpers
# -------------------------
function Get-ExeVersion {
  param([Parameter(Mandatory)][string]$GameDir)
  $exe = Join-Path $GameDir 'Among Us.exe'
  if (Test-Path $exe) { return (Get-Item $exe).VersionInfo.FileVersion }
  return $null
}

function Get-DirStat {
  param([Parameter(Mandatory)][string]$Path)
  $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue
  [PSCustomObject]@{
    Count = ($files | Measure-Object).Count
    Bytes = ($files | Measure-Object -Property Length -Sum).Sum
  }
}

function Copy-TreeRobocopy {
  param([Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $args = @("$Source","$Destination","/E","/COPY:DAT","/R:2","/W:1","/MT:8","/ETA")
  & robocopy @args | Out-Host
  $code = $LASTEXITCODE
  if ($code -ge 8) { throw "Robocopy failed with code $code" }
  return $code
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
  param(
    [Parameter(Mandatory)][string]$BackupDir,
    [Parameter(Mandatory)][string]$GameDir,
    [Parameter(Mandatory)]$Stat,
    [string]$ExeVersion,
    [string]$ModVersion
  )
  $meta = [pscustomobject]@{
    created    = (Get-Date)
    gameDir    = $GameDir
    exeVersion = $ExeVersion
    count      = $Stat.Count
    bytes      = [int64]$Stat.Bytes
    modVersion = $ModVersion
  }
  $meta | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $BackupDir '.au_backup_meta.json') -Encoding UTF8
}

function Save-BackupMetaModVersion {
  param([Parameter(Mandatory)][string]$BackupDir,[Parameter(Mandatory)][string]$Version)
  $metaPath = Join-Path $BackupDir '.au_backup_meta.json'
  $meta = if (Test-Path $metaPath) {
    Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json
  } else { [pscustomobject]@{} }
  $meta.modVersion = $Version
  $meta | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $metaPath -Encoding UTF8
}

function Test-BackupIntegrity {
  param([Parameter(Mandatory)][string]$GameDir,[Parameter(Mandatory)][string]$BackupDir)
  $g = Get-DirStat -Path $GameDir
  $b = Get-DirStat -Path $BackupDir
  Write-Info ("Backup integrity - files: {0} vs {1}, bytes: {2:N0} vs {3:N0}" -f $g.Count,$b.Count,$g.Bytes,$b.Bytes)
  return (($g.Count -eq $b.Count) -and ([int64]$g.Bytes -eq [int64]$b.Bytes))
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


# -------------------------
# Mod version & download/install
# -------------------------
function Get-LatestTouMiraVersion {
  Ensure-Tls12
  try {
    $api  = 'https://api.github.com/repos/AU-Avengers/TOU-Mira/releases/latest'
    $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }
    $r = Invoke-WebRequest -UseBasicParsing -Uri $api -Headers $hdrs -ErrorAction Stop
    $j = $r.Content | ConvertFrom-Json
    if ($j.tag_name) { return $j.tag_name }
  } catch {}
  try {
    $url = 'https://github.com/AU-Avengers/TOU-Mira/releases/latest'
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse(); $loc = $resp.Headers['Location']; $resp.Close()
    if ($loc -and ($loc -match '/tag/([^/]+)$')) { return $matches[1] }
  } catch {}
  throw "Unable to determine latest TOU-Mira version."
}

function Expand-Zip {
  param([Parameter(Mandatory)][string]$ZipPath,[Parameter(Mandatory)][string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
  } else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
  }
}

function Download-TouMiraAssets {
  param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$StageDir)
  Ensure-Tls12
  New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
  $base  = "https://github.com/AU-Avengers/TOU-Mira/releases/download/$Version"
  $items = @(
    @{ Name='MiraAPI.dll'; Url="$base/MiraAPI.dll" },
    @{ Name='TownOfUsMira.dll'; Url="$base/TownOfUsMira.dll" },
    @{ Name="TouMira-$Version-x86-steam-itch.zip"; Url="$base/TouMira-$Version-x86-steam-itch.zip" }
  )
  foreach ($it in $items) {
    $dest = Join-Path $StageDir $it.Name
    Write-Info "Downloading: $($it.Url)"
    Invoke-WebRequest -UseBasicParsing -Uri $it.Url -OutFile $dest
  }
  [pscustomobject]@{
    StageDir = $StageDir
    MiraApi  = Join-Path $StageDir 'MiraAPI.dll'
    TouMira  = Join-Path $StageDir 'TownOfUsMira.dll'
    ZipPath  = Join-Path $StageDir "TouMira-$Version-x86-steam-itch.zip"
  }
}

function Copy-TreeRobocopyQuiet {
  param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination,[string]$FileMask = '*')
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  & robocopy $Source $Destination $FileMask /E /R:2 /W:1 /MT:8
  if ($LASTEXITCODE -ge 8) { throw "Robocopy failed (mods) with code $LASTEXITCODE" }
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

  # --- offer Better-CrewLink install ---
  Write-Host ''
  Write-TypeLines -Lines @(
  'Would you like to install Better-CrewLink (proximity voice chat) as well?'
  ) -TotalSeconds 1.4 -Colors @('Magenta')

  if (Read-YN -Prompt 'Install Better-CrewLink now? (y/n): ') {
    Write-TypeLines -Lines @('Launching Better-CrewLink installer...') -TotalSeconds 1.4 -Colors @('Green')
    Install-BetterCrewLink
  } else {
   Write-TypeLines -Lines @('Skipping Better-CrewLink.') -TotalSeconds 1.4 -Colors @('Yellow')
  }

}

# -------------------------
# Resolve game path (UI + detection)
# -------------------------
function Resolve-GameDirInteractive {
  Show-ProgressDots -Label 'Searching for Game Directory' -Seconds 3
  $roots = Get-SteamRoot
  $libs  = Get-SteamLibraries -SteamRoots $roots
  $auto  = Get-GamePath -CommonRoots $libs
  if ($auto) {
    Write-TypeLines -Lines @("Found '$($script:AppName)' Installation: $auto") -Colors @('Green')
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
    if (Test-Path (Join-Path $pick 'Among Us.exe')) { return (Resolve-Path $pick).Path }
    Write-Warn2 "Selected folder does NOT contain 'Among Us.exe'."
    $ans = Read-YQ "Pick another folder? (y/q): "
    if ($ans -eq 'q') { return $null }
  }
}

# -------------------------
# Workflows
# -------------------------
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

  Write-Host ''
  Write-TypeLines -Lines @('-' * 47) -Colors @('Red')
  Write-Host ''

  Write-TypeLines -Lines @(
    'Manual validation (Steam client):',
    "  Library -> Right-click '$($script:AppName)' -> Properties -> Installed Files -> Verify integrity of game files"
  ) -Colors @('Cyan','DarkGray')

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

  function Find-BackupDir {
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
      $bckOnly = Find-BackupDir
      if (-not $bckOnly) { Write-Err2 "No backup found. Nothing to restore."; return }
      $parent  = Split-Path -Parent $bckOnly
      $GameDir = Join-Path $parent 'Among Us'
    }
  }

  $GameDir   = (Resolve-Path $GameDir).Path
  $parentDir = Split-Path -Parent $GameDir
  $BackupDir = Join-Path $parentDir 'Among Us - Bck'

  if (-not (Test-Path $BackupDir)) {
    $found = Find-BackupDir
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
  if ((Read-YQ "Proceed? (y/q): ") -eq 'q') { Write-Host 'Restore aborted.' -ForegroundColor Yellow; return }

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
    if (Test-Path $GameDir) {
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      Rename-Item -LiteralPath $GameDir -NewName ("Among Us (old $stamp)")
    }
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

  # --- Offer Better-CrewLink uninstall after restore ---
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

# --- BetterCrewLink (3rd party) ---

function Get-LatestBetterCrewLinkVersion {
  Ensure-Tls12
  try {
    $api  = 'https://api.github.com/repos/OhMyGuus/BetterCrewLink/releases/latest'
    $hdrs = @{ 'User-Agent'='AU-Installer'; 'Accept'='application/vnd.github+json' }
    $r = Invoke-WebRequest -UseBasicParsing -Uri $api -Headers $hdrs -ErrorAction Stop
    $j = $r.Content | ConvertFrom-Json
    if ($j.tag_name) { return $j.tag_name }  # e.g. "v3.1.4"
  } catch {}
  try {
    $url = 'https://github.com/OhMyGuus/BetterCrewLink/releases/latest'
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'AU-Installer'
    $resp = $req.GetResponse()
    $loc  = $resp.Headers['Location']
    $resp.Close()
    if ($loc -and ($loc -match '/tag/([^/]+)$')) { return $matches[1] } # includes 'v'
  } catch {}
  throw "Unable to determine latest BetterCrewLink version."
}

function Get-BCLDownloadInfo {
  param([Parameter(Mandatory)][string]$Tag)  # e.g. v3.1.4
  $verNoV = if ($Tag.StartsWith('v')) { $Tag.Substring(1) } else { $Tag }
  $name   = "Better-CrewLink-Setup-$verNoV.exe"
  $url    = "https://github.com/OhMyGuus/BetterCrewLink/releases/download/$Tag/$name"
  [pscustomobject]@{ Tag = $Tag; Version = $verNoV; Name = $name; Url = $url }
}

function Test-BCLInstalled {
  # Fast path: default install locations
  $defaultDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\bettercrewlink'),
    (Join-Path $env:LOCALAPPDATA 'Programs\BetterCrewLink')
  )
  foreach ($d in $defaultDirs) {
    $exe = Join-Path $d 'Better-CrewLink.exe'
    if (Test-Path $exe) { return $true }
  }

  # StrictMode-safe registry check (HKCU first for per-user installs)
  try {
    $keys = @(
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $hit = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
           Where-Object {
             $_.PSObject.Properties['DisplayName'] -and
             ($_.DisplayName -match '(?i)\bBetter[- ]?CrewLink\b')
           } |
           Select-Object -First 1
    if ($hit) { return $true }
  } catch {}

  # Package provider (limit to Programs to avoid NuGet noise)
  try {
    $pkg = Get-Package -ProviderName Programs -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match '(?i)\bBetter[- ]?CrewLink\b' } |
           Select-Object -First 1
    if ($pkg) { return $true }
  } catch {}

  return $false
}

function Get-BCLUninstallEntry {
  # HKCU first (per-user installs), then machine-wide
  $keys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
    Where-Object {
      $_.PSObject.Properties['DisplayName'] -and
      ($_.DisplayName -match '(?i)\bBetter[- ]?CrewLink\b')
    } |
    Select-Object -First 1 DisplayName, UninstallString
}

function Uninstall-BetterCrewLink {
  $entry = Get-BCLUninstallEntry
  if (-not $entry -or -not $entry.UninstallString) {
    Write-Warn2 "Could not find an uninstall entry for Better-CrewLink."
    return
  }
  Write-Info  "Uninstalling: $($entry.DisplayName)"
  Write-Info  "Command: $($entry.UninstallString) /S"

  # Parse executable + args from UninstallString (handles quoted path)
  $cmdLine = $entry.UninstallString
  $exePath = $null; $exeArgs = $null
  if ($cmdLine -match '^\s*"(.*?)"\s*(.*)$') {
    $exePath = $matches[1]; $exeArgs = $matches[2]
  } else {
    $parts = $cmdLine.Split(' ',2)
    $exePath = $parts[0]; $exeArgs = if ($parts.Count -gt 1) { $parts[1] } else { '' }
  }
  $exeArgs = ($exeArgs + ' /S').Trim()

  try {
    $p = Start-Process -FilePath $exePath -ArgumentList $exeArgs -PassThru -WindowStyle Hidden -ErrorAction Stop
    $p.WaitForExit()
    Start-Sleep -Seconds 3
    Write-Ok "Uninstall finished (code $($p.ExitCode))."

    # On successful uninstall, clean up empty folder under %LOCALAPPDATA%\Programs\bettercrewlink
    if ($p.ExitCode -eq 0) {
      $bclDir = Join-Path $env:LOCALAPPDATA 'Programs\bettercrewlink'
      if (Test-Path $bclDir) {
        # Remove only if there are no files left (subfolders allowed)
        $hasFiles = $false
        try {
          $f = Get-ChildItem -LiteralPath $bclDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
          $hasFiles = [bool]$f
        } catch {}

        if (-not $hasFiles) {
          try {
            # clear readonly attributes and remove
            Get-ChildItem -LiteralPath $bclDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
              try { $_.Attributes = 'Normal' } catch {}
            }
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
      while ($true) { $in = (Read-Host $Prompt).Trim(); if ($in -match '^(y|Y)$'){return $true}; if($in -match '^(n|N)$'){return $false}; Write-Warn2 "Please type 'y' or 'n'." }
    }
    if (-not (Read-YNLocal)) { Write-Info "Skipping Better-CrewLink install."; return }
    try { Uninstall-BetterCrewLink } catch { Write-Warn2 "Uninstall step failed: $($_.Exception.Message)" }
  }

  Write-Info 'Resolving latest Better-CrewLink version from GitHub...'
  $tag   = Get-LatestBetterCrewLinkVersion         # e.g., v3.1.4
  $info  = Get-BCLDownloadInfo -Tag $tag           # builds proper URL & filename
  Write-Ok "Latest Better-CrewLink: $($info.Tag)"

  $dest = Join-Path $script:Paths.Downloads $info.Name
  Write-Info "Downloading installer: $($info.Name)"
  try {
    $hdrs = @{ 'User-Agent'='AU-Installer' }
    Invoke-WebRequest -UseBasicParsing -Uri $info.Url -OutFile $dest -Headers $hdrs -ErrorAction Stop
    Write-Ok "Saved: $dest"
  } catch {
    Write-Err2 "Download failed ($($info.Url)): $($_.Exception.Message)"
    return
  }

  Write-Info "Launching installer..."
  try {
    Start-Process -FilePath $dest -ErrorAction Stop | Out-Null
  } catch {
    Write-Err2 "Failed to launch installer: $($_.Exception.Message)"; return
  }

  # Poll for install completion
  $totalWait = 20; $step = 4; $elapsed = 0
  while ($elapsed -lt $totalWait) {
    Start-Sleep -Seconds $step; $elapsed += $step
    if (Test-BCLInstalled) { Write-Ok "Better-CrewLink detected as installed."; return }
  }

  while (-not (Test-BCLInstalled)) {
    function Read-YNLocal2 { param([string]$Prompt='Still not detected. Return to menu? (Y - for Yes, N - for No and press ENTER):')
      while ($true) { $in = (Read-Host $Prompt).Trim(); if ($in -match '^(y|Y)$'){return $true}; if($in -match '^(n|N)$'){return $false}; Write-Warn2 "Please type 'y' or 'n'." }
    }
    if (Read-YNLocal2) { Write-Warn2 "Returning to menu without confirming Better-CrewLink installation."; return }
    Write-Info "Waiting 30 seconds more..."; Start-Sleep -Seconds 30
  }
  Write-Ok "Better-CrewLink detected as installed."
}

# =========================
# MAIN (interactive, loops back)
# =========================
:MainMenu while ($true) {
  try {
    Show-Banner
    Show-Menu

    $choice = Read-Choice -Prompt 'Select option (1/2/3/4 or Q to quit and press ENTER) [1]:' -Default '1'
    switch ($choice) {
      '1' { try { Install-ToU }            finally { Remove-WorkingFolder }; Write-TypeLines -Lines @('Done. Returning to menu...') -Colors @('Green') }
      '2' { try { Update-ModPack }         finally { Remove-WorkingFolder }; Write-TypeLines -Lines @('Done. Returning to menu...') -Colors @('Green') }
      '3' { try { Restore-Vanilla }        finally { Remove-WorkingFolder }; Write-TypeLines -Lines @('Done. Returning to menu...') -Colors @('Green') }
      '4' { try { Install-BetterCrewLink } finally { Remove-WorkingFolder }; Write-TypeLines -Lines @('Done. Returning to menu...') -Colors @('Green') }
      'q' {
        Write-TypeLines -Lines @('Goodbye!') -TotalSeconds 1.4 -Colors @('Green')
        Remove-WorkingFolder
        break MainMenu   # exits the while loop
      }
    }

    Start-Sleep -Milliseconds 700
  }
  catch {
    Write-TypeLines -Lines @("ERROR: $($_.Exception.Message)", 'Returning to menu...') -TotalSeconds 1.4 -Colors @('Red','Yellow')
    Start-Sleep -Milliseconds 900
  }
}
