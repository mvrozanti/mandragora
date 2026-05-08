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
$STATE = 'C:\mandragora-install-state.txt'
$SELF  = 'C:\mandragora-install.ps1'

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { Write-Error 'must run as administrator'; exit 1 }

function Get-State { if (Test-Path $STATE) { Get-Content $STATE -Raw } else { 'init' } }
function Set-State($s) { $s | Set-Content -Path $STATE -NoNewline }

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
            Write-Host '==> rebooting in 10s; will auto-resume after login' -ForegroundColor Green
            Start-Sleep 10
            Restart-Computer -Force
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
            Remove-Item $STATE -Force -ErrorAction SilentlyContinue
            Remove-Item $SELF  -Force -ErrorAction SilentlyContinue
            exit 0
        }
        default { throw "unknown state: $state" }
    }
}
