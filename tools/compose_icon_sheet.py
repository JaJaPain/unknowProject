"""Tile generated icons into a store icon sheet and point the items at it.

Reads docs/image_needs.json. Every entry with a "sheet_cell" whose file exists
in art_inbox/ is resized into its cell of a 5 x 5 sheet (the layout the game's
store UI slices: width / 5 per cell), saved as assets/RandomIcon04.png, and
the matching items in data/content/store_items.json are switched to the new
"materials" sheet. Items whose icon is not generated yet keep their old icon.

    python tools/compose_icon_sheet.py            # compose and update
    python tools/compose_icon_sheet.py --dry-run  # report only
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
NEEDS = ROOT / "docs" / "image_needs.json"
INBOX = ROOT / "art_inbox"
SHEET = ROOT / "assets" / "RandomIcon04.png"
ITEMS = ROOT / "data" / "content" / "store_items.json"
SHEET_NAME = "materials"
SHEET_RES = "res://assets/RandomIcon04.png"
CELL = 250
GRID = 5
BACKGROUND = (11, 16, 22)

# image id -> store item id
ITEM_FOR = {
    "icon_survey_drone": "survey_drone",
    "icon_thermal_lattice": "thermal_lattice",
    "icon_rad_quartz": "rad_quartz",
    "icon_cryo_ferrite": "cryo_ferrite",
    "icon_resonant_crystal": "resonant_crystal",
}


def main() -> int:
    dry = "--dry-run" in sys.argv
    needs = json.loads(NEEDS.read_text(encoding="utf-8"))
    sheet = Image.open(SHEET).convert("RGB") if SHEET.exists() else Image.new("RGB", (CELL * GRID, CELL * GRID), BACKGROUND)
    placed = {}
    for entry in needs["images"]:
        cell = entry.get("sheet_cell")
        if cell is None:
            continue
        src = INBOX / entry["filename"]
        if not src.exists():
            print(f"missing  {entry['filename']}")
            continue
        icon = Image.open(src).convert("RGB").resize((CELL, CELL), Image.LANCZOS)
        sheet.paste(icon, (cell[0] * CELL, cell[1] * CELL))
        placed[entry["id"]] = cell
        print(f"placed   {entry['filename']} at {cell}")
    if not placed:
        print("nothing to place")
        return 0
    if dry:
        return 0
    sheet.save(SHEET)
    raw = ITEMS.read_bytes()
    crlf = b"\r\n" in raw
    data = json.loads(raw.decode("utf-8"))
    data.setdefault("icon_sheets", {})[SHEET_NAME] = SHEET_RES
    for item in data["items"]:
        for image_id, cell in placed.items():
            if ITEM_FOR.get(image_id) == item["item_id"]:
                item["icon_sheet"] = SHEET_NAME
                item["icon_cell"] = list(cell)
    text = json.dumps(data, indent=4, ensure_ascii=False) + "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    ITEMS.write_bytes(text.encode("utf-8"))
    print(f"wrote {SHEET.relative_to(ROOT)} and updated {len(placed)} item icon(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
