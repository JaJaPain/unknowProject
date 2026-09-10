param(
    [int]$SystemSeed = 0,
    [int]$ShipCount = 8,
    [string]$Faction = ""
)

$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
$ScriptPath = Join-Path $PSScriptRoot "generate_single.py"
$OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "..\assets\ships\generated"
$OutputDir = (Resolve-Path $OutputDir -ErrorAction SilentlyContinue) ?? $OutputDir

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$Textures = @{
    "zenith" = "NavyBlueMetal.png"
    "aurelia" = "ForestGreenMetal.png"
    "vanguard" = "RedMetal.png"
    "" = "metal.png"
}

$Emblems = @{
    "zenith" = "ZenithBadge.png"
    "aurelia" = "AurelliaBadge.png"
    "vanguard" = "VanguardBadge.png"
    "" = "none"
}

$Classes = @("fighter", "hauler")
$Factions = if ($Faction -ne "") { @($Faction) } else { @("zenith", "aurelia", "vanguard") }

Write-Host "Generating $ShipCount ships for system seed $SystemSeed..."

for ($i = 1; $i -le $ShipCount; $i++) {
    $seed = "ship_${SystemSeed}_${i}"
    $outFile = Join-Path $OutputDir "$seed.glb"

    if (Test-Path $outFile) {
        Write-Host "  [$i/$ShipCount] $seed - already exists, skipping"
        continue
    }

    $fac = $Factions[$i % $Factions.Count]
    $tex = $Textures[$fac]
    $emb = $Emblems[$fac]
    $cls = $Classes[$i % $Classes.Count]
    $met = [math]::Round(0.7 + (Get-Random -Minimum 0 -Maximum 25) / 100.0, 2)

    $maxAttempts = 10
    $attempt = 0
    $generated = $false

    while ($attempt -lt $maxAttempts -and -not $generated) {
        $attempt++
        $currentSeed = if ($attempt -eq 1) { $seed } else { "${seed}_$(Get-Random -Maximum 99999)" }
        Write-Host "  [$i/$ShipCount] $currentSeed - $fac $cls (attempt $attempt)..."

        & $BlenderExe --background --python $ScriptPath -- `
            --seed $currentSeed `
            --class $cls `
            --texture $tex `
            --emblem $emb `
            --normal "hull_normal.png" `
            --metallic $met `
            --output $outFile 2>&1 | Out-Null

        if (Test-Path $outFile) {
            $sizeMB = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
            Write-Host "    OK (${sizeMB}MB)"
            $generated = $true
        } elseif ($attempt -lt $maxAttempts) {
            Write-Host "    Rejected (missing hardpoints/thrusters), retrying with new seed..."
        } else {
            Write-Host "    FAILED after $maxAttempts attempts"
        }
    }
}

Write-Host "Done."
