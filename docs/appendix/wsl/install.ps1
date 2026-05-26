# Mandragora WSL install -- single-file orchestrator.
#
# Usage on a Win 11 host with WSL2 already installed (regular PowerShell):
#   iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/wsl/install.ps1)
#
# WSL2 must already be present on the host. The script aborts with a
# clear error if `wsl --version` fails. To install WSL2 itself (one-time,
# admin) ask your administrator or run on a personal box:
#     wsl --install --no-distribution
#     reboot
#
# Tunables (set before running):
#   $env:MANDRAGORA_RICE     = '1'      # opt in to Windows cosmetic / privacy registry tweaks (default OFF; needs admin)
#   $env:MANDRAGORA_PERSONAL = '1'      # opt in to mvrozanti's personal config (git identity, aerc/khal/notmuch dotfiles)
#   $env:MANDRAGORA_FORCE    = '1'      # bypass the managed-device safety prompt
#   $env:MANDRAGORA_REPO     = 'https://github.com/<fork>/mandragora.git'
#   $env:MANDRAGORA_REPLACE  = 'all'    # auto-answer every conflict prompt with Yes
#   $env:MANDRAGORA_REPLACE  = 'none'   # auto-answer every conflict prompt with No (keep existing)
#
# Default behaviour: imports NixOS-WSL as a sibling distro and runs the
# mandragora-wsl bootstrap inside it. Does not touch any other distro.

$ErrorActionPreference = 'Stop'
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/wsl'
$REPO = $env:MANDRAGORA_REPO; if (-not $REPO) { $REPO = 'https://github.com/mvrozanti/mandragora.git' }
$RICE     = ($env:MANDRAGORA_RICE -eq '1')
$PERSONAL = ($env:MANDRAGORA_PERSONAL -eq '1')
$FORCE    = ($env:MANDRAGORA_FORCE -eq '1')

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WslDistroExists {
    param([Parameter(Mandatory)] [string] $Name)
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $raw = & wsl.exe --list --quiet 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $false }
        $clean = (($raw | Out-String) -replace "`0",'')
        $lines = $clean -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return ($lines -contains $Name)
    } finally { $ErrorActionPreference = $prevEAP }
}

function Get-WslGuestHostname {
    param([Parameter(Mandatory)] [string] $Name)
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $raw = & wsl.exe -d $Name -- cat /etc/hostname 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return '' }
        return ((($raw | Out-String) -replace "`0",'') -split "`r?`n" |
                ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1)
    } finally { $ErrorActionPreference = $prevEAP }
}

$script:NERD_FONT_FACE = 'JetBrainsMono Nerd Font'
$script:NERD_FONT_WINGET_ID = 'DEVCOM.JetBrainsMonoNerdFont'
$script:NERD_FONT_DOWNLOAD = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'

function Test-NerdFontInstalled {
    $userFontsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $systemFontsKey = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($k in @($userFontsKey, $systemFontsKey)) {
        try {
            $vals = (Get-ItemProperty -Path $k -ErrorAction Stop).PSObject.Properties.Name
            if ($vals | Where-Object { $_ -match 'JetBrainsMono.*Nerd' }) { return $true }
        } catch {}
    }
    return $false
}

function Install-NerdFont {
    if (Test-NerdFontInstalled) {
        Write-Host '    JetBrainsMono Nerd Font already installed' -ForegroundColor DarkGray
        return
    }
    Write-Host '    installing JetBrainsMono Nerd Font (user scope, no admin, no winget)' -ForegroundColor DarkGray
    $zip = Join-Path $env:TEMP 'JetBrainsMono-NF.zip'
    $extract = Join-Path $env:TEMP 'JetBrainsMono-NF'
    Invoke-WebRequest -Uri $script:NERD_FONT_DOWNLOAD -OutFile $zip -UseBasicParsing
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $userFontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Test-Path $userFontsDir)) { New-Item -ItemType Directory -Path $userFontsDir -Force | Out-Null }
    $regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
    $copied = 0
    Get-ChildItem -Path $extract -Filter '*.ttf' -Recurse | ForEach-Object {
        $dest = Join-Path $userFontsDir $_.Name
        Copy-Item -Path $_.FullName -Destination $dest -Force
        $faceName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) + ' (TrueType)'
        Set-ItemProperty -Path $regKey -Name $faceName -Value $dest -Force
        $copied++
    }
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Write-Host "    installed $copied .ttf files under $userFontsDir" -ForegroundColor DarkGray
    if (-not (Test-NerdFontInstalled)) {
        throw "manual nerd font install completed but registry probe still fails -- inspect $userFontsDir and HKCU font key"
    }
}

