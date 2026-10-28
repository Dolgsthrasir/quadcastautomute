$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'QuadCast2AutoMute.ps1'
if (-not (Test-Path -LiteralPath $source)) {
    throw 'QuadCast2AutoMute.ps1 is missing from the installer folder.'
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'QuadCast2AutoMute'
$installedScript = Join-Path $installDirectory 'QuadCast2AutoMute.ps1'
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

if (-not [string]::Equals([IO.Path]::GetFullPath($source), [IO.Path]::GetFullPath($installedScript), [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $source -Destination $installedScript -Force
}

& $installedScript -Mode Install

Write-Output "Installed at $installedScript"
