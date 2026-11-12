# Boot an Android 11 (API 30) AOSP emulator, apply the module's font files to
# /system, reboot, and capture before/after screenshots.
#
# The module overlay is emulated by pushing the exact same files to /system,
# which is what Magisk does at boot. Everything else about the module zip
# (module.prop, customize.sh, META-INF) can only be exercised on a real device.

param(
    [string]$Sdk = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$Avd = "a11-test",
    [string]$Package = "system-images;android-30;default;x86_64",
    [switch]$KeepRunning,
    [switch]$SkipBoot
)

$ErrorActionPreference = "Continue"   # native tools (sdkmanager/avdmanager) warn on stderr
$root      = Split-Path -Parent $PSScriptRoot
$emulator  = Join-Path $Sdk "emulator\emulator.exe"
$adb       = Join-Path $Sdk "platform-tools\adb.exe"
$avdmanage = Join-Path $Sdk "cmdline-tools\latest\bin\avdmanager.bat"
$shots     = Join-Path $root "dist\test"
New-Item -ItemType Directory -Force -Path $shots | Out-Null

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $adb @Args 2>&1
}

function Wait-Device {
    param([int]$TimeoutSec = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = (& $adb get-state 2>&1) -join " "
        if ($state -match "device") {
            $boot = (& $adb shell getprop sys.boot_completed 2>&1) -join ""
            if ($boot.Trim() -eq "1") { return $true }
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Save-Shot {
    param([string]$Name)
    $path = Join-Path $shots $Name
    # Must go through cmd redirection: PowerShell would decode the PNG as text.
    & cmd.exe /c "`"$adb`" exec-out screencap -p > `"$path`""
    Write-Host "  screenshot -> $path"
}

function Wake-Emulator {
    & $adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    & $adb shell wm dismiss-keyguard | Out-Null
    Start-Sleep -Seconds 1
}

function Show-Settings {
    & $adb shell am start -n com.android.settings/.Settings | Out-Null
    Start-Sleep -Seconds 4
}

if (-not (Test-Path (Join-Path $Sdk "system-images\android-30\default\x86_64"))) {
    throw "API 30 system image missing. Run: sdkmanager `"$Package`""
}

$avds = (& $avdmanage list avd 2>&1) -join "`n"
if ($avds -notmatch [regex]::Escape($Avd)) {
    Write-Host "Creating AVD $Avd"
    "no`r`n" | & $avdmanage create avd -n $Avd -k $Package -d pixel_2 --force 2>&1 | Out-Host
}

& $adb kill-server 2>&1 | Out-Null

if (-not $SkipBoot) {
    Write-Host "Starting emulator $Avd"
    Start-Process -FilePath $emulator -ArgumentList @(
        "-avd", $Avd, "-no-snapshot", "-no-audio", "-no-boot-anim",
        "-no-window", "-gpu", "swiftshader_indirect", "-writable-system"
    ) | Out-Null
    if (-not (Wait-Device)) { throw "Emulator did not boot in time" }
    Write-Host "Booted"
}

# Deterministic screen: Settings, then compare.
Wake-Emulator
Show-Settings
Save-Shot "1-before.png"

Write-Host "Remounting /system and pushing module files"
(& $adb root) | Out-Null
Start-Sleep -Seconds 3
(& $adb remount) | Out-Host
Start-Sleep -Seconds 3

# On API 30 the emulator sets up overlayfs on /system only on the next boot,
# so reboot once after `adb remount` and confirm the partition is writable.
& $adb reboot | Out-Null
Start-Sleep -Seconds 5
if (-not (Wait-Device)) { throw "Device did not come back after remount" }
(& $adb root) | Out-Null
Start-Sleep -Seconds 3
$rw = (& $adb shell "touch /system/etc/.rwtest && rm /system/etc/.rwtest && echo RW_OK" 2>&1) -join " "
if ($rw -notmatch "RW_OK") { throw "System partition still read-only: $rw" }
Write-Host "  /system is writable"

& $adb push (Join-Path $root "system\etc\fonts.xml") /system/etc/fonts.xml | Out-Host
foreach ($weight in "Light", "Regular", "Medium", "Bold", "Heavy") {
    & $adb push (Join-Path $root "system\fonts\MiSans-$weight.ttf") /system/fonts/MiSans-$weight.ttf | Out-Host
}
& $adb shell "chmod 644 /system/etc/fonts.xml /system/fonts/MiSans-*.ttf"
& $adb shell "chown root:root /system/etc/fonts.xml /system/fonts/MiSans-*.ttf"
& $adb shell "restorecon -R /system/fonts; restorecon /system/etc/fonts.xml"
& $adb shell sync

Write-Host "Rebooting to apply"
& $adb reboot | Out-Null
Start-Sleep -Seconds 5
if (-not (Wait-Device)) { throw "Device did not come back after reboot" }
Write-Host "Booted with MiSans"

& $adb shell am start -n com.android.settings/.Settings | Out-Null
Wake-Emulator
Show-Settings
Save-Shot "2-after-settings.png"

# Chinese sample: notification text goes through the system UI text stack.
& $adb shell cmd notification post misans "简体中文测试 MiSans 字体 123 ABC" 2>&1 | Out-Null
& $adb shell cmd statusbar expand-notifications 2>&1 | Out-Null
Start-Sleep -Seconds 3
Save-Shot "3-after-chinese.png"

Write-Host "Font related log lines (errors only):"
(& $adb logcat -d -v brief "*:E" 2>&1) | Select-String -Pattern "font|Font|typeface|Typeface" | Select-Object -First 20 | ForEach-Object { "  " + $_.Line }

Write-Host "Applied config:"
(& $adb shell "grep -c MiSans /system/etc/fonts.xml" 2>&1) | ForEach-Object { "  MiSans references: $_" }
(& $adb shell "ls -l /system/fonts/MiSans-*.ttf" 2>&1) | ForEach-Object { "  $_" }

if ($KeepRunning) {
    Write-Host "Emulator left running (avd: $Avd)"
} else {
    & $adb emu kill | Out-Null
}