$script:WT_PROFILE_NAME = 'Mandragora'
$script:START_MENU_LNK  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Mandragora.lnk"
$script:WT_FRAGMENT_OLD = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Mandragora\nixos.json"

function Get-TerminalSettingsPaths {
    $found = New-Object System.Collections.Generic.List[string]
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbcwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbcwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $found.Add($c) } }
    if ($found.Count -eq 0) {
        $pkgRoot = "$env:LOCALAPPDATA\Packages"
        if (Test-Path $pkgRoot) {
            Get-ChildItem -Path $pkgRoot -Directory -Filter '*WindowsTerminal*' -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Join-Path $_.FullName 'LocalState\settings.json'
                if (Test-Path $p) { $found.Add($p) }
            }
        }
    }
    if ($found.Count -eq 0) {
        Get-ChildItem -Path $env:LOCALAPPDATA -Recurse -Filter 'settings.json' -ErrorAction SilentlyContinue -Depth 5 |
            Where-Object { $_.FullName -match '(?i)WindowsTerminal' } |
            ForEach-Object { $found.Add($_.FullName) }
    }
    return $found
}

function Remove-StaleFragment {
    if (Test-Path $script:WT_FRAGMENT_OLD) {
        Remove-Item $script:WT_FRAGMENT_OLD -Force -ErrorAction SilentlyContinue
        $parent = Split-Path $script:WT_FRAGMENT_OLD -Parent
        if ((Test-Path $parent) -and -not (Get-ChildItem $parent)) {
            Remove-Item $parent -Force -ErrorAction SilentlyContinue
        }
        Write-Host '    removed stale fragment from earlier installer attempts' -ForegroundColor DarkGray
    }
}

function Find-WslNixosProfile {
    param($List)
    @($List | Where-Object {
        ($_.source -and ($_.source -match '(?i)wsl')) -and (
            ($_.name -and ($_.name -match '(?i)nixos')) -or
            ($_.commandline -and ($_.commandline -match '(?i)nixos'))
        )
    })
}

$script:MANDRAGORA_PROFILE_GUID = '{a7c6f4e2-1f4b-4b3e-9a5d-7c8e2d4f6b1a}'

function Get-MandragoraProfileObject {
    [PSCustomObject]@{
        guid              = $script:MANDRAGORA_PROFILE_GUID
        name              = $script:WT_PROFILE_NAME
        commandline       = 'wsl.exe -d NixOS'
        startingDirectory = '~'
        font              = [PSCustomObject]@{ face = $script:NERD_FONT_FACE }
        colorScheme       = 'Campbell'
        hidden            = $false
    }
}

