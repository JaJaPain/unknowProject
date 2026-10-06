"""Tile the 16 target icons (art_inbox/target_icons, docs/target_icon_brief.md)
into assets/ui/target_icons.png: a 4 x 4 sheet of 256 px cells, white on
transparent, in ORDER (UIManager.TARGET_ICON indexes match).

    python tools/compose_target_icons.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "art_inbox" / "target_icons"
SHEET = ROOT / "assets" / "ui" / "target_icons.png"
CELL = 256
ORDER = ["ship_hauler", "ship_combat", "asteroid_rock", "asteroid_ice",
         "station", "outpost", "gate", "planet_rocky",
         "planet_ocean", "planet_gas", "star", "wreckage",
         "derelict", "anomaly", "cargo", "destination"]


def main() -> None:
    sheet = Image.new("RGBA", (CELL * 4, CELL * 4), (255, 255, 255, 0))
    for i, name in enumerate(ORDER):
        icon = Image.open(INBOX / ("target_%s.png" % name)).convert("RGBA").resize((CELL, CELL), Image.LANCZOS)
        sheet.paste(icon, ((i % 4) * CELL, (i // 4) * CELL))
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET)
    print("wrote", SHEET, sheet.size)


if __name__ == "__main__":
    main()
