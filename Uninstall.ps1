$ErrorActionPreference = 'Stop'

$installDirectory = Join-Path $env:LOCALAPPDATA 'QuadCast2AutoMute'
$installedScript = Join-Path $installDirectory 'QuadCast2AutoMute.ps1'
$logPath = Join-Path $installDirectory 'QuadCast2AutoMute.log'

if (Test-Path -LiteralPath $installedScript) {
    & $installedScript -Mode Uninstall
} else {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'QuadCast2AutoMute' -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 500
Remove-Item -LiteralPath $installedScript, $logPath -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -ErrorAction SilentlyContinue
}
Write-Output 'QuadCast 2 Auto Mute uninstalled.'