function Test-TerminalFontConfigured {
    $paths = Get-TerminalSettingsPaths
    if (-not $paths) {
        return (Test-Path $script:WT_FRAGMENT_OLD)
    }
    foreach ($p in $paths) {
        try {
            $j = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { continue }
        if (-not $j.profiles) { return $false }
        $list = if ($j.profiles.list) { $j.profiles.list } else { $j.profiles }
        $mine = @($list | Where-Object { $_.guid -eq $script:MANDRAGORA_PROFILE_GUID })
        if (-not $mine) { return $false }
        foreach ($prof in $mine) {
            if (-not $prof.font -or $prof.font.face -ne $script:NERD_FONT_FACE) { return $false }
        }
    }
    return $true
}

function Write-MandragoraFragment {
    $dir = Split-Path $script:WT_FRAGMENT_OLD -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [PSCustomObject]@{
        '$schema' = 'https://aka.ms/terminal-profiles-schema-fragments'
        profiles  = @(Get-MandragoraProfileObject)
    }
    ($obj | ConvertTo-Json -Depth 32) | Set-Content -Path $script:WT_FRAGMENT_OLD -Encoding UTF8
    Write-Host "    wrote terminal fragment -> $($script:WT_FRAGMENT_OLD) (no settings.json found)" -ForegroundColor DarkGray
}

function Set-TerminalProfileFont {
    $paths = Get-TerminalSettingsPaths
    if (-not $paths) {
        Write-Host '    no Windows Terminal settings.json located; falling back to fragment' -ForegroundColor DarkYellow
        Write-MandragoraFragment
        return
    }
    Remove-StaleFragment
    foreach ($p in $paths) {
        try {
            $raw = Get-Content -Path $p -Raw -Encoding UTF8
            $j = $raw | ConvertFrom-Json
        } catch {
            Write-Host "    could not parse $p ; skipping" -ForegroundColor DarkYellow
            continue
        }
        if (-not $j.profiles) {
            $j | Add-Member -MemberType NoteProperty -Name profiles -Value ([PSCustomObject]@{ list = @() }) -Force
        }
        if (-not $j.profiles.list) {
            if ($j.profiles -is [array]) {
                $j.profiles = [PSCustomObject]@{ list = @($j.profiles) }
            } else {
                $j.profiles | Add-Member -MemberType NoteProperty -Name list -Value @() -Force
            }
        }
        $list = @($j.profiles.list)

        $profileDump = ($list | ForEach-Object {
            "        - name=$($_.name) source=$($_.source) commandline=$($_.commandline) guid=$($_.guid)"
        }) -join "`n"
        Write-Host "    enumerated profiles in $p :" -ForegroundColor DarkGray
        Write-Host $profileDump -ForegroundColor DarkGray

        $auto = Find-WslNixosProfile -List $list
        foreach ($prof in $auto) {
            if ($prof.guid -eq $script:MANDRAGORA_PROFILE_GUID) { continue }
            if ($prof.PSObject.Properties.Name -contains 'hidden') { $prof.hidden = $true }
            else { $prof | Add-Member -MemberType NoteProperty -Name hidden -Value $true -Force }
            Write-Host "    hid auto WSL profile name=$($prof.name) guid=$($prof.guid)" -ForegroundColor DarkGray
        }

        $existing = @($list | Where-Object { $_.guid -eq $script:MANDRAGORA_PROFILE_GUID })
        if ($existing) {
            foreach ($prof in $existing) {
                $prof.name = $script:WT_PROFILE_NAME
                $prof.commandline = 'wsl.exe -d NixOS'
                if (-not $prof.font) { $prof | Add-Member -MemberType NoteProperty -Name font -Value (New-Object PSObject) -Force }
                if ($prof.font.PSObject.Properties.Name -contains 'face') { $prof.font.face = $script:NERD_FONT_FACE }
                else { $prof.font | Add-Member -MemberType NoteProperty -Name face -Value $script:NERD_FONT_FACE -Force }
                if ($prof.PSObject.Properties.Name -contains 'hidden') { $prof.hidden = $false }
            }
            Write-Host "    updated existing Mandragora profile in $p" -ForegroundColor DarkGray
        } else {
            $newList = @($list) + (Get-MandragoraProfileObject)
            $j.profiles.list = $newList
            Write-Host "    added Mandragora profile (guid=$($script:MANDRAGORA_PROFILE_GUID)) to $p" -ForegroundColor DarkGray
        }

        $backup = "$p.mandragora-bak"
        if (-not (Test-Path $backup)) { Copy-Item $p $backup -Force }
        ($j | ConvertTo-Json -Depth 64) | Set-Content -Path $p -Encoding UTF8
    }
}

function Get-NixosIconPath {
    $dir = "$env:LOCALAPPDATA\Mandragora"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $ico = Join-Path $dir 'nixos.ico'
    if (-not (Test-Path $ico)) {
        try {
            Invoke-WebRequest -Uri 'https://nixos.org/favicon.ico' -OutFile $ico -UseBasicParsing -ErrorAction Stop
            Write-Host "    downloaded NixOS icon -> $ico" -ForegroundColor DarkGray
        } catch {
            Write-Host "    failed to download nixos.org/favicon.ico ($($_.Exception.Message)); using shell default icon" -ForegroundColor DarkYellow
            return $null
        }
    }
    return $ico
}

function Install-StartMenuShortcut {
    $parent = Split-Path $script:START_MENU_LNK -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue)
    if ($wt) {
        $targetPath = $wt.Source
        $args = "-p `"$($script:MANDRAGORA_PROFILE_GUID)`""
    } else {
        $targetPath = "$env:SYSTEMROOT\System32\wsl.exe"
        $args = '-d NixOS'
    }
    $ico = Get-NixosIconPath
    $iconLocation = if ($ico) { "$ico,0" } else { "$targetPath,0" }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($script:START_MENU_LNK)
    $lnk.TargetPath = $targetPath
    $lnk.Arguments = $args
    $lnk.WorkingDirectory = $env:USERPROFILE
    $lnk.IconLocation = $iconLocation
    $lnk.Description = 'Mandragora (NixOS-WSL)'
    $lnk.Save()
    Write-Host "    wrote Start Menu shortcut -> $($script:START_MENU_LNK)" -ForegroundColor DarkGray
    Write-Host "    target: $targetPath $args" -ForegroundColor DarkGray
    Write-Host "    icon  : $iconLocation" -ForegroundColor DarkGray
    Write-Host '    type "mandragora" in Start to launch (may take 30s to index)' -ForegroundColor DarkGray
}

function Test-StartMenuShortcut {
    if (-not (Test-Path $script:START_MENU_LNK)) { return $false }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($script:START_MENU_LNK)
        return ($lnk.IconLocation -match 'nixos\.ico')
    } catch { return $false }
}
$IS_ADMIN = Test-Admin

$STATE_DIR = "$env:LOCALAPPDATA\Mandragora"
$STATE_KEY = 'HKCU:\SOFTWARE\Mandragora'
$DESKTOP = [Environment]::GetFolderPath('Desktop')
$LOG_DIR = Join-Path $DESKTOP 'mandragora-logs'
$LOG  = Join-Path $LOG_DIR 'install.log'
$env:MANDRAGORA_LOG_DIR = $LOG_DIR
if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
if (-not (Test-Path $LOG_DIR))   { New-Item -ItemType Directory -Path $LOG_DIR   -Force | Out-Null }
if (-not (Test-Path $STATE_KEY)) { New-Item -Path $STATE_KEY -Force | Out-Null }
Start-Transcript -Path $LOG -Append -ErrorAction SilentlyContinue | Out-Null

$script:ReplaceAll = $false
$script:ReplaceNone = $false
$replaceEnv = if ($env:MANDRAGORA_REPLACE) { $env:MANDRAGORA_REPLACE.ToLower() } else { '' }
switch ($replaceEnv) {
    'all'  { $script:ReplaceAll  = $true }
    'yes'  { $script:ReplaceAll  = $true }
    'none' { $script:ReplaceNone = $true }
    'no'   { $script:ReplaceNone = $true }
}

function Confirm-Replace {
    param([Parameter(Mandatory)] [string] $What)
    if ($script:ReplaceAll)  { Write-Host "    '$What' exists -- replacing (MANDRAGORA_REPLACE=all)" -ForegroundColor DarkGray; return $true }
    if ($script:ReplaceNone) { Write-Host "    '$What' exists -- keeping  (MANDRAGORA_REPLACE=none)" -ForegroundColor DarkGray; return $false }
    while ($true) {
        $r = Read-Host "    '$What' already exists. Replace? [Y]es / [N]o / [A]ll / N[o]ne"
        switch -Regex ($r.Trim().ToLower()) {
            '^(y|yes)$'     { return $true }
            '^(n|no)$'      { return $false }
            '^(a|all)$'     { $script:ReplaceAll  = $true; return $true }
            '^(o|none)$'    { $script:ReplaceNone = $true; return $false }
            default         { Write-Host '    please answer Y / N / A / O' -ForegroundColor Yellow }
        }
    }
}

function Invoke-Elevated {
    param(
        [Parameter(Mandatory)] [string] $What,
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $ArgumentList = @()
    )
    Write-Host "    UAC prompt incoming for: $What" -ForegroundColor Yellow
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Verb RunAs -Wait -PassThru -ErrorAction Stop
    if ($proc.ExitCode -ne 0) { throw "$What failed in elevated child (exit $($proc.ExitCode))" }
}

function Assert-WslReady {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $ok = $false
    try {
        & wsl --version 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
    } catch {} finally { $ErrorActionPreference = $prevEAP }
    if ($ok) { return }

    Write-Host ''
    Write-Host '====================================================' -ForegroundColor Red
    Write-Host '  WSL2 is not installed on this host.'                -ForegroundColor Red
    Write-Host '====================================================' -ForegroundColor Red
    Write-Host '  This installer assumes WSL2 is already present so it'
    Write-Host '  can run end-to-end without admin / UAC prompts.'
    Write-Host ''
    Write-Host '  To install WSL2 itself (one-time, requires admin):'  -ForegroundColor Yellow
    Write-Host '    1. open an ADMIN PowerShell on this machine'
    Write-Host '    2. run:  wsl --install --no-distribution'
    Write-Host '    3. reboot'
    Write-Host '    4. re-run this installer as a regular user'
    Write-Host ''
    Write-Host '  Or ask your administrator to enable WSL2. Once' -ForegroundColor Yellow
    Write-Host '  `wsl --version` succeeds, this installer needs no admin.'
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 3
}

function Show-Preflight {
    $cs       = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os       = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $domain   = if ($cs) { $cs.PartOfDomain } else { $false }
    $azureAD  = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Enrollments') -and `
                ((Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
                  Where-Object { $_.PSChildName -match '^[0-9A-F-]{36}$' }).Count -gt 0)
    $bitlocker = $false
    try { $bitlocker = ((Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop).ProtectionStatus -eq 'On') } catch {}
    $existing = @()
    try {
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $raw = & wsl.exe --list --quiet 2>$null
        if ($raw) {
            $clean = (($raw | Out-String) -replace "`0",'')
            $existing = $clean -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'NixOS' }
        }
        $ErrorActionPreference = $prevEAP
    } catch { $ErrorActionPreference = $prevEAP }

    Write-Host ''
    Write-Host '====================================================' -ForegroundColor Yellow
    Write-Host '  MANDRAGORA-WSL INSTALL -- preflight'                 -ForegroundColor Yellow
    Write-Host '====================================================' -ForegroundColor Yellow
    $csName  = if ($cs) { $cs.Name }     else { $env:COMPUTERNAME }
    $osCap   = if ($os) { $os.Caption }  else { 'Windows' }
    Write-Host ('  computer       : {0} ({1})' -f $csName, $osCap)
    Write-Host ('  admin powershell: {0}' -f $IS_ADMIN)
    Write-Host ('  WSL2 already up: True (verified)')
    Write-Host ('  domain joined  : {0}' -f $domain)
    Write-Host ('  AAD enrolled   : {0}' -f $azureAD)
    Write-Host ('  BitLocker C:   : {0}' -f $bitlocker)
    Write-Host ('  existing WSL   : {0}' -f ($(if ($existing) { $existing -join ', ' } else { '(none)' })))
    Write-Host ('  rice mode      : {0}' -f ($(if ($RICE) { 'ON (will edit registry -- UAC)' } else { 'OFF (use MANDRAGORA_RICE=1 to enable)' })))
    Write-Host ('  personal cfg   : {0}' -f ($(if ($PERSONAL) { 'ON (mvrozanti git/email + aerc/khal dotfiles)' } else { 'OFF (use MANDRAGORA_PERSONAL=1 to enable)' })))
    Write-Host ('  replace policy : {0}' -f ($(if ($script:ReplaceAll) { 'all (auto-Yes)' } elseif ($script:ReplaceNone) { 'none (auto-No)' } else { 'prompt (Y/N/A/O)' })))
    Write-Host ('  log file       : {0}' -f $LOG)
    Write-Host '----------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  what will happen:' -ForegroundColor Yellow
    if ($RICE) {
        Write-Host '    - apply Windows cosmetic + privacy registry tweaks (UAC prompt)'
    }
    Write-Host   '    - import latest NixOS-WSL as a NEW sibling distro called "NixOS" (per-user, no admin)'
    Write-Host   '    - inside NixOS: clone mandragora repo + nixos-rebuild switch (per-user, no admin)'
    Write-Host   '    - prompt on every pre-existing artefact (distro / tarball / repo dir)'
    Write-Host '  will NOT touch:' -ForegroundColor Yellow
    Write-Host   '    - any existing WSL distros (Ubuntu/Debian/etc remain untouched)'
    Write-Host   '    - BitLocker, full-disk encryption, secure boot'
    Write-Host   '    - corporate VPN, AV, MDM agent, group policies'
    Write-Host   '    - Windows user accounts, domain bindings, network settings'
    Write-Host '====================================================' -ForegroundColor Yellow

    if (($domain -or $azureAD) -and -not $FORCE) {
        Write-Host ''
        Write-Host 'this looks like a managed device (domain-joined or AAD-enrolled).' -ForegroundColor Red
        Write-Host 'aborting. set MANDRAGORA_FORCE=1 in the env to override.' -ForegroundColor Red
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 2
    }

    Write-Host ''
    Write-Host 'starting in 15s -- Ctrl-C to abort.' -ForegroundColor Cyan
    for ($i = 15; $i -gt 0; $i--) { Write-Host -NoNewline ("`r  {0,3}s..." -f $i); Start-Sleep 1 }
    Write-Host ''
}

