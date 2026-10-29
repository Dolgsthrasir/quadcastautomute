param(
    [ValidateSet('Watch', 'Once', 'Install', 'Uninstall')]
    [string]$Mode = 'Watch'
)

$ErrorActionPreference = 'Stop'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'QuadCast2AutoMute'
$stopEventName = 'Local\QuadCast2AutoMuteStop'

function Stop-CurrentWatcher {
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting($stopEventName)
        try { [void]$event.Set() } finally { $event.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] {
        # No watcher is running.
    }

    $mutex = [Threading.Mutex]::new($false, 'Local\QuadCast2AutoMute')
    try {
        try {
            $stopped = $mutex.WaitOne(5000)
        } catch [Threading.AbandonedMutexException] {
            $stopped = $true
        }
        if (-not $stopped) {
            throw 'The existing watcher did not stop within five seconds.'
        }
        $mutex.ReleaseMutex()
    } finally {
        $mutex.Dispose()
    }
}

if ($Mode -eq 'Install') {
    $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $powershell = Join-Path $PSHOME $exeName
    $arguments = '-NoProfile -WindowStyle Hidden -File "{0}" -Mode Watch' -f $PSCommandPath
    $command = '"{0}" {1}' -f $powershell, $arguments
    Stop-CurrentWatcher
    New-ItemProperty -Path $runKey -Name $runName -Value $command -PropertyType String -Force | Out-Null
    Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden
    Write-Output "Installed and started. Autostart command: $command"
    return
}
if ($Mode -eq 'Uninstall') {
    Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
    Stop-CurrentWatcher
    Write-Output 'Autostart removed; watcher stopped.'
    return
}

if (-not ('QuadCast2Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class QuadCast2Native {
    private static readonly Guid HidGuid = new Guid("4d1e55b2-f16f-11cf-88cb-001111000030");
    private const uint AccessReadWrite = 0xC0000000;
    private const uint ShareReadWrite = 3;

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    private static extern int CM_Get_Device_Interface_List_SizeW(out uint size, ref Guid classGuid, IntPtr deviceId, uint flags);

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    private static extern int CM_Get_Device_Interface_ListW(ref Guid classGuid, IntPtr deviceId, [Out] char[] buffer, uint size, uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetOutputReport(IntPtr handle, byte[] report, uint length);

    public static string[] CurrentMicrophones() {
        for (int attempt = 0; attempt < 3; attempt++) {
            Guid guid = HidGuid;
            uint size;
            int result = CM_Get_Device_Interface_List_SizeW(out size, ref guid, IntPtr.Zero, 0);
            if (result != 0) { throw new Exception("HID interface size query failed: " + result); }
            char[] buffer = new char[size];
            result = CM_Get_Device_Interface_ListW(ref guid, IntPtr.Zero, buffer, size, 0);
            if (result == 0) {
                var paths = new List<string>();
                string all = new string(buffer);
                foreach (string path in all.Split(new char[] { '\0' }, StringSplitOptions.RemoveEmptyEntries)) {
                    if (path.IndexOf("VID_03F0&PID_07B4&MI_02&Col04", StringComparison.OrdinalIgnoreCase) >= 0) {
                        paths.Add(path);
                    }
                }
                return paths.ToArray();
            }
            if (result != 0x1A) { throw new Exception("HID interface list query failed: " + result); }
        }
        throw new Exception("HID interface list changed repeatedly.");
    }

    public static void Mute(string path) {
        IntPtr handle = CreateFile(path, AccessReadWrite, ShareReadWrite, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (handle == new IntPtr(-1)) {
            throw new Exception("Opening QuadCast 2 failed: " + Marshal.GetLastWin32Error());
        }
        try {
            // Report 0x77, command 0x06, absolute mute state 0x01.
            byte[] report = new byte[64];
            report[0] = 0x77;
            report[1] = 0x06;
            report[2] = 0x01;
            if (!HidD_SetOutputReport(handle, report, (uint)report.Length)) {
                throw new Exception("Hardware mute failed: " + Marshal.GetLastWin32Error());
            }
        } finally {
            CloseHandle(handle);
        }
    }
}
'@
}

if ($Mode -eq 'Once') {
    $paths = [QuadCast2Native]::CurrentMicrophones()
    if ($paths.Count -eq 0) { throw 'QuadCast 2 is not connected.' }
    foreach ($path in $paths) { [QuadCast2Native]::Mute($path) }
    Write-Output 'QuadCast 2 hardware mute applied.'
    return
}

$mutex = [Threading.Mutex]::new($false, 'Local\QuadCast2AutoMute')
try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { $mutex.Dispose(); return }
$stopEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, $stopEventName)
$logPath = Join-Path $PSScriptRoot 'QuadCast2AutoMute.log'
function Write-MuteLog([string]$message) {
    Add-Content -LiteralPath $logPath -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $message)
}

try {
    Write-MuteLog 'Watcher started.'
    $lastPath = $null
    $mutedThisConnection = $false
    $lastErrorLog = [datetime]::MinValue
    while ($true) {
        try {
            $paths = [QuadCast2Native]::CurrentMicrophones()
            $path = if ($paths.Count -gt 0) { $paths[0] } else { $null }
            if ($path -ne $lastPath) {
                $lastPath = $path
                $mutedThisConnection = $false
                $lastErrorLog = [datetime]::MinValue
                if ($null -eq $path) { Write-MuteLog 'Microphone disconnected.' }
            }
            if ($null -ne $path -and -not $mutedThisConnection) {
                try {
                    [QuadCast2Native]::Mute($path)
                    $mutedThisConnection = $true
                    Write-MuteLog 'Hardware mute applied.'
                } catch {
                    if ((Get-Date) - $lastErrorLog -ge [timespan]::FromMinutes(1)) {
                        Write-MuteLog ("Mute attempt failed: {0}" -f $_.Exception.Message)
                        $lastErrorLog = Get-Date
                    }
                }
            }
        } catch {
            if ((Get-Date) - $lastErrorLog -ge [timespan]::FromMinutes(1)) {
                Write-MuteLog ("Device lookup failed: {0}" -f $_.Exception.Message)
                $lastErrorLog = Get-Date
            }
        }
        if ($stopEvent.WaitOne(250)) { break }
    }
    Write-MuteLog 'Watcher stopped.'
} finally {
    $stopEvent.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
