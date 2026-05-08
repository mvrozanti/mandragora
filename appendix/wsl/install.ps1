# Mandragora WSL install — single-file orchestrator.
#
# Usage on a fresh Win 11 (admin PowerShell):
#   iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl/install.ps1)
#
# Tunables (set before running):
#   $env:MANDRAGORA_RICE  = '1'   # opt in to Windows cosmetic / privacy registry tweaks (default OFF)
#   $env:MANDRAGORA_FORCE = '1'   # bypass the managed-device safety prompt
#   $env:MANDRAGORA_REPO  = 'https://github.com/<fork>/mandragora.git'
#
# Default behaviour: enables WSL2 features + MSI, imports NixOS-WSL as a
# sibling distro (does NOT touch any existing Ubuntu/Debian distro), runs
# the mandragora-wsl bootstrap inside it. Does NOT modify Windows
# registry/desktop unless you set MANDRAGORA_RICE=1.

$ErrorActionPreference = 'Stop'
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl'
$REPO = $env:MANDRAGORA_REPO; if (-not $REPO) { $REPO = 'https://github.com/mvrozanti/mandragora.git' }
$RICE = ($env:MANDRAGORA_RICE -eq '1')
$FORCE = ($env:MANDRAGORA_FORCE -eq '1')
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
$IS_ADMIN = Test-Admin

if ($IS_ADMIN) {
    $STATE_DIR = "$env:ProgramData\Mandragora"
    $STATE_KEY = 'HKLM:\SOFTWARE\Mandragora'
    $RUN_KEY   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
} else {
    $STATE_DIR = "$env:LOCALAPPDATA\Mandragora"
    $STATE_KEY = 'HKCU:\SOFTWARE\Mandragora'
    $RUN_KEY   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
}
$SELF = "$STATE_DIR\install.ps1"
$LOG  = "$STATE_DIR\install.log"
if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
if (-not (Test-Path $STATE_KEY)) { New-Item -Path $STATE_KEY -Force | Out-Null }
Start-Transcript -Path $LOG -Append -ErrorAction SilentlyContinue | Out-Null

function Need-Admin($what) {
    if (-not $IS_ADMIN) {
        throw "this step needs admin: $what`nrelaunch PowerShell as Administrator and re-run the same one-liner."
    }
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
    $hyperv   = $false
    if ($IS_ADMIN) { $hyperv = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue).State -eq 'Enabled' }
    $wslReady = $false
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & wsl --version 2>$null | Out-Null
        $wslReady = ($LASTEXITCODE -eq 0)
    } catch {} finally { $ErrorActionPreference = $prevEAP }
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
    Write-Host ('  WSL2 already up: {0}' -f $wslReady)
    Write-Host ('  domain joined  : {0}' -f $domain)
    Write-Host ('  AAD enrolled   : {0}' -f $azureAD)
    Write-Host ('  BitLocker C:   : {0}' -f $bitlocker)
    Write-Host ('  Hyper-V        : {0}' -f ($(if ($IS_ADMIN) { $hyperv } else { '(unknown — needs admin to probe)' })))
    Write-Host ('  existing WSL   : {0}' -f ($(if ($existing) { $existing -join ', ' } else { '(none)' })))
    Write-Host ('  rice mode      : {0}' -f ($(if ($RICE) { 'ON (will edit registry)' } else { 'OFF (use MANDRAGORA_RICE=1 to enable)' })))
    Write-Host ('  log file       : {0}' -f $LOG)
    Write-Host '----------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  what will happen:' -ForegroundColor Yellow
    if ($RICE) { Write-Host '    - apply Windows cosmetic + privacy registry tweaks (admin)' }
    if (-not $wslReady) {
        Write-Host '    - enable Microsoft-Windows-Subsystem-Linux + VirtualMachinePlatform features (admin)'
        Write-Host '    - REBOOT (auto-resumes after login via RunOnce)'
        Write-Host '    - install WSL2 MSI from microsoft/WSL releases (admin)'
    } else {
        Write-Host '    - WSL2 is already installed; skipping feature/MSI/reboot phases'
    }
    Write-Host   '    - import latest NixOS-WSL as a NEW sibling distro called "NixOS" (per-user, no admin)'
    Write-Host   '    - inside NixOS: clone mandragora repo + nixos-rebuild switch (per-user, no admin)'
    Write-Host '  will NOT touch:' -ForegroundColor Yellow
    Write-Host   '    - any existing WSL distros (Ubuntu/Debian/etc remain untouched)'
    Write-Host   '    - BitLocker, full-disk encryption, secure boot'
    Write-Host   '    - corporate VPN, AV, MDM agent, group policies'
    Write-Host   '    - Windows user accounts, domain bindings, network settings'
    Write-Host '====================================================' -ForegroundColor Yellow

    if (-not $wslReady -and -not $IS_ADMIN) {
        Write-Host ''
        Write-Host 'WSL2 is not installed yet AND this PowerShell is not elevated.' -ForegroundColor Red
        Write-Host 'either:' -ForegroundColor Red
        Write-Host '  1. ask IT to install WSL2, then re-run this in a normal PowerShell, or' -ForegroundColor Red
        Write-Host '  2. relaunch PowerShell as Administrator and re-run.' -ForegroundColor Red
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 3
    }

    if ($RICE -and -not $IS_ADMIN) {
        Write-Host 'rice phase needs admin; either drop MANDRAGORA_RICE or relaunch elevated.' -ForegroundColor Red
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 3
    }

    if (($domain -or $azureAD) -and -not $FORCE) {
        Write-Host ''
        Write-Host 'this looks like a managed device (domain-joined or AAD-enrolled).' -ForegroundColor Red
        Write-Host 'enabling Windows features may conflict with corporate group policy.' -ForegroundColor Red
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
        try {
            $wslVer = & wsl --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $wslVer -match 'WSL') { return 'wsl-installed' }
        } catch {}
        $f = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq 'Enabled') { return 'features-enabled' }
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

