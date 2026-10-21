$ErrorActionPreference = 'Continue'

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb = Join-Path $BaseDir 'adb.exe'
$Fastboot = Join-Path $BaseDir 'fastboot.exe'
$AppDir = Join-Path $BaseDir 'app'
$BackupRoot = Join-Path $BaseDir 'backups'

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host "==== $Text ===="
}

function Require-Adb {
    if (-not (Test-Path -LiteralPath $Adb)) {
        throw "adb.exe not found next to this script: $Adb"
    }
}

function Require-Fastboot {
    if (-not (Test-Path -LiteralPath $Fastboot)) {
        throw "fastboot.exe not found next to this script: $Fastboot"
    }
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $Adb @Args
}

function Invoke-Fastboot {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $Fastboot @Args
}

function New-UniqueStampedDirectory {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    for ($i = 1; $i -le 999; $i++) {
        $name = if ($i -eq 1) { $stamp } else { "{0}-{1:D3}" -f $stamp, $i }
        $dir = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
            return $dir
        }
    }
    throw "Could not create unique directory in: $Root"
}

function New-UniqueStampedFile {
    param(
        [string]$Root,
        [string]$Prefix,
        [string]$Extension
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    for ($i = 1; $i -le 999; $i++) {
        $suffix = if ($i -eq 1) { '' } else { "-{0:D3}" -f $i }
        $file = Join-Path $Root ("{0}{1}{2}{3}" -f $Prefix, $stamp, $suffix, $Extension)
        if (-not (Test-Path -LiteralPath $file)) {
            return $file
        }
    }
    throw "Could not create unique file in: $Root"
}

function Test-Device {
    Require-Adb
    $devices = Invoke-Adb devices -l
    $deviceLines = @($devices | Where-Object { $_ -match '\sdevice(\s|$)' -and $_ -notmatch '^List of devices' })
    if ($deviceLines.Count -lt 1) {
        Write-Host $devices
        throw "No authorized ADB device found. Check USB debugging authorization."
    }
    if ($deviceLines.Count -gt 1) {
        Write-Host $devices
        throw "More than one ADB device found. Connect only one device."
    }
    Write-Host $deviceLines[0]
}

function New-Backup {
    Test-Device
    $dir = New-UniqueStampedDirectory $BackupRoot

    Write-Title "Backup"
    Write-Host "Writing backup to: $dir"
    Invoke-Adb devices -l | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'devices.txt')
    Invoke-Adb shell getprop | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'getprop.txt')
    Invoke-Adb shell settings list global | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'settings-global.txt')
    Invoke-Adb shell settings list secure | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'settings-secure.txt')
    Invoke-Adb shell settings list system | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'settings-system.txt')
    Invoke-Adb shell pm list packages | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'packages-all.txt')
    Invoke-Adb shell pm list packages -d | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'packages-disabled.txt')
    Invoke-Adb shell dumpsys battery | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'battery.txt')
    return $dir
}

function Backup-BeforeChange {
    New-Backup | Out-Null
}

function Export-SettingsSnapshot {
    Test-Device
    $root = Join-Path $BaseDir 'settings-snapshots'
    $dir = New-UniqueStampedDirectory $root

    Write-Title "Export settings"
    Write-Host "Writing settings snapshot to: $dir"
    Invoke-Adb shell settings list global | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'adb shell settings list global.txt')
    Invoke-Adb shell settings list system | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'adb shell settings list system.txt')
    Invoke-Adb shell settings list secure | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'adb shell settings list secure.txt')
    Invoke-Adb shell getprop | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'adb shell getprop.txt')
    Invoke-Adb shell pm list packages -d | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'adb shell pm list packages -d.txt')
    Write-Host "Done."
}

function Split-CommandLine {
    param([string]$Line)
    $matches = [regex]::Matches($Line, '("[^"]*"|''[^'']*''|\S+)')
    $args = @()
    foreach ($m in $matches) {
        $v = $m.Value
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $args += $v
    }
    return $args
}

