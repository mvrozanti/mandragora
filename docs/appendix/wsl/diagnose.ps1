$ErrorActionPreference = 'Continue'
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/wsl'
$STATE_DIR = "$env:LOCALAPPDATA\Mandragora"
if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LOG = "$STATE_DIR\diagnose-$stamp.log"
Start-Transcript -Path $LOG -Append | Out-Null

function Section($t) {
    Write-Host ''
    Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan
}
function Try-Run($label, [scriptblock]$sb) {
    Write-Host ('-- ' + $label) -ForegroundColor DarkCyan
    try { & $sb } catch { Write-Host ('  ERR: ' + $_.Exception.Message) -ForegroundColor Red }
}

Section 'host'
Try-Run 'os' { (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture | Format-List | Out-String).Trim() }
Try-Run 'cpu' { (Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions | Format-List | Out-String).Trim() }
Try-Run 'computer' { (Get-CimInstance Win32_ComputerSystem | Select-Object Name, PartOfDomain, Domain, Manufacturer, Model | Format-List | Out-String).Trim() }
Try-Run 'aad-enrolled' {
    $enr = Test-Path 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    $aad = $false
    if ($enr) {
        $aad = ((Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^[0-9A-F-]{36}$' }).Count -gt 0)
    }
    Write-Host ('  AAD-enrolled: ' + $aad)
}
Try-Run 'admin-context' {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host ('  IsAdmin: ' + $isAdmin)
}

Section 'wsl-stack'
Try-Run 'wsl --version' { & wsl --version 2>&1 }
Try-Run 'wsl --status' { & wsl --status 2>&1 }
Try-Run 'wsl --list --verbose' { & wsl --list --verbose 2>&1 }
Try-Run 'wsl optional features' {
    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue |
        Select-Object FeatureName, State | Format-List | Out-String
    Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue |
        Select-Object FeatureName, State | Format-List | Out-String
    Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction SilentlyContinue |
        Select-Object FeatureName, State | Format-List | Out-String
}
Try-Run 'wslg.exe presence' {
    Write-Host ('  wslg.exe: ' + (Test-Path 'C:\Program Files\WSL\wslg.exe'))
    Write-Host ('  wsl.exe : ' + (Test-Path 'C:\Program Files\WSL\wsl.exe'))
}

Section 'defender'
Try-Run 'defender status' {
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        (Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled, IsTamperProtected, AntivirusEnabled | Format-List | Out-String).Trim()
    } else { Write-Host '  Defender cmdlets unavailable' }
}
Try-Run 'defender preferences' {
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        $p = Get-MpPreference
        Write-Host ('  ExclusionPath: ' + ($p.ExclusionPath -join '; '))
        Write-Host ('  ExclusionProcess: ' + ($p.ExclusionProcess -join '; '))
        Write-Host ('  DisableRealtimeMonitoring: ' + $p.DisableRealtimeMonitoring)
    }
}
Try-Run 'recent defender quarantine (last 7d)' {
    Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 50 -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 1006,1007,1015,1116,1117,2050 } |
        Select-Object -First 10 TimeCreated, Id, @{n='Msg';e={$_.Message.Substring(0,[Math]::Min(200,$_.Message.Length))}} |
        Format-List | Out-String
}

Section 'launchers'
Try-Run 'nixos shortcuts' {
    $paths = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
               "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Recurse -Filter *NixOS*.lnk -ErrorAction SilentlyContinue | ForEach-Object {
                $s = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName)
                Write-Host ('  path   : ' + $_.FullName)
                Write-Host ('  target : ' + $s.TargetPath)
                Write-Host ('  args   : ' + $s.Arguments)
                Write-Host ''
            }
        }
    }
}
Try-Run 'windows terminal nixos profile' {
    $wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbcwe\LocalState\settings.json"
    if (Test-Path $wt) {
        $j = Get-Content $wt -Raw | ConvertFrom-Json
        $profiles = $j.profiles.list | Where-Object { $_.name -match 'NixOS' -or $_.source -match 'WSL' -or $_.commandline -match 'NixOS' }
        $profiles | Format-List name, source, commandline, hidden | Out-String
    } else { Write-Host '  no Windows Terminal settings.json' }
}

