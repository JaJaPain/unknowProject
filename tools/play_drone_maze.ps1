# Opens the drone maze practice scene (no campaign needed).
#   powershell -File tools/play_drone_maze.ps1
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Godot\Godot_v4.6.3-stable_win64.exe"
if (-not (Test-Path $godot)) { $godot = Join-Path $root "Godot\Godot_v4.6.3-stable_win64_console.exe" }
$logs = Join-Path $root ".tmp_godot_user\test_logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
& $godot --path $root --log-file (Join-Path $logs "drone_maze_practice.log") res://tools/drone_maze_practice.tscn