function Invoke-Phase($name) {
    Write-Host ">>> phase: $name" -ForegroundColor Cyan
    $script = "$env:TEMP\mandragora-$name.ps1"
    Invoke-WebRequest -Uri "$BASE/$name.ps1" -OutFile $script -UseBasicParsing
    & powershell -ExecutionPolicy Bypass -NoProfile -File $script
    if ($LASTEXITCODE -ne 0) { throw "phase $name failed (exit $LASTEXITCODE)" }
}

function Set-RunOnce {
    Invoke-WebRequest -Uri "$BASE/install.ps1" -OutFile $SELF -UseBasicParsing
    Set-ItemProperty `
        -Path $RUN_KEY `
        -Name 'MandragoraInstall' `
        -Value "powershell -ExecutionPolicy Bypass -NoProfile -File `"$SELF`""
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

if ((Get-State) -eq 'init') { Show-Preflight }

while ($true) {
    $state = Get-State
    Write-Host "==> stage: $state" -ForegroundColor Yellow
    switch ($state) {
        'init' {
            if ($RICE) {
                Need-Admin 'phase 01-rice writes HKLM telemetry policy keys'
                Invoke-Phase '01-rice'
            } else {
                Write-Host '>>> phase: 01-rice — SKIPPED (set MANDRAGORA_RICE=1 to enable)' -ForegroundColor DarkYellow
            }
            Set-State 'rice-done'
        }
        'rice-done' {
            Need-Admin 'enabling Microsoft-Windows-Subsystem-Linux + VirtualMachinePlatform features'
            Invoke-Phase '02-install-wsl'
            Set-State 'features-enabled'
            Set-RunOnce
            Write-Host '==> rebooting in 30s; will auto-resume after login' -ForegroundColor Green
            & shutdown.exe /r /t 30 /c 'Mandragora install: rebooting to finish WSL setup'
            exit 0
        }
        'features-enabled' {
            Need-Admin 'installing the WSL2 MSI system-wide'
            Invoke-Phase '02b-install-wsl-msi'
            Set-State 'wsl-installed'
        }
        'wsl-installed' {
            Invoke-Phase '03-import-nixos-wsl'
            Set-State 'nixos-imported'
        }
        'nixos-imported' {
            Write-Host '>>> phase: 04-bootstrap (inside NixOS-WSL)' -ForegroundColor Cyan
            $boot = "$env:TEMP\04-bootstrap.sh"
            Invoke-WebRequest -Uri "$BASE/04-bootstrap.sh" -OutFile $boot -UseBasicParsing
            $drive = $boot.Substring(0,1).ToLower()
            $rest  = $boot.Substring(2) -replace '\\','/'
            $wslPath = "/mnt/$drive$rest"
            & wsl -d NixOS -e env MANDRAGORA_REPO=$REPO bash $wslPath
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
