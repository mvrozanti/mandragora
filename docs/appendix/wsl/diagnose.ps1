$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$BASE = 'https://raw.githubusercontent.com/mvrozanti/mandragora/master/docs/appendix/wsl'
$DESKTOP = [Environment]::GetFolderPath('Desktop')
if (-not $DESKTOP -or -not (Test-Path $DESKTOP)) { $DESKTOP = "$env:USERPROFILE\Desktop" }
if (-not (Test-Path $DESKTOP)) { New-Item -ItemType Directory -Path $DESKTOP -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LOG = Join-Path $DESKTOP "mandragora-wsl-diagnose-$stamp.log"
Start-Transcript -Path $LOG -Append | Out-Null
Write-Host ('==> writing report to: ' + $LOG) -ForegroundColor Green
Write-Host ('==> script will take 2-5 min, do not close window') -ForegroundColor Green

function Section($t) {
    Write-Host ''
    Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan
}
function Try-Run($label, [scriptblock]$sb) {
    Write-Host ('-- ' + $label) -ForegroundColor DarkCyan
    try { & $sb 2>&1 | Out-String -Stream | ForEach-Object { Write-Host ('  ' + $_) } }
    catch { Write-Host ('  ERR: ' + $_.Exception.Message) -ForegroundColor Red }
}
function Run-WithTimeout($label, $cmd, $cmdArgs, $secs) {
    Write-Host ('-- ' + $label + '  [timeout ' + $secs + 's]') -ForegroundColor DarkCyan
    $tmpOut = [IO.Path]::GetTempFileName()
    $tmpErr = [IO.Path]::GetTempFileName()
    $start = Get-Date
    $proc = $null
    try {
        $proc = Start-Process -FilePath $cmd -ArgumentList $cmdArgs `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr `
            -NoNewWindow -PassThru
    } catch {
        Write-Host ('  spawn ERR: ' + $_.Exception.Message) -ForegroundColor Red
        Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
        return
    }
    if (-not $proc.WaitForExit($secs * 1000)) {
        Write-Host ('  HUNG (>' + $secs + 's) -- consistent with reported symptom') -ForegroundColor Yellow
        try { $proc.Kill() } catch {}
        $proc.WaitForExit(2000) | Out-Null
        $hung = $true
    } else {
        $hung = $false
    }
    $proc.WaitForExit()
    $exit = $null
    try { $exit = $proc.ExitCode } catch {}
    $dur = ((Get-Date) - $start).TotalSeconds
    Write-Host ('  duration : {0:N1}s' -f $dur)
    Write-Host ('  exit-code: ' + $(if ($null -eq $exit) { '(unknown)' } else { $exit }))
    Write-Host ('  hung     : ' + $hung)
    if (Test-Path $tmpOut) {
        $o = (Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue)
        if ($o) { Write-Host '  stdout:'; ($o -split "`n") | ForEach-Object { Write-Host ('    ' + $_.TrimEnd()) } }
    }
    if (Test-Path $tmpErr) {
        $e = (Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue)
        if ($e) { Write-Host '  stderr:'; ($e -split "`n") | ForEach-Object { Write-Host ('    ' + $_.TrimEnd()) } }
    }
    Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
}

Section 'meta'
Try-Run 'timestamp + user' {
    Write-Host ('  utc      : ' + (Get-Date).ToUniversalTime().ToString('o'))
    Write-Host ('  local    : ' + (Get-Date).ToString('o'))
    Write-Host ('  user     : ' + $env:USERNAME)
    Write-Host ('  computer : ' + $env:COMPUTERNAME)
}
Try-Run 'admin context' {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host ('  IsAdmin: ' + $isAdmin)
}

Section 'host'
Try-Run 'os'        { Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime, InstallDate | Format-List }
Try-Run 'cpu'       { Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions, VMMonitorModeExtensions | Format-List }
Try-Run 'computer'  { Get-CimInstance Win32_ComputerSystem | Select-Object Name, PartOfDomain, Domain, Manufacturer, Model, TotalPhysicalMemory, NumberOfProcessors | Format-List }
Try-Run 'bios uefi' { Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate | Format-List }
Try-Run 'aad / domain' {
    $enr = $false; $aad = $false; $cnt = 0
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Enrollments') {
        $enr = $true
        $matches = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
                   Where-Object { $_.PSChildName -match '^[0-9A-F-]{36}$' }
        $cnt = ($matches | Measure-Object).Count
        $aad = $cnt -gt 0
    }
    Write-Host ('  enrollments-key  : ' + $enr)
    Write-Host ('  enrolled-guids   : ' + $cnt)
    Write-Host ('  AAD-enrolled     : ' + $aad)
    try { dsregcmd /status 2>&1 | Select-String -Pattern 'AzureAdJoined|DomainJoined|EnterpriseJoined|TenantName|TenantId' | ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) } } catch {}
}

