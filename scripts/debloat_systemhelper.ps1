param(
    [string]$Serial = '',
    [string]$Package = 'com.mobiletools.systemhelper'
)
# debloat_systemhelper.ps1
# Example: remove a preinstalled telemetry package for user 0, then verify.
# Requires: adb on PATH (or set $AdbPath below).
#
# usage:
#   .\debloat_systemhelper.ps1 -Serial <device-ip>:<port> -Package com.vendor.telemetry

$ErrorActionPreference = 'Continue'
$AdbPath = if ($env:ADB) { $env:ADB } else { 'adb' }

function Sh([string]$cmd) { ((& $AdbPath -s $Serial shell $cmd 2>&1) -join "`n").Trim() }
function Say($m) { Write-Host $m }

if (-not $Serial) {
    $d = (& $AdbPath devices) -join "`n"
    $m = [regex]::Match($d, '(?m)^(\S+)\s+device$')
    if (-not $m.Success) { Say 'no device in "device" state; connect first'; return }
    $Serial = $m.Groups[1].Value
}
Say "target: $Serial / $Package"

Say ''
Say '== 1. before =='
Say ('path   : ' + (Sh "pm path $Package"))
Say ('enabled: ' + (Sh "dumpsys package $Package | grep -m1 -o enabled=[0-9]*"))
Say ('procs  : ' + (Sh "ps -A -o NAME | grep -c ${Package##*.}"))

Say ''
Say '== 2. stop + clear data =='
Sh "am force-stop $Package" | Out-Null
Sh "pm clear $Package" | Out-Null

Say ''
Say '== 3. uninstall for user 0 =='
$out1 = Sh "pm uninstall --user 0 $Package"
Say $out1
if ($out1 -notmatch 'Success') {
    Say '  fallback: cmd package uninstall'
    Say (Sh "cmd package uninstall --user 0 $Package")
}

Say ''
Say '== 4. verify =='
Say ('pm list hits : ' + (Sh "pm list packages | grep -c $Package"))
Say ('pm path      : ' + (Sh "pm path $Package"))
Say ('procs        : ' + (Sh "ps -A -o NAME | grep -c ${Package##*.}"))
Say ('state        : ' + (Sh "dumpsys package $Package | grep -m1 -E 'User 0'"))

$hits = Sh "pm list packages | grep -c $Package"
if ($hits -eq '0') {
    Say ''
    Say '[OK] removed for user 0. The APK still exists under /system (root required to delete).'
    Say '     Verify again after a reboot: pm list packages -u | grep <pkg>'
} else {
    Say ''
    Say '[BLOCKED] OEM protection (e.g. DELETE_FAILED_USER_RESTRICTED). Options:'
    Say '  - appops tightening (see reapply_appops.sh)'
    Say '  - root: pm disable / remove the /system APK'
}
