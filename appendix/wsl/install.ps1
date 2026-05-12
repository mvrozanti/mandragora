# Mandragora WSL install — single-file orchestrator.
#
# Usage on a Win 11 host with WSL2 already installed (regular PowerShell):
#   iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl/install.ps1)
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
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl'
$REPO = $env:MANDRAGORA_REPO; if (-not $REPO) { $REPO = 'https://github.com/mvrozanti/mandragora.git' }
$RICE     = ($env:MANDRAGORA_RICE -eq '1')
$PERSONAL = ($env:MANDRAGORA_PERSONAL -eq '1')
$FORCE    = ($env:MANDRAGORA_FORCE -eq '1')

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
$IS_ADMIN = Test-Admin

$STATE_DIR = "$env:LOCALAPPDATA\Mandragora"
$STATE_KEY = 'HKCU:\SOFTWARE\Mandragora'
$LOG  = "$STATE_DIR\install.log"
if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
if (-not (Test-Path $STATE_KEY)) { New-Item -Path $STATE_KEY -Force | Out-Null }
Start-Transcript -Path $LOG -Append -ErrorAction SilentlyContinue | Out-Null

$script:ReplaceAll = $false
$script:ReplaceNone = $false
switch (($env:MANDRAGORA_REPLACE | ForEach-Object { $_.ToLower() })) {
    'all'  { $script:ReplaceAll  = $true }
    'yes'  { $script:ReplaceAll  = $true }
    'none' { $script:ReplaceNone = $true }
    'no'   { $script:ReplaceNone = $true }
}

function Confirm-Replace {
    param([Parameter(Mandatory)] [string] $What)
    if ($script:ReplaceAll)  { Write-Host "    '$What' exists — replacing (MANDRAGORA_REPLACE=all)" -ForegroundColor DarkGray; return $true }
    if ($script:ReplaceNone) { Write-Host "    '$What' exists — keeping  (MANDRAGORA_REPLACE=none)" -ForegroundColor DarkGray; return $false }
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
        $existing = (& wsl --list --quiet 2>$null) -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
        $existing = $existing | Where-Object { $_ -ne 'NixOS' }
        $ErrorActionPreference = $prevEAP
    } catch { $ErrorActionPreference = $prevEAP }

    Write-Host ''
    Write-Host '====================================================' -ForegroundColor Yellow
    Write-Host '  MANDRAGORA-WSL INSTALL — preflight'                 -ForegroundColor Yellow
    Write-Host '====================================================' -ForegroundColor Yellow
    Write-Host ('  computer       : {0} ({1})' -f $cs.Name, $os.Caption)
    Write-Host ('  admin powershell: {0}' -f $IS_ADMIN)
    Write-Host ('  WSL2 already up: True (verified)')
    Write-Host ('  domain joined  : {0}' -f $domain)
    Write-Host ('  AAD enrolled   : {0}' -f $azureAD)
    Write-Host ('  BitLocker C:   : {0}' -f $bitlocker)
    Write-Host ('  existing WSL   : {0}' -f ($(if ($existing) { $existing -join ', ' } else { '(none)' })))
    Write-Host ('  rice mode      : {0}' -f ($(if ($RICE) { 'ON (will edit registry — UAC)' } else { 'OFF (use MANDRAGORA_RICE=1 to enable)' })))
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
    Write-Host 'starting in 15s — Ctrl-C to abort.' -ForegroundColor Cyan
    for ($i = 15; $i -gt 0; $i--) { Write-Host -NoNewline ("`r  {0,3}s..." -f $i); Start-Sleep 1 }
    Write-Host ''
}

function Get-State {
    $v = (Get-ItemProperty -Path $STATE_KEY -Name InstallStage -ErrorAction SilentlyContinue).InstallStage
    if ($v) { return $v }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        try {
            $list = & wsl --list --quiet 2>$null
            if ($LASTEXITCODE -eq 0 -and ($list -match '^NixOS$')) { return 'nixos-imported' }
        } catch {}
        return 'init'
    } finally {
        $ErrorActionPreference = $prevEAP
    }
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
    Write-Host ('    full transcript at: ' + $LOG)              -ForegroundColor Red
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
                Write-Host '>>> phase: 01-rice — SKIPPED (set MANDRAGORA_RICE=1 to enable)' -ForegroundColor DarkYellow
            }
            Set-State 'rice-done'
        }
        'rice-done' {
            $tarball = "$env:USERPROFILE\Downloads\nixos-wsl.tar.gz"
            $replaceDistro  = $false
            $replaceTarball = $false

            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $distroExists = ((& wsl --list --quiet 2>$null) -match '^NixOS$')
            $ErrorActionPreference = $prevEAP
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
            & wsl -d NixOS -e env `
                MANDRAGORA_REPO=$REPO `
                MANDRAGORA_PERSONAL=$personal `
                MANDRAGORA_REPLACE=$replacePolicy `
                bash $wslPath
            if ($LASTEXITCODE -ne 0) { throw "bootstrap failed (exit $LASTEXITCODE)" }
            Set-State 'done'
        }
        'done' {
            Write-Host '==> mandragora-wsl install complete.' -ForegroundColor Green
            Write-Host '==> run: wsl -d NixOS' -ForegroundColor Green
            Remove-Item $STATE_KEY -Recurse -Force -ErrorAction SilentlyContinue
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            Remove-Item $STATE_DIR -Recurse -Force -ErrorAction SilentlyContinue
            exit 0
        }
        default { throw "unknown state: $state" }
    }
}
