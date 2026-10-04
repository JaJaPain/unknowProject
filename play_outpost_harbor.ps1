$projectPath = $PSScriptRoot
$logDirectory = Join-Path $projectPath ".tmp_godot_user/test_logs"
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$testLog = Join-Path $logDirectory ("outpost_play_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
& (Join-Path $projectPath "Godot/Godot_v4.6.3-stable_win64_console.exe") --path $projectPath res://scenes/tests/outpost_harbor/outpost_harbor.tscn --log-file $testLog -- --baseline-offline