function Invoke-UserCommandLine {
    param([string]$Line)
    $args = @(Split-CommandLine $Line)
    if ($args.Count -eq 0) {
        return
    }

    if ($args[0] -ieq 'adb') {
        $args = @($args | Select-Object -Skip 1)
    }

    if ($args.Count -eq 0) {
        return
    }

    $first = $args[0].ToLowerInvariant()
    if ($first -eq 'shell') {
        if ($args.Count -lt 2) {
            throw "Unsupported shell command: $Line"
        }
        $shellCmd = $args[1].ToLowerInvariant()
        if ($shellCmd -notin @('settings', 'pm', 'cmd', 'content', 'am', 'input', 'svc')) {
            throw "Blocked shell command: $Line"
        }
        Invoke-Adb @args
        return
    }

    if ($first -in @('settings', 'pm', 'cmd', 'content', 'am', 'input', 'svc')) {
        Invoke-Adb shell @args
        return
    }

    if ($first -in @('install', 'uninstall', 'push', 'pull', 'reboot')) {
        Invoke-Adb @args
        return
    }

    throw "Unsupported command: $Line"
}

function Apply-CommandsFromTxt {
    Test-Device
    $cmdDir = Join-Path $BaseDir 'commands'
    New-Item -ItemType Directory -Force -Path $cmdDir | Out-Null
    $files = @(Get-ChildItem -LiteralPath $cmdDir -Filter '*.txt' -File -ErrorAction SilentlyContinue | Sort-Object Name)

    Write-Title "Apply commands from txt"
    if ($files.Count -eq 0) {
        Write-Host "No .txt command files found in: $cmdDir"
        Write-Host "Put a .txt file there and run this menu item again."
        Write-Host "Allowed examples:"
        Write-Host "  adb shell settings put global window_animation_scale 0"
        Write-Host "  settings put system screen_off_timeout 300000"
        Write-Host "  pm disable-user --user 0 com.android.nfc"
        return
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host "$($i + 1). $($files[$i].Name)"
    }
    $choice = Read-Host "Choose txt file number"
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $files.Count) {
        throw "Invalid file selection."
    }

    $file = $files[$n - 1].FullName
    Write-Host "Selected: $file"
    $confirm = Read-Host "Type APPLY to run commands from this file"
    if ($confirm -ne 'APPLY') {
        Write-Host "Cancelled."
        return
    }

    Backup-BeforeChange
    $logRoot = Join-Path $BaseDir 'command-logs'
    $logFile = New-UniqueStampedFile $logRoot 'commands-' '.log'

    $lines = Get-Content -LiteralPath $file -Encoding UTF8
    $lineNo = 0
    foreach ($line in $lines) {
        $lineNo++
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('//')) {
            continue
        }

        Write-Host "[$lineNo] $trimmed"
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value "[$lineNo] $trimmed"
        try {
            $out = Invoke-UserCommandLine $trimmed 2>&1
            if ($out) {
                $out | Tee-Object -FilePath $logFile -Append
            }
        } catch {
            $msg = "ERROR line ${lineNo}: $($_.Exception.Message)"
            Write-Host $msg -ForegroundColor Red
            Add-Content -LiteralPath $logFile -Encoding UTF8 -Value $msg
            throw
        }
    }

    Write-Host "Done. Log: $logFile"
}

function Get-BackupDirectory {
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        throw "No backups folder found: $BackupRoot"
    }
    $backups = @(Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        throw "No backups found in: $BackupRoot"
    }

    Write-Title "Available backups"
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "$($i + 1). $($backups[$i].Name)"
    }
    $choice = Read-Host "Choose backup number"
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $backups.Count) {
        throw "Invalid backup selection."
    }
    return $backups[$n - 1].FullName
}

function Restore-SettingsNamespace {
    param(
        [string]$BackupDir,
        [string]$Namespace,
        [string]$FileName
    )
    $file = Join-Path $BackupDir $FileName
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Host "Skip missing file: $file"
        return
    }

    Write-Title "Restore settings $Namespace"
    $lines = Get-Content -LiteralPath $file -Encoding UTF8
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '=') {
            continue
        }
        $parts = $line.Split('=', 2)
        $key = $parts[0]
        $value = $parts[1]
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        Write-Host "$Namespace $key=$value"
        Invoke-Adb shell settings put $Namespace $key $value | Out-Null
    }
}