function Get-State {
    $v = (Get-ItemProperty -Path $STATE_KEY -Name InstallStage -ErrorAction SilentlyContinue).InstallStage
    if (Test-WslDistroExists -Name 'NixOS') {
        $h = Get-WslGuestHostname -Name 'NixOS'
        if ($h -eq 'mandragora-wsl') {
            if (-not (Test-NerdFontInstalled)) { return 'bootstrap-done' }
            if (-not (Test-TerminalFontConfigured) -or -not (Test-StartMenuShortcut)) { return 'fonts-done' }
            return 'done'
        }
        return 'nixos-imported'
    }
    if ($v) { return $v }
    return 'init'
}
function Set-State($s) {
    Set-ItemProperty -Path $STATE_KEY -Name InstallStage -Value $s -Force
    $check = (Get-ItemProperty -Path $STATE_KEY -Name InstallStage).InstallStage
    if ($check -ne $s) { throw "state write verify failed: wanted '$s' got '$check'" }
    Write-Host "    state -> $s" -ForegroundColor DarkGray
}

function Invoke-Phase {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [switch] $RequiresAdmin,
        [hashtable] $EnvVars = @{}
    )
    Write-Host ">>> phase: $Name" -ForegroundColor Cyan
    $script = "$env:TEMP\mandragora-$Name.ps1"
    Invoke-WebRequest -Uri "$BASE/$Name.ps1" -OutFile $script -UseBasicParsing
    foreach ($k in $EnvVars.Keys) { Set-Item -Path "env:$k" -Value $EnvVars[$k] }
    try {
        if ($RequiresAdmin -and -not $IS_ADMIN) {
            Invoke-Elevated -What "phase $Name" -FilePath powershell `
                -ArgumentList @('-ExecutionPolicy','Bypass','-NoProfile','-File',$script)
        } else {
            & powershell -ExecutionPolicy Bypass -NoProfile -File $script
            if ($LASTEXITCODE -ne 0) { throw "phase $Name failed (exit $LASTEXITCODE)" }
        }
    } finally {
        foreach ($k in $EnvVars.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

trap {
    Write-Host ''
    Write-Host ('==> install failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('    logs on Desktop: ' + $LOG_DIR)             -ForegroundColor Red
    Write-Host ('    re-run the same one-liner to resume from last state') -ForegroundColor Red
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

Assert-WslReady

if ((Get-State) -eq 'init') { Show-Preflight }

while ($true) {
    $state = Get-State
    Write-Host "==> stage: $state" -ForegroundColor Yellow
    switch ($state) {
        'init' {
            if ($RICE) {
                Invoke-Phase -Name '01-rice' -RequiresAdmin
            } else {
                Write-Host '>>> phase: 01-rice -- SKIPPED (set MANDRAGORA_RICE=1 to enable)' -ForegroundColor DarkYellow
            }
            Set-State 'rice-done'
        }
        'rice-done' {
            $tarball = "$env:USERPROFILE\Downloads\nixos-wsl.tar.gz"
            $replaceDistro  = $false
            $replaceTarball = $false

            $distroExists = Test-WslDistroExists -Name 'NixOS'
            if ($distroExists) {
                $replaceDistro = Confirm-Replace -What 'WSL distro "NixOS"'
            }
            if (Test-Path $tarball) {
                $replaceTarball = Confirm-Replace -What "tarball $tarball"
            }

            Invoke-Phase -Name '03-import-nixos-wsl' -EnvVars @{
                MANDRAGORA_REPLACE_DISTRO  = $(if ($replaceDistro)  { '1' } else { '0' })
                MANDRAGORA_REPLACE_TARBALL = $(if ($replaceTarball) { '1' } else { '0' })
            }
            Set-State 'nixos-imported'
        }
        'nixos-imported' {
            Write-Host '>>> phase: 04-bootstrap (inside NixOS-WSL)' -ForegroundColor Cyan
            $boot = "$env:TEMP\04-bootstrap.sh"
            Invoke-WebRequest -Uri "$BASE/04-bootstrap.sh" -OutFile $boot -UseBasicParsing
            $drive = $boot.Substring(0,1).ToLower()
            $rest  = $boot.Substring(2) -replace '\\','/'
            $wslPath = "/mnt/$drive$rest"
            $personal = if ($env:MANDRAGORA_PERSONAL -eq '1') { '1' } else { '0' }
            $replacePolicy = if ($script:ReplaceAll) { 'all' } elseif ($script:ReplaceNone) { 'none' } else { 'prompt' }
            $bootLog = Join-Path $LOG_DIR 'bootstrap.log'
            $logDrive = $LOG_DIR.Substring(0,1).ToLower()
            $logRest  = $LOG_DIR.Substring(2) -replace '\\','/'
            $wslLogDir = "/mnt/$logDrive$logRest"
            Write-Host "    bootstrap log -> $bootLog" -ForegroundColor DarkGray
            & wsl -d NixOS -e env `
                MANDRAGORA_REPO=$REPO `
                MANDRAGORA_PERSONAL=$personal `
                MANDRAGORA_REPLACE=$replacePolicy `
                MANDRAGORA_LOG_DIR=$wslLogDir `
                bash $wslPath 2>&1 | Tee-Object -FilePath $bootLog -Append
            if ($LASTEXITCODE -ne 0) { throw "bootstrap failed (exit $LASTEXITCODE) -- see $bootLog" }
            Set-State 'bootstrap-done'
        }
        'bootstrap-done' {
            Write-Host '>>> phase: nerd-font install' -ForegroundColor Cyan
            Install-NerdFont
            Set-State 'fonts-done'
        }
        'fonts-done' {
            Write-Host '>>> phase: windows-terminal profile rename + font' -ForegroundColor Cyan
            Set-TerminalProfileFont
            Write-Host '>>> phase: start menu shortcut' -ForegroundColor Cyan
            Install-StartMenuShortcut
            Set-State 'done'
        }
        'done' {
            Write-Host '==> mandragora-wsl install complete.' -ForegroundColor Green
            Write-Host '==> run: wsl -d NixOS' -ForegroundColor Green
            Write-Host ('==> logs retained on Desktop: ' + $LOG_DIR) -ForegroundColor Green
            Remove-Item $STATE_KEY -Recurse -Force -ErrorAction SilentlyContinue
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            Remove-Item $STATE_DIR -Recurse -Force -ErrorAction SilentlyContinue
            exit 0
        }
        default { throw "unknown state: $state" }
    }
}