Section 'security-stack'
Try-Run 'defender status' {
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled, IsTamperProtected, AntivirusEnabled, AntispywareEnabled, NISEnabled, BehaviorMonitorEnabled, OnAccessProtectionEnabled, AMRunningMode | Format-List
    } else { Write-Host '  Get-MpComputerStatus not available' }
}
Try-Run 'defender preferences' {
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        $p = Get-MpPreference
        Write-Host ('  ExclusionPath        : ' + ($p.ExclusionPath -join '; '))
        Write-Host ('  ExclusionProcess     : ' + ($p.ExclusionProcess -join '; '))
        Write-Host ('  ExclusionExtension   : ' + ($p.ExclusionExtension -join '; '))
        Write-Host ('  DisableRealtimeMon   : ' + $p.DisableRealtimeMonitoring)
        Write-Host ('  DisableScriptScanning: ' + $p.DisableScriptScanning)
    }
}
Try-Run 'defender quarantine (last 50 events)' {
    Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 50 -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 1006,1007,1015,1116,1117,1118,1119,2050 } |
        Select-Object -First 10 TimeCreated, Id, @{n='Msg';e={$_.Message.Substring(0,[Math]::Min(250,$_.Message.Length))}} |
        Format-List
}
Try-Run 'applocker policy' {
    if (Test-Path 'HKLM:\Software\Policies\Microsoft\Windows\SrpV2') {
        Get-ChildItem 'HKLM:\Software\Policies\Microsoft\Windows\SrpV2' -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host ('  rule-collection: ' + $_.PSChildName)
            Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue | Format-List
        }
    } else { Write-Host '  no SrpV2 (AppLocker) policy' }
}
Try-Run 'wdac / device guard' {
    Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue |
        Select-Object SecurityServicesConfigured, SecurityServicesRunning, CodeIntegrityPolicyEnforcementStatus, UsermodeCodeIntegrityPolicyEnforcementStatus, VirtualizationBasedSecurityStatus | Format-List
}
Try-Run 'smart app control + smartscreen' {
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableSmartScreen -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -ErrorAction SilentlyContinue | Format-List
}
Try-Run 'other antivirus / EDR vendors' {
    Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntivirusProduct -ErrorAction SilentlyContinue |
        Select-Object displayName, productState, instanceGuid | Format-List
    $edrPatterns = 'cylance|sentinel|crowdstrike|carbonblack|symantec|sophos|trendmicro|mcafee|kaspersky|eset|bitdefender|trellix|harmony|elastic-agent|cb-defense'
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $edrPatterns -or $_.DisplayName -match $edrPatterns } |
        Select-Object Name, DisplayName, State, StartMode | Format-Table -AutoSize
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $edrPatterns } |
        Select-Object ProcessName, Id, Path | Format-Table -AutoSize
}

Section 'policy'
Try-Run 'wsl policy keys' {
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WSL', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss') {
        if (Test-Path $k) {
            Write-Host ('  key: ' + $k)
            Get-ItemProperty $k -ErrorAction SilentlyContinue | Format-List
        }
    }
}
Try-Run 'intune / mdm policy manager presence' {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device') {
        Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device' -ErrorAction SilentlyContinue |
            Select-Object PSChildName | Format-Table -AutoSize
    } else { Write-Host '  no PolicyManager (no Intune/MDM)' }
}
Try-Run 'group policy summary' {
    gpresult /scope:computer /r 2>&1 | Select-Object -First 60
}