function Restore-PackagesFromBackup {
    param([string]$BackupDir)
    $disabledFile = Join-Path $BackupDir 'packages-disabled.txt'
    if (-not (Test-Path -LiteralPath $disabledFile)) {
        Write-Host "Skip package restore, missing: $disabledFile"
        return
    }

    Write-Title "Restore disabled package state"
    $backupDisabled = @(Get-Content -LiteralPath $disabledFile -Encoding UTF8 |
        Where-Object { $_ -match '^package:' } |
        ForEach-Object { $_ -replace '^package:', '' })

    $currentDisabled = @(Invoke-Adb shell pm list packages -d |
        Where-Object { $_ -match '^package:' } |
        ForEach-Object { $_ -replace '^package:', '' })

    foreach ($pkg in $currentDisabled) {
        if ($backupDisabled -notcontains $pkg) {
            Write-Host "Enable $pkg"
            Invoke-Adb shell pm enable --user 0 $pkg | Out-Null
        }
    }

    foreach ($pkg in $backupDisabled) {
        Write-Host "Disable $pkg"
        Invoke-Adb shell pm disable-user --user 0 $pkg | Out-Null
    }
}

function Restore-FromBackup {
    Test-Device
    $backupDir = Get-BackupDirectory
    Write-Host "Selected backup: $backupDir"
    $confirm = Read-Host "Type RESTORE to restore settings and disabled packages"
    if ($confirm -ne 'RESTORE') {
        Write-Host "Restore cancelled."
        return
    }

    Backup-BeforeChange
    Restore-PackagesFromBackup $backupDir
    Restore-SettingsNamespace $backupDir 'global' 'settings-global.txt'
    Restore-SettingsNamespace $backupDir 'secure' 'settings-secure.txt'
    Restore-SettingsNamespace $backupDir 'system' 'settings-system.txt'
    Write-Host "Restore finished. Reboot is recommended."
}

$BeamPackages = @(
    'acr.browser.barebones',
    'com.android.backupconfirm',
    'com.android.bips',
    'com.android.bookmarkprovider',
    'com.android.calculator2',
    'com.android.calendar',
    'com.android.camera2',
    'com.android.captiveportallogin',
    'com.android.companiondevicemanager',
    'com.android.cts.ctsshim',
    'com.android.cts.priv.ctsshim',
    'com.android.deskclock',
    'com.android.dreams.basic',
    'com.android.egg',
    'com.android.gallery3d',
    'com.android.hotspot2.osulogin',
    'com.android.internal.display.cutout.emulation.hole',
    'com.android.internal.display.cutout.emulation.tall',
    'com.android.internal.display.cutout.emulation.waterfall',
    'com.android.internal.systemui.navbar.gestural',
    'com.android.internal.systemui.navbar.gestural_extra_wide_back',
    'com.android.internal.systemui.navbar.gestural_narrow_back',
    'com.android.internal.systemui.navbar.gestural_wide_back',
    'com.android.internal.systemui.navbar.threebutton',
    'com.android.keychain',
    'com.android.managedprovisioning',
    'com.android.mms.service',
    'com.android.music',
    'com.android.musicfx',
    'com.android.nfc',
    'com.android.onetimeinitializer',
    'com.android.providers.blockednumber',
    'com.android.providers.calendar',
    'com.android.providers.contacts',
    'com.android.providers.userdictionary',
    'com.android.quicksearchbox',
    'com.android.rk',
    'com.android.simappdialog',
    'com.android.soundrecorder',
    'com.android.statementservice',
    'com.android.theme.color.amethyst',
    'com.android.theme.color.aquamarine',
    'com.android.theme.color.carbon',
    'com.android.theme.color.cinnamon',
    'com.android.theme.color.green',
    'com.android.theme.color.ocean',
    'com.android.theme.color.orchid',
    'com.android.theme.color.purple',
    'com.android.theme.color.sand',
    'com.android.theme.color.space',
    'com.android.theme.color.tangerine',
    'com.android.theme.icon.pebble',
    'com.android.theme.icon.roundedrect',
    'com.android.theme.icon.squircle',
    'com.android.theme.icon.taperedrect',
    'com.android.theme.icon.teardrop',
    'com.android.theme.icon.vessel',
    'com.android.theme.icon_pack.circular.android',
    'com.android.theme.icon_pack.circular.launcher',
    'com.android.theme.icon_pack.circular.settings',
    'com.android.theme.icon_pack.circular.systemui',
    'com.android.theme.icon_pack.circular.themepicker',
    'com.android.theme.icon_pack.filled.android',
    'com.android.theme.icon_pack.filled.launcher',
    'com.android.theme.icon_pack.filled.settings',
    'com.android.theme.icon_pack.filled.systemui',
    'com.android.theme.icon_pack.filled.themepicker',
    'com.android.theme.icon_pack.kai.android',
    'com.android.theme.icon_pack.kai.launcher',
    'com.android.theme.icon_pack.kai.settings',
    'com.android.theme.icon_pack.kai.systemui',
    'com.android.theme.icon_pack.kai.themepicker',
    'com.android.theme.icon_pack.rounded.android',
    'com.android.theme.icon_pack.rounded.launcher',
    'com.android.theme.icon_pack.rounded.settings',
    'com.android.theme.icon_pack.rounded.systemui',
    'com.android.theme.icon_pack.rounded.themepicker',
    'com.android.theme.icon_pack.sam.android',
    'com.android.theme.icon_pack.sam.launcher',
    'com.android.theme.icon_pack.sam.settings',
    'com.android.theme.icon_pack.sam.systemui',
    'com.android.theme.icon_pack.sam.themepicker',
    'com.android.theme.icon_pack.victor.android',
    'com.android.theme.icon_pack.victor.launcher',
    'com.android.theme.icon_pack.victor.settings',
    'com.android.theme.icon_pack.victor.systemui',
    'com.android.theme.icon_pack.victor.themepicker',
    'com.android.traceur',
    'com.android.wallpaperbackup',
    'com.android.wallpapercropper',
    'com.android.wallpaperpicker',
    'com.google.android.inputmethod.japanese',
    'com.google.android.inputmethod.korean',
    'com.google.android.inputmethod.pinyin'
)

