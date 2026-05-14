# Import NixOS-WSL tarball as a WSL distro named 'NixOS'.
# Conflict policy decided by parent install.ps1 and passed as env:
#   MANDRAGORA_REPLACE_DISTRO  = '1' | '0'
#   MANDRAGORA_REPLACE_TARBALL = '1' | '0'

$ErrorActionPreference = 'Stop'

$wslRoot = 'C:\WSL\NixOS'
$tarball = "$env:USERPROFILE\Downloads\nixos-wsl.tar.gz"
$url     = 'https://github.com/nix-community/NixOS-WSL/releases/latest/download/nixos.wsl'
$replaceDistro  = ($env:MANDRAGORA_REPLACE_DISTRO  -eq '1')
$replaceTarball = ($env:MANDRAGORA_REPLACE_TARBALL -eq '1')

Write-Host '[1/3] tarball'
if ((Test-Path $tarball) -and -not $replaceTarball) {
    Write-Host "    reusing existing $tarball"
} else {
    if (Test-Path $tarball) { Remove-Item $tarball -Force }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
}

Write-Host '[2/3] import distro NixOS'
$exists = ((wsl --list --quiet) -match '^NixOS$')
if ($exists -and -not $replaceDistro) {
    Write-Host '    NixOS distro already present, keeping as-is'
} else {
    if ($exists) {
        Write-Host '    unregistering existing NixOS distro'
        wsl --unregister NixOS
        if ($LASTEXITCODE -ne 0) { throw "wsl --unregister NixOS failed (exit $LASTEXITCODE)" }
    }
    New-Item -ItemType Directory -Path $wslRoot -Force | Out-Null
    wsl --import NixOS $wslRoot $tarball --version 2
    if ($LASTEXITCODE -ne 0) { throw "wsl --import NixOS failed (exit $LASTEXITCODE)" }
}

Write-Host '[3/3] smoke test'
wsl -d NixOS -- /run/current-system/sw/bin/uname -a
if ($LASTEXITCODE -ne 0) { throw "smoke test failed (exit $LASTEXITCODE)" }

Write-Host 'NixOS-WSL imported. Default user is `nixos` until mandragora bootstrap runs.'