Section 'hyper-v + virt'
Try-Run 'bcdedit hypervisorlaunchtype' { bcdedit /enum '{current}' 2>&1 | Select-String -Pattern 'hypervisorlaunchtype|nx|description' }
Try-Run 'optional features' {
    foreach ($f in 'Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform','HypervisorPlatform','Microsoft-Hyper-V-All','Microsoft-Hyper-V') {
        $r = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($r) { Write-Host ('  {0,-45} : {1}' -f $r.FeatureName, $r.State) }
    }
}
Try-Run 'vmcompute + lxssmanager services' {
    Get-Service vmcompute, LxssManager, LxssManagerUser, hns, HvHost, vmms -ErrorAction SilentlyContinue | Format-Table -AutoSize
}

Section 'wsl-stack'
Try-Run 'wsl --version' { & wsl --version 2>&1 }
Try-Run 'wsl --status'  { & wsl --status 2>&1 }
Try-Run 'wsl --list --verbose' { & wsl --list --verbose 2>&1 }
Try-Run 'wsl binaries on disk' {
    Write-Host ('  C:\Program Files\WSL\wsl.exe  : ' + (Test-Path 'C:\Program Files\WSL\wsl.exe'))
    Write-Host ('  C:\Program Files\WSL\wslg.exe : ' + (Test-Path 'C:\Program Files\WSL\wslg.exe'))
    Write-Host ('  inbox stub System32\wsl.exe   : ' + (Test-Path "$env:WINDIR\System32\wsl.exe"))
    Get-Command wsl  -ErrorAction SilentlyContinue | Select-Object Source | Format-List
    Get-Command wslg -ErrorAction SilentlyContinue | Select-Object Source | Format-List
}
Try-Run 'C:\Users\<you>\.wslconfig' {
    $p = "$env:USERPROFILE\.wslconfig"
    if (Test-Path $p) { Get-Content $p } else { Write-Host '  (none)' }
}
Try-Run 'wsl appdata logs' {
    $p = "$env:LOCALAPPDATA\Microsoft\WSL"
    if (Test-Path $p) {
        Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
    } else { Write-Host '  (none)' }
}

Section 'launchers'
Try-Run 'NixOS .lnk shortcuts' {
    $paths = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
               "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Recurse -Filter *NixOS*.lnk -ErrorAction SilentlyContinue | ForEach-Object {
                $s = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName)
                Write-Host ('  path    : ' + $_.FullName)
                Write-Host ('  target  : ' + $s.TargetPath)
                Write-Host ('  args    : ' + $s.Arguments)
                Write-Host ('  workdir : ' + $s.WorkingDirectory)
                Write-Host ''
            }
        }
    }
}
Try-Run 'windows terminal NixOS/WSL profiles' {
    $wts = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbcwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbcwe\LocalState\settings.json"
    )
    foreach ($wt in $wts) {
        if (Test-Path $wt) {
            Write-Host ('  settings: ' + $wt)
            $j = Get-Content $wt -Raw | ConvertFrom-Json
            $profs = $j.profiles.list | Where-Object { $_.name -match 'NixOS' -or $_.source -match 'WSL' -or $_.commandline -match 'NixOS' }
            $profs | Select-Object name, source, commandline, hidden, font, colorScheme | Format-List
            Write-Host ('  defaultProfile: ' + $j.defaultProfile)
        }
    }
}