Section 'distro-internal'
$probe = "$env:TEMP\mandragora-diag-probe.sh"
$probeBody = @'
set +u
[ -f /etc/profile ] && . /etc/profile
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH
set -u
banner() { printf "\n### %s ###\n" "$1"; }
banner identity
id
hostname
banner os-release
cat /etc/os-release 2>&1 | head -10
banner kernel
uname -a
banner generation
nixos-version
readlink /run/current-system 2>&1
banner mandragora-rev
cat /run/current-system/git-revision 2>&1 || echo "no git-revision"
banner wsl-env
env | grep -E '^(WSL|WAYLAND|DISPLAY|XDG|PATH|TERM|MANDRAGORA)' | sort
banner run-user
ls -la /run/user/ 2>&1
banner systemd-system
systemctl is-system-running 2>&1
systemctl --failed --no-pager 2>&1 | head -20
banner systemd-user
systemctl --user is-system-running 2>&1
banner home-manager-files
ls -la ~/.zshrc ~/.p10k.zsh ~/.config/tmux/tmux.conf 2>&1
banner zshrc-tail
head -25 ~/.zshrc 2>&1
banner tmux-version
tmux -V 2>&1
banner tmux-server-start
timeout 6 tmux -L diag new -d -s probe 'sleep 2' 2>&1
echo tmux-rc=$?
tmux -L diag ls 2>&1
tmux -L diag kill-server 2>/dev/null
banner zsh-interactive-trace
script -qc 'timeout 12 zsh -i -x -c "print READY; exit"' /dev/null 2>&1 | tail -60
banner zsh-interactive-noexec
script -qc 'timeout 8 env MANDRAGORA_NO_TMUX=1 zsh -i -c "print READY; exit"' /dev/null 2>&1 | tail -20
banner storepath-stat
ls -la /nix/store/.links 2>&1 | head -3
df -h /nix /home 2>&1
banner journal-recent
journalctl -b -p err --no-pager 2>&1 | tail -30
'@
Set-Content -Path $probe -Value $probeBody -Encoding ascii
$drive = $probe.Substring(0,1).ToLower()
$rest = $probe.Substring(2) -replace '\\','/'
$wslProbe = "/mnt/$drive$rest"

Try-Run 'wsl direct echo (no shell)' {
    $start = Get-Date
    $out = & wsl -d NixOS --exec /run/current-system/sw/bin/echo READY 2>&1
    $dur = ((Get-Date) - $start).TotalSeconds
    Write-Host ('  duration: {0:N1}s' -f $dur)
    Write-Host ('  output  : ' + ($out -join ' | '))
}
Try-Run 'distro internal probe (non-interactive)' {
    $start = Get-Date
    & wsl -d NixOS --exec /bin/sh -c "bash $wslProbe" 2>&1
    Write-Host ('  duration: {0:N1}s' -f ((Get-Date) - $start).TotalSeconds)
}
Try-Run 'interactive launcher timeout test' {
    $tmp = "$env:TEMP\mandragora-diag-interactive.txt"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $start = Get-Date
    $job = Start-Job -ScriptBlock {
        param($outFile)
        & wsl -d NixOS 2>&1 > $outFile
    } -ArgumentList $tmp
    if (Wait-Job $job -Timeout 15) {
        Receive-Job $job 2>&1 | Out-Null
        Write-Host ('  exited in {0:N1}s' -f ((Get-Date) - $start).TotalSeconds)
    } else {
        Stop-Job $job
        Write-Host ('  HUNG (>15s) -- consistent with reported symptom') -ForegroundColor Yellow
        Get-Process wsl, init, NixOS -ErrorAction SilentlyContinue | Format-Table Id, ProcessName | Out-String
        Get-Process | Where-Object { $_.ProcessName -match 'wsl|tmux' } | Format-Table Id, ProcessName | Out-String
        & wsl --shutdown 2>&1 | Out-Null
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if (Test-Path $tmp) {
        Write-Host '  captured output:'
        Get-Content $tmp -Raw
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host '  no output captured'
    }
}

Section 'done'
Stop-Transcript | Out-Null
Write-Host ''
Write-Host ('==> report saved: ' + $LOG) -ForegroundColor Green
Write-Host ('==> paste contents to your debugging channel') -ForegroundColor Green
