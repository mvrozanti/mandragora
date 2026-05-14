# Reverts every Windows-side cosmetic / privacy registry tweak that
# 01-rice.ps1 may have applied. Run this if rice ran on a box where
# you didn't want it.
#
# Usage (admin PowerShell):
#   iex (iwr https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/wsl/01-unrice.ps1)

$ErrorActionPreference = 'Continue'
$WarningPreference = 'SilentlyContinue'

function Reset-Reg($path, $name) {
    try {
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction Stop
            Write-Host "  cleared ${path}\${name}"
        }
    } catch {
        Write-Host "  skipped ${path}\${name} : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Host '[1/8] revert dark theme (back to system default)'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme'

Write-Host '[2/8] timezone left untouched (rerun tzutil if you need to change it back)'

Write-Host '[3/8] revert explorer view tweaks'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSuperHidden'

Write-Host '[4/8] revert taskbar tweaks'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl'

Write-Host '[5/8] revert telemetry policy'
Reset-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled'

Write-Host '[6/8] revert Cortana / Bing search blocks'
Reset-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent'

Write-Host '[7/8] revert lockscreen suggestion blocks'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled'
Reset-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled'

Write-Host '[8/8] restart explorer'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }

Write-Host 'unrice complete. settings will reapply Windows defaults on next logon.'