Section 'event-logs'
Try-Run 'Application: errors mentioning WSL/Lxss (last 200 scanned)' {
    Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.LevelDisplayName -in 'Error','Warning' -and ($_.ProviderName -match 'wsl|lxss' -or $_.Message -match 'WSL|NixOS|Lxss') } |
        Select-Object -First 15 TimeCreated, LevelDisplayName, ProviderName, Id, @{n='Msg';e={$_.Message.Substring(0,[Math]::Min(250,$_.Message.Length))}} |
        Format-List
}
Try-Run 'System: errors mentioning WSL/Lxss/Hyper-V (last 200 scanned)' {
    Get-WinEvent -LogName System -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.LevelDisplayName -in 'Error','Warning' -and ($_.ProviderName -match 'wsl|lxss|vmcompute|hyper' -or $_.Message -match 'WSL|NixOS|Lxss|Hyper-V') } |
        Select-Object -First 15 TimeCreated, LevelDisplayName, ProviderName, Id, @{n='Msg';e={$_.Message.Substring(0,[Math]::Min(250,$_.Message.Length))}} |
        Format-List
}

Section 'network / vpn'
Try-Run 'active adapters' {
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Disabled' } |
        Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress | Format-Table -AutoSize
}
Try-Run 'vpn-related adapters + services' {
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'vpn|tap|tun|cisco|forticlient|paloalto|zscaler|netskope|globalprotect|openvpn|wireguard|tailscale|anyconnect|prisma' } |
        Format-List Name, InterfaceDescription, Status
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vpn|forticlient|paloalto|zscaler|netskope|cisco|anyconnect|globalprotect|openvpn|wireguard' -or $_.DisplayName -match 'VPN|Forti|Palo|Zscaler|Netskope|Cisco AnyConnect|GlobalProtect' } |
        Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
}
Try-Run 'WSL vEthernet routing' {
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'WSL|Hyper-V' } |
        Format-List InterfaceAlias, IPv4Address, IPv4DefaultGateway
}

Section 'distro-internal'
$probe = Join-Path $env:TEMP 'mandragora-diag-probe.sh'
$probeBody = @'
set +u
[ -f /etc/profile ] && . /etc/profile
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH
set -u
banner() { printf "\n### %s ###\n" "$1"; }

banner identity
id
whoami
hostname
getent passwd "$(whoami)" 2>&1

banner os-release
cat /etc/os-release 2>&1 | head -10

banner kernel-uname
uname -a

banner generation
nixos-version
readlink /run/current-system 2>&1
test -r /run/current-system/git-revision && echo "mandragora-rev: $(cat /run/current-system/git-revision)" || echo "(no git-revision)"

banner wsl-env
env | grep -E '^(WSL|WAYLAND|DISPLAY|XDG|PATH|TERM|MANDRAGORA|LANG|LC_)' | sort

banner wsl-conf
cat /etc/wsl.conf 2>&1 || echo "(no /etc/wsl.conf)"

banner shells-and-defaults
cat /etc/shells 2>&1
echo "login shell (getent): $(getent passwd "$(whoami)" | cut -d: -f7)"

banner run-user-dir
ls -la /run/user/ 2>&1

banner systemd-system
systemctl is-system-running 2>&1
systemctl --failed --no-pager 2>&1 | head -30

banner systemd-user
systemctl --user is-system-running 2>&1
systemctl --user --failed --no-pager 2>&1 | head -30

banner home-manager-files
ls -la ~/.zshrc ~/.p10k.zsh ~/.config/tmux/tmux.conf 2>&1
readlink ~/.zshrc 2>&1
readlink ~/.p10k.zsh 2>&1

banner zshrc-head
head -40 ~/.zshrc 2>&1

banner tmux-version
tmux -V 2>&1

banner tmux-server-start
timeout 8 tmux -L diag new -d -s probe 'sleep 2' 2>&1
echo tmux-spawn-rc=$?
tmux -L diag ls 2>&1
tmux -L diag kill-server 2>/dev/null

banner zsh-noninteractive
( echo "noninteractive-ok" | timeout 5 zsh -c 'print HELLO' 2>&1 )
echo rc=$?

banner zsh-interactive-trace
script -qc 'timeout 12 zsh -i -x -c "print READY; exit"' /dev/null 2>&1 | tail -120

banner zsh-interactive-without-tmux
script -qc 'timeout 8 env TMUX=__SKIP__ zsh -i -c "print READY; exit"' /dev/null 2>&1 | tail -30

banner bash-interactive-baseline
script -qc 'timeout 6 bash -i -c "echo READY-BASH; exit"' /dev/null 2>&1 | tail -10

