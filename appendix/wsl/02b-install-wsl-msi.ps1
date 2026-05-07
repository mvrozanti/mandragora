# Install WSL2 from the GitHub-released MSI.
# Use this when the inbox `wsl --install` stub can't bootstrap (no MS
# Store auth, headless VMs). Run after 02-install-wsl.ps1 enabled the
# Windows optional features and the box was rebooted.

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'must run as administrator'
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host '[1/4] resolving latest WSL release'
$rel = Invoke-RestMethod 'https://api.github.com/repos/microsoft/WSL/releases/latest' -UseBasicParsing
$msi = $rel.assets | Where-Object { $_.name -match 'wsl.*\.x64\.msi$' } | Select-Object -First 1
if (-not $msi) { throw 'no x64 MSI in latest release' }
Write-Host "    $($rel.tag_name): $($msi.name)"

Write-Host '[2/4] downloading'
$dest = "$env:USERPROFILE\Downloads\$($msi.name)"
if (-not (Test-Path $dest)) {
    Invoke-WebRequest -Uri $msi.browser_download_url -OutFile $dest -UseBasicParsing
}
Write-Host "    $dest ($((Get-Item $dest).Length) bytes)"

Write-Host '[3/4] msiexec install'
$logPath = "$env:TEMP\wsl-msi-install.log"
$p = Start-Process msiexec.exe -ArgumentList "/i `"$dest`" /qn /norestart /l*v `"$logPath`"" -Wait -PassThru
if ($p.ExitCode -ne 0) {
    Write-Host "    msiexec exit $($p.ExitCode); see $logPath"
    exit $p.ExitCode
}

Write-Host '[4/4] smoke test'
& wsl --version
& wsl --set-default-version 2

Write-Host 'WSL MSI installed.'
