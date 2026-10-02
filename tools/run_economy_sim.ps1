# Runs tools/economy_sim.gd for several scenarios and seeds (one Godot at a
# time, each with its own log) and prints the average minutes per rung.
#   powershell -File tools/run_economy_sim.ps1
param([int]$Seeds = 4)
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Godot\Godot_v4.6.3-stable_win64_console.exe"
$logs = Join-Path $root ".tmp_godot_user\test_logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$scenarios = [ordered]@{
  "current_numbers"            = @()
  "old_board_pay"              = @("--job-mult=0.5")
  "drone_400"                  = @("--drone-price=400")
}
$rows = @{}
foreach ($name in $scenarios.Keys) {
  for ($s = 1; $s -le $Seeds; $s++) {
    $log = Join-Path $logs "esim_${name}_$s.log"
    $args = @("--headless", "--path", $root, "--script", "res://tools/economy_sim.gd", "--log-file", $log, "--", "--label=$name", "--seed=$s") + $scenarios[$name]
    $p = Start-Process -FilePath $godot -ArgumentList $args -NoNewWindow -PassThru
    if (-not $p.WaitForExit(180000)) { $p.Kill(); Write-Host "$name seed $s TIMED OUT"; continue }
    $line = Select-String -Path $log -Pattern "^SIMROW " | Select-Object -First 1
    if ($line) { $rows["$name|$s"] = ($line.Line -split "\|")[2] }
  }
}
Write-Host ""
Write-Host ("{0,-30} {1,8} {2,8} {3,8} {4,8} {5,8}" -f "scenario (avg min per rung)", "II", "III", "IV", "V", "VI")
Write-Host ("{0,-30} {1,8} {2,8} {3,8} {4,8} {5,8}" -f "target", "20-30", "30-40", "45-60", "120-240", "240-480")
foreach ($name in $scenarios.Keys) {
  $cols = @()
  for ($c = 0; $c -lt 5; $c++) {
    $vals = @()
    for ($s = 1; $s -le $Seeds; $s++) {
      $r = $rows["$name|$s"]
      if ($r) { $v = ($r -split ",")[$c]; if ($v -ne "-") { $vals += [double]$v } }
    }
    if ($vals.Count -eq $Seeds) { $cols += [math]::Round(($vals | Measure-Object -Average).Average) } elseif ($vals.Count -gt 0) { $cols += "$([math]::Round(($vals | Measure-Object -Average).Average))*" } else { $cols += "never" }
  }
  Write-Host ("{0,-30} {1,8} {2,8} {3,8} {4,8} {5,8}" -f $name, $cols[0], $cols[1], $cols[2], $cols[3], $cols[4])
}
Write-Host "(* = some seeds never reached it within 40 simulated hours)"