$SettingBlocks = [ordered]@{
    'RK3566' = @(
        @('settings','put','global','persist.sys.rk.audio_latency','1'),
        @('settings','put','global','persist.rk.video.decode.freq','1800000'),
        @('settings','put','global','persist.rk.ddr.freq','1056000')
    )
    'GPU' = @(
        @('settings','put','global','debug.egl.hw','1'),
        @('settings','put','global','debug.sf.hw','1'),
        @('settings','put','global','debug.gralloc.enable_fb_ubwc','1'),
        @('settings','put','global','force_gpu_rendering','1')
    )
    'RAM' = @(
        @('settings','put','global','sys.sysctl.extra_free_kbytes','24300'),
        @('settings','put','global','sys.sysctl.min_free_kbytes','4096'),
        @('settings','put','global','sys.sysctl.vm_compaction_priority','1'),
        @('settings','put','global','cached_apps_freezer','enabled'),
        @('settings','put','global','activity_manager_constants','max_cached_processes=1')
    )
    'Media' = @(
        @('settings','put','global','persist.sys.media.avsync','1'),
        @('settings','put','global','sys.use_fifo_ui','1'),
        @('settings','put','global','debug.sf.disable_hwc_overlays','1'),
        @('settings','put','global','media_transcoding_cache_enabled','1'),
        @('settings','put','global','persist.vendor.sys.media.buffering','1'),
        @('settings','put','global','persist.debug.media.codec.bufferqueuesize','1024'),
        @('settings','put','global','media.stagefright.max-frame-buffer-count','4')
    )
    'Thermal' = @(
        @('settings','put','global','persist.sys.thermal.debug','1'),
        @('settings','put','global','persist.vendor.sys.thermal.config','aggressive'),
        @('settings','put','global','persist.sys.cpu.boost_duration','2000'),
        @('settings','put','global','adaptive_thermal_enabled','0'),
        @('settings','put','global','persist.thermal.config.forced_throttling','0')
    )
    'WiFi' = @(
        @('settings','put','global','wifi_verbose_logging','0'),
        @('settings','put','global','wifi_display_certification_on','1'),
        @('settings','put','global','wifi_power_save','0'),
        @('settings','put','global','wifi_scan_always_enabled','0')
    )
    'Power' = @(
        @('settings','put','global','aggressive_battery_saver','0'),
        @('settings','put','global','charging_control_enabled','1'),
        @('settings','put','global','charging_control_limit','85'),
        @('settings','put','global','low_power','1'),
        @('settings','put','global','low_power_sticky','1')
    )
    'Animations' = @(
        @('settings','put','global','window_animation_scale','0'),
        @('settings','put','global','transition_animation_scale','0'),
        @('settings','put','global','animator_duration_scale','0')
    )
    'Cleanup' = @(
        @('pm','trim-caches','999999999'),
        @('settings','put','global','background_process_limit','1'),
        @('settings','put','global','auto_update_apk','0'),
        @('content','insert','--uri','content://settings/global','--bind','name:s:auto_sync','--bind','value:i:0')
    )
}

