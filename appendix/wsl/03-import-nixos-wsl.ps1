# Import NixOS-WSL tarball as a WSL distro named 'NixOS'.
# Run after rebooting from 02-install-wsl.ps1.

$ErrorActionPreference = 'Stop'

$wslRoot = 'C:\WSL\NixOS'
$tarball = "$env:USERPROFILE\Downloads\nixos-wsl.tar.gz"
$url     = 'https://github.com/nix-community/NixOS-WSL/releases/latest/download/nixos.wsl'

Write-Host '[1/4] checking WSL is ready'
wsl --status | Out-String | Write-Host
wsl --update --web-download | Out-Null

Write-Host '[2/4] downloading NixOS-WSL tarball'
if (-not (Test-Path $tarball)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
}

Write-Host '[3/4] importing as distro NixOS'
if ((wsl --list --quiet) -match '^NixOS$') {
    Write-Host 'NixOS distro already imported, skipping'
} else {
    New-Item -ItemType Directory -Path $wslRoot -Force | Out-Null
    wsl --import NixOS $wslRoot $tarball --version 2
}

Write-Host '[4/4] smoke test'
wsl -d NixOS -- /run/current-system/sw/bin/uname -a

Write-Host 'NixOS-WSL imported. Default user is `nixos` until mandragora bootstrap runs.'