banner storepath-stat
df -h /nix /home /tmp 2>&1
echo "/nix/store entries: $(ls /nix/store 2>/dev/null | wc -l)"

banner journal-recent-errors
journalctl -b -p err --no-pager 2>&1 | tail -40

banner journal-user-errors
journalctl --user -b -p err --no-pager 2>&1 | tail -40

banner kernel-log-tail
dmesg 2>&1 | tail -40 || echo "(dmesg requires sudo)"

banner mem-uptime
free -h 2>&1
uptime 2>&1

banner process-tree
ps auxf 2>&1 | head -50

banner strace-zsh
if command -v strace >/dev/null 2>&1; then
  timeout 8 strace -f -tt -o /tmp/zsh-strace.log -e trace=openat,connect,read,write,execve zsh -i -c 'print READY; exit' >/dev/null 2>&1
  echo --- strace tail ---
  tail -120 /tmp/zsh-strace.log 2>&1
else
  echo "(strace not in PATH)"
fi
'@
Set-Content -Path $probe -Value $probeBody -Encoding ascii
$drive = $probe.Substring(0,1).ToLower()
$rest  = $probe.Substring(2) -replace '\\','/'
$wslProbe = "/mnt/$drive$rest"

Try-Run 'wsl raw echo (no shell)' {
    $start = Get-Date
    $out = & wsl -d NixOS --exec /run/current-system/sw/bin/echo READY 2>&1
    $dur = ((Get-Date) - $start).TotalSeconds
    Write-Host ('  duration: {0:N1}s' -f $dur)
    Write-Host ('  output  : ' + ($out -join ' | '))
}
Try-Run 'distro probe (non-interactive)' {
    $start = Get-Date
    & wsl -d NixOS --exec /bin/sh -c "bash $wslProbe" 2>&1
    Write-Host ('  duration: {0:N1}s' -f ((Get-Date) - $start).TotalSeconds)
}

Section 'repro-matrix'
Write-Host '(each invocation gets 15-20s; HUNG means stuck shell reproduced)'
Run-WithTimeout 'wsl -d NixOS (default user shell)' 'wsl.exe' @('-d','NixOS') 20
Run-WithTimeout 'wsl -d NixOS --exec /bin/sh -c id' 'wsl.exe' @('-d','NixOS','--exec','/bin/sh','-c','id') 10
Run-WithTimeout 'wsl -d NixOS --exec bash -lc id' 'wsl.exe' @('-d','NixOS','--exec','/run/current-system/sw/bin/bash','-lc','id') 15
Run-WithTimeout 'wsl -d NixOS --exec zsh -ic exit' 'wsl.exe' @('-d','NixOS','--exec','/run/current-system/sw/bin/zsh','-i','-c','exit') 15
Run-WithTimeout 'wsl -d NixOS TMUX=skip zsh -ic exit' 'wsl.exe' @('-d','NixOS','--exec','/run/current-system/sw/bin/env','TMUX=skip','/run/current-system/sw/bin/zsh','-i','-c','exit') 15
if (Test-Path 'C:\Program Files\WSL\wslg.exe') {
    Run-WithTimeout 'wslg.exe -d NixOS --cd ~ -- echo READY' 'C:\Program Files\WSL\wslg.exe' @('-d','NixOS','--cd','~','--','echo','READY') 15
}

Section 'post-repro state'
Try-Run 'distro state after repro' { & wsl --list --verbose 2>&1 }
Try-Run 'orphaned wsl host processes' {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'wsl|wslg|wslservice|wslhost' } |
        Select-Object Id, ProcessName, StartTime | Format-Table -AutoSize
}
Try-Run 'shutdown WSL to clean state' { & wsl --shutdown 2>&1 }

Section 'done'
Stop-Transcript | Out-Null
Write-Host ''
Write-Host ('==> report on Desktop: ' + (Split-Path -Leaf $LOG)) -ForegroundColor Green
Write-Host ('==> full path        : ' + $LOG) -ForegroundColor Green
Write-Host ('==> open / paste contents back') -ForegroundColor Green
