# QuadCast 2 Auto Mute

Automatically hardware-mute a HyperX QuadCast 2 when it connects to Windows. This is useful when a KVM switch disconnects and reconnects the microphone: Windows mutes it after reconnecting, and one tap on the microphone's top sensor unmutes it. The watcher sends the mute command once per connection, so it does not re-mute the microphone after you tap it.

Tested with a QuadCast 2 exposing `VID_03F0&PID_07B4&MI_02&Col04` on Windows. The script uses the microphone's HID output report (`77 06 01`) rather than Windows' software microphone mute. It does not support the QuadCast 2 S or other models as written.

## Install

1. Download the repository as a ZIP and extract it to any folder, or clone it.
2. Double-click `Install.cmd`. No administrator rights or PowerShell 7 installation are required.
3. The installer copies the script to `%LOCALAPPDATA%\QuadCast2AutoMute`, starts the watcher immediately, and registers it to start when you sign in to Windows.
4. Switch the KVM away and back. The microphone should be muted. Tap its top sensor once to unmute it.

The watcher logs connection and mute events to `%LOCALAPPDATA%\QuadCast2AutoMute\QuadCast2AutoMute.log`.

PowerShell script execution must be allowed by the Windows policy on the computer. The installer and watcher do not override that policy.

## Uninstall

Run `Uninstall.cmd` from the extracted repository folder. It stops the watcher, removes the sign-in entry, and deletes the installed script and log.

## Manual commands

From the repository folder, you can run a one-time hardware mute without installing the watcher:

```powershell
powershell.exe -NoProfile -File .\QuadCast2AutoMute.ps1 -Mode Once
```

The microphone must be connected for this command. `Install.cmd` works even if it is disconnected; the watcher waits for it.

## Limitations

The microphone powers up unmuted. Software can send the mute command only after Windows has enumerated its USB HID interface, so a brief unmuted interval after a KVM switch is possible. This is not a fail-closed privacy switch. The watcher runs separately on each Windows PC where it is installed.

## Security review

The installer copies the script to the current user's `%LOCALAPPDATA%\QuadCast2AutoMute` folder, adds a `QuadCast2AutoMute` entry under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, and starts a background PowerShell watcher. The watcher loads the included C# HID interop code, checks for the matching QuadCast 2 USB interface, and sends its hardware-mute report once per connection. It writes a local log. It does not need administrator rights or make network requests.

On a computer managed by an organization, endpoint protection may still flag this behavior. Ask the security administrator to review the exact Falcon detection and this source code before approving its use; do not disable protection or add a broad exclusion. A public sandbox scan cannot reproduce every detection from the local Falcon sensor and policy.

The implementation uses [Windows' HID output-report API](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/hidsdi/nf-hidsdi-hidd_setoutputreport). Protocol research is documented in the [OpenHyperX QuadCast notes](https://github.com/chase-irql/OpenHyperX/blob/main/quadcast/hyperx_quadcast.md).