$ExtraOptimBlocks = [ordered]@{
    'CPU' = @(
        @('settings','put','global','persist.vendor.rk.cpu.mode','balanced'),
        @('settings','put','global','persist.vendor.rk.cpu.idle','true')
    )
    'ThermalQuiet' = @(
        @('settings','put','global','persist.sys.thermal.polling_speed','low_power'),
        @('settings','put','global','persist.sys.thermal.temp_threshold','45'),
        @('settings','put','global','persist.sys.thermal.fan_mode','quiet')
    )
    'GPUBalanced' = @(
        @('settings','put','global','persist.vendor.gpu.mode','balanced'),
        @('settings','put','global','sys.use_mali_async_pipeline','0')
    )
    'Streaming' = @(
        @('settings','put','global','persist.vendor.rk.video.mode','streaming'),
        @('settings','put','global','persist.vendor.rk.video.quality','medium'),
        @('settings','put','global','persist.vendor.rk.video.latency','medium'),
        @('settings','put','global','persist.vendor.video.buffer.size','65536'),
        @('settings','put','global','debug.stagefright.use-hw-decoder','1'),
        @('settings','put','global','persist.sys.media.stagefright.hwaccel','1')
    )
    'WiFiPowerSave' = @(
        @('settings','put','global','wifi_power_save','1'),
        @('settings','put','global','wifi_scan_always_enabled','0'),
        @('settings','put','global','persist.vendor.wifi.rssi.level','medium'),
        @('settings','put','global','persist.vendor.wifi.buffer.size','8192'),
        @('settings','put','global','net.tcp.buffersize.wifi','524288,2097152,4194304,524288,2097152,4194304')
    )
    'BackgroundLimit3' = @(
        @('settings','put','global','background_process_limit','3'),
        @('settings','put','global','auto_update_apk','0')
    )
    'AnimationsOff' = @(
        @('settings','put','global','window_animation_scale','0'),
        @('settings','put','global','transition_animation_scale','0'),
        @('settings','put','global','animator_duration_scale','0')
    )
    'SensorsLowPower' = @(
        @('settings','put','global','persist.sys.sensor.rate','low_power')
    )
}

function Disable-BeamPackages {
    Backup-BeforeChange
    Write-Title "Disable packages from beam-app.sh"
    $i = 0
    foreach ($pkg in $BeamPackages) {
        $i++
        Write-Host "[$i/$($BeamPackages.Count)] $pkg"
        Invoke-Adb shell pm disable-user --user 0 $pkg
    }
    $count = @(Invoke-Adb shell pm list packages -d).Count
    Write-Host "Disabled packages count: $count"
}

function Apply-SettingBlock {
    param([string]$Name)
    Write-Title "Apply settings block: $Name"
    $commands = [System.Collections.ArrayList]::new()
    $block = $SettingBlocks[$Name]
    if ($block -is [array] -and $block.Count -gt 0 -and $block[0] -is [string]) {
        [void]$commands.Add($block)
    } else {
        foreach ($item in $block) {
            [void]$commands.Add($item)
        }
    }
    foreach ($cmd in $commands) {
        Write-Host ($cmd -join ' ')
        Invoke-Adb shell @cmd
    }
}

function Apply-AllSettings {
    Backup-BeforeChange
    foreach ($name in $SettingBlocks.Keys) {
        Apply-SettingBlock $name
    }
}

function Apply-ExtraOptimPreset {
    param([bool]$RebootAfter = $true)
    Backup-BeforeChange
    Write-Title "Apply extra_optim.sh preset"
    foreach ($name in $ExtraOptimBlocks.Keys) {
        Write-Title "extra_optim block: $name"
        $commands = [System.Collections.ArrayList]::new()
        $block = $ExtraOptimBlocks[$name]
        if ($block -is [array] -and $block.Count -gt 0 -and $block[0] -is [string]) {
            [void]$commands.Add($block)
        } else {
            foreach ($item in $block) {
                [void]$commands.Add($item)
            }
        }
        foreach ($cmd in $commands) {
            Write-Host ($cmd -join ' ')
            Invoke-Adb shell @cmd
        }
    }
    if ($RebootAfter) {
        $answer = Read-Host "extra_optim.sh reboots at the end. Reboot now? [Y/N]"
        if ($answer -match '^[Yy]$') {
            Invoke-Adb reboot
        }
    }
}

