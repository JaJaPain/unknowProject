$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Godot\Godot_v4.3-stable_win64_console.exe"
$testData = Join-Path $root ".godot\baseline_user_data"

$env:APPDATA = $testData
$env:LOCALAPPDATA = $testData

Write-Host "Launching Godot editor to scan project and build class cache..."
$proc = Start-Process -FilePath $godot -ArgumentList "--headless", "--editor", "--path", $root -PassThru
Start-Sleep -Seconds 7
if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
}
Write-Host "Godot editor scan complete."
