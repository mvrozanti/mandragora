# Install WSL2 kernel + features. Reboot is required afterwards.
# Skips the bundled Ubuntu install (we want NixOS-WSL).

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'must run as administrator'
    exit 1
}

Write-Host '[1/3] enabling Microsoft-Windows-Subsystem-Linux'
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null

Write-Host '[2/3] enabling VirtualMachinePlatform'
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart | Out-Null

Write-Host '[3/3] installing WSL2 kernel + setting default version'
wsl --install --no-distribution --web-download
wsl --set-default-version 2

Write-Host 'WSL installed. Reboot required before next step.'
