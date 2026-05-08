# Mandragora WSL install — single-file orchestrator.
#
# Usage on a fresh Win 11 (admin PowerShell):
#   iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl/install.ps1)
#
# Idempotent. Reboots once between WSL feature enablement and MSI install,
# auto-resumes via RunOnce. Run it once, log back in after reboot, done.

$ErrorActionPreference = 'Stop'
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/appendix/wsl'
$REPO = $env:MANDRAGORA_REPO; if (-not $REPO) { $REPO = 'https://github.com/mvrozanti/mandragora.git' }
$STATE_DIR = "$env:ProgramData\Mandragora"
$STATE_KEY = 'HKLM:\SOFTWARE\Mandragora'
$SELF      = "$STATE_DIR\install.ps1"
if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
if (-not (Test-Path $STATE_KEY)) { New-Item -Path $STATE_KEY -Force | Out-Null }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { Write-Error 'must run as administrator'; exit 1 }

function Get-State {
    $v = (Get-ItemProperty -Path $STATE_KEY -Name InstallStage -ErrorAction SilentlyContinue).InstallStage
    if ($v) { return $v }
    if ((& wsl --list --quiet 2>$null) -match '^NixOS$') { return 'nixos-imported' }
    $wslVer = & wsl --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $wslVer -match 'WSL') { return 'wsl-installed' }
    $f = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    if ($f -and $f.State -eq 'Enabled') { return 'features-enabled' }
    return 'init'
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
        -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' `
        -Name 'MandragoraInstall' `
        -Value "powershell -ExecutionPolicy Bypass -NoProfile -File `"$SELF`""
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

while ($true) {
    $state = Get-State
    Write-Host "==> stage: $state" -ForegroundColor Yellow
    switch ($state) {
        'init' {
            Invoke-Phase '01-rice'
            Set-State 'rice-done'
        }
        'rice-done' {
            Invoke-Phase '02-install-wsl'
            Set-State 'features-enabled'
            Set-RunOnce
            Write-Host '==> rebooting in 30s; will auto-resume after login' -ForegroundColor Green
            & shutdown.exe /r /t 30 /c 'Mandragora install: rebooting to finish WSL setup'
            exit 0
        }
        'features-enabled' {
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
            $wslPath = (& wsl -d NixOS wslpath ($boot -replace '\\','/' -replace '^([A-Z]):','/mnt/$1' )).Trim().ToLower()
            if (-not $wslPath) { $wslPath = "/mnt/$($boot.Substring(0,1).ToLower())/$($boot.Substring(3) -replace '\\','/')" }
            & wsl -d NixOS -e env MANDRAGORA_REPO=$REPO bash $wslPath
            if ($LASTEXITCODE -ne 0) { throw "bootstrap failed (exit $LASTEXITCODE)" }
            Set-State 'done'
        }
        'done' {
            Write-Host '==> mandragora-wsl install complete.' -ForegroundColor Green
            Write-Host '==> run: wsl -d NixOS' -ForegroundColor Green
            Remove-Item $STATE_DIR -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $STATE_KEY -Recurse -Force -ErrorAction SilentlyContinue
            exit 0
        }
        default { throw "unknown state: $state" }
    }
}
