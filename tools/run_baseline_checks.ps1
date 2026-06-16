param(
    [switch]$KeepLogs
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$godotCandidates = @(
    (Join-Path $root "Godot\Godot_v4.6.3-stable_win64_console.exe"),
    (Join-Path $root "Godot\Godot_v4.6.3-stable_win64.exe")
)
$godot = $godotCandidates | Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $godot) {
    throw "Godot 4.6.3 was not found in '$root\Godot'."
}

$testData = Join-Path $root ".godot\baseline_user_data"
$logDir = Join-Path $root ".godot\baseline_logs"
New-Item -ItemType Directory -Force -Path $testData, $logDir | Out-Null

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$env:APPDATA = $testData
$env:LOCALAPPDATA = $testData

$failures = 0
$stepNumber = 0

function Invoke-BaselineStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    $script:stepNumber++
    $safeName = $Name -replace "[^A-Za-z0-9_-]", "_"
    $logPath = Join-Path $logDir (
        "{0:D2}_{1}.log" -f $script:stepNumber, $safeName
    )
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $output = @(& $Command 2>&1)
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @($_ | Out-String)
        $exitCode = 1
    }
    $timer.Stop()
    $output | Set-Content -LiteralPath $logPath

    if ($exitCode -eq 0) {
        Write-Host (
            "[PASS] {0} ({1:N1}s)" -f $Name, $timer.Elapsed.TotalSeconds
        )
        if (-not $KeepLogs) {
            Remove-Item -LiteralPath $logPath -Force
        }
        return
    }

    $script:failures++
    Write-Host (
        "[FAIL] {0} ({1:N1}s, exit {2})" -f
        $Name, $timer.Elapsed.TotalSeconds, $exitCode
    ) -ForegroundColor Red
    Get-Content -LiteralPath $logPath -Tail 80
}

try {
    Push-Location $root

    Invoke-BaselineStep "Static diff check" {
        & git diff --check
    }
    Invoke-BaselineStep "Godot import and parse" {
        & $godot --headless --editor --path $root --quit
    }
    Invoke-BaselineStep "Domain ID and validation foundation" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_domain_foundation_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "System and gate registry" {
        & $godot --headless --path $root --script `
            "res://tests/registry/run_system_registry_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Persistent world identity" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_world_identity_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Navigation preflight route planner" {
        & $godot --headless --path $root --script `
            "res://tests/navigation/run_navigation_route_planner_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Universal campaign clock" {
        & $godot --headless --path $root --script `
            "res://tests/time/run_campaign_clock_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Faction NPC ship portrait and voice definitions" {
        & $godot --headless --path $root --script `
            "res://tests/registry/run_game_content_registry_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Unified speech service" {
        & $godot --headless --path $root --script `
            "res://tests/speech/run_speech_service_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Mission definitions and state adapter" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_mission_contract_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Timed mission metadata and expiration" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_timed_mission_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Public board fallback and placeholder validation" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_public_board_validation_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Mission instance state machine" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_mission_instance_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Mission capability registry" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_mission_capability_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Mission collection and lanes" {
        & $godot --headless --path $root --script `
            "res://tests/domain/run_mission_collection_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Mission template registry and validation" {
        & $godot --headless --path $root --script `
            "res://tests/run_mission_template_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "LLM quest objective validator" {
        & $godot --headless --path $root -- `
            --llm-validator-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Transitional save migration" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_save_migration_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign storage schemas and ownership" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_schema_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign identity and three-slot registry" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_slot_registry_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign transactions and recovery" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_transaction_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign safe and manual checkpoint bundles" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_checkpoint_store_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign chronicle branches" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_chronicle_store_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign Kaelen memory and reversal classification" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_kaelen_memory_store_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign version-2 legacy save import" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_legacy_import_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Campaign manifest and asset registry" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_campaign_manifest_store_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Phase 2 storage ownership acceptance" {
        & $godot --headless --path $root --script `
            "res://tests/persistence/run_phase_2_acceptance_tests.gd" -- `
            --baseline-offline
    }
    Invoke-BaselineStep "Version-2 save startup import" {
        & $godot --headless --path $root -- `
            --legacy-import-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Mission gameplay lifecycle" {
        & $godot --headless --path $root -- `
            --mission-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Mining economy and upgrades" {
        & $godot --headless --path $root -- `
            --economy-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Station services and pickup routing" {
        & $godot --headless --path $root -- `
            --services-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Public board urgent lifecycle" {
        & $godot --headless --path $root -- `
            --public-board-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Combat damage death and restart" {
        & $godot --headless --path $root -- `
            --combat-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Station-adjacent loaded-state combat" {
        & $godot --headless --path $root -- `
            --station-combat-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Warm-service game restart" {
        & $godot --headless --path $root -- `
            --restart-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Death reload and discarded timeline memory" {
        & $godot --headless --path $root -- `
            --death-reload-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Core startup and controls" {
        & $godot --headless --path $root -- `
            --core-smoke-test --no-save-load --baseline-offline
    }
    Invoke-BaselineStep "Autopilot obstacle and planet-circle navigation" {
        & $godot --headless --path $root -- `
            --autopilot-smoke-test --baseline-offline
    }
    Invoke-BaselineStep "Two-way gate and save restoration" {
        & $godot --headless --path $root -- `
            --jump-smoke-test --save-smoke-test --no-save-load `
            --baseline-offline
    }
    Invoke-BaselineStep "Docking and dock autosave" {
        & $godot --headless --path $root -- `
            --dock-smoke-test --no-save-load --baseline-offline
    }
}
finally {
    Pop-Location
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}

if ($failures -gt 0) {
    Write-Host (
        "Baseline suite failed: {0} of {1} steps failed. Logs: {2}" -f
        $failures, $stepNumber, $logDir
    ) -ForegroundColor Red
    exit 1
}

Write-Host (
    "Baseline suite passed: {0} of {0} steps." -f $stepNumber
) -ForegroundColor Green
exit 0