function Install-Apks {
    Backup-BeforeChange
    Write-Title "Install APK files from app"
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $apks = @(Get-ChildItem -LiteralPath $AppDir -Filter '*.apk' -File -ErrorAction SilentlyContinue)
    if ($apks.Count -eq 0) {
        Write-Host "No APK files found in: $AppDir"
        return
    }
    $i = 0
    foreach ($apk in $apks) {
        $i++
        Write-Host "[$i/$($apks.Count)] Installing $($apk.Name)"
        Invoke-Adb install -r -d $apk.FullName
    }
}

function Verify-Status {
    Write-Title "Status"
    Test-Device
    Write-Host "Model:"
    Invoke-Adb shell getprop ro.product.model
    Write-Host "Build:"
    Invoke-Adb shell getprop ro.build.display.id
    Write-Host "Disabled package count:"
    @(Invoke-Adb shell pm list packages -d).Count
    Write-Host "Battery:"
    Invoke-Adb shell dumpsys battery | Select-String -Pattern 'level|temperature|USB powered|status'
}

function Factory-Reset-Fastboot {
    Require-Adb
    Require-Fastboot
    Test-Device

    Write-Title "Factory reset"
    Write-Host "This will erase userdata and cache via fastboot."
    Write-Host "Installed apps, app data, local files, and device settings may be deleted."
    Write-Host "A backup of ADB-readable state will be created first, but it is not a full data backup."
    $confirm = Read-Host "Type RESET to continue"
    if ($confirm -ne 'RESET') {
        Write-Host "Factory reset cancelled."
        return
    }

    Backup-BeforeChange
    Write-Host "Rebooting to bootloader..."
    Invoke-Adb reboot bootloader
    Start-Sleep -Seconds 5

    Write-Host "Waiting for fastboot..."
    $deadline = (Get-Date).AddMinutes(2)
    do {
        $devices = @(Invoke-Fastboot devices)
        if ($devices.Count -gt 0 -and ($devices -join "`n") -match '\S+') {
            Write-Host ($devices -join "`n")
            break
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    $devices = @(Invoke-Fastboot devices)
    if ($devices.Count -eq 0 -or (($devices -join "`n") -notmatch '\S+')) {
        throw "No fastboot device found. The device may not support fastboot mode or drivers are missing."
    }

    Write-Host "Erasing userdata..."
    Invoke-Fastboot erase userdata
    Write-Host "Erasing cache..."
    Invoke-Fastboot erase cache
    Write-Host "Rebooting..."
    Invoke-Fastboot reboot
}

function Full-Run {
    Backup-BeforeChange
    Write-Title "Full run: disable packages"
    foreach ($pkg in $BeamPackages) {
        Write-Host $pkg
        Invoke-Adb shell pm disable-user --user 0 $pkg
    }
    Write-Title "Full run: settings"
    foreach ($name in $SettingBlocks.Keys) {
        Apply-SettingBlock $name
    }
    Write-Title "Full run: install APKs"
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $apks = @(Get-ChildItem -LiteralPath $AppDir -Filter '*.apk' -File -ErrorAction SilentlyContinue)
    foreach ($apk in $apks) {
        Write-Host "Installing $($apk.Name)"
        Invoke-Adb install -r -d $apk.FullName
    }
    Verify-Status
}

while ($true) {
    try {
        Write-Title "XREAL Beam ADB Tool"
        Write-Host "1. Check device"
        Write-Host "2. Backup only"
        Write-Host "3. Export settings snapshot"
        Write-Host "4. Apply commands from txt"
        Write-Host "5. Apply beam-app"
        Write-Host "6. Apply beam-settings"
        Write-Host "7. Apply extra_optim"
        Write-Host "8. Install APKs from app folder"
        Write-Host "9. Full run: backup + beam-app + beam-settings + APK install"
        Write-Host "10. Restore from backup"
        Write-Host "11. Reboot device"
        Write-Host "12. Factory reset via fastboot"
        Write-Host "13. Status"
        Write-Host "0. Exit"
        $choice = Read-Host "Choose"

        switch ($choice) {
            '1' { Test-Device }
            '2' { New-Backup | Out-Null }
            '3' { Export-SettingsSnapshot }
            '4' { Apply-CommandsFromTxt }
            '5' { Disable-BeamPackages }
            '6' { Apply-AllSettings }
            '7' { Apply-ExtraOptimPreset $true }
            '8' { Install-Apks }
            '9' { Full-Run }
            '10' { Restore-FromBackup }
            '11' { Backup-BeforeChange; Invoke-Adb reboot }
            '12' { Factory-Reset-Fastboot }
            '13' { Verify-Status }
            '0' { exit 0 }
            default { Write-Host "Unknown choice." }
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
