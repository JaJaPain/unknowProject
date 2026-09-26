"""Remove a baked-in text label from a generated icon (art stays text-free
for localization; the game draws item names itself).

Finds the bright, low-saturation text pixels in the bottom band inside the
frame and paints their bounding box over with the band's own dark background.

    python tools/strip_icon_label.py art_inbox/icon_x.png [more.png ...]
"""
import sys

from PIL import Image, ImageFilter


def strip(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    x0, x1 = int(w * 0.08), int(w * 0.92)
    y0, y1 = int(h * 0.74), int(h * 0.93)
    def is_text(c):
        hi, lo = max(c), min(c)
        return hi > 170 and hi - lo < 45

    # Rows of text, found from the bottom up: the label is the lowest band of
    # bright neutral pixels, and it ends at the first empty gap above it (so
    # the glow of the object itself is never mistaken for letters).
    counts = [sum(1 for x in range(x0, x1) if is_text(px[x, y])) for y in range(y0, y1)]
    rows = [i for i, c in enumerate(counts) if c > 2]
    if not rows:
        print("%s: no label found" % path)
        return
    bottom = rows[-1]
    top = bottom
    gap = 0
    for i in range(bottom, -1, -1):
        if counts[i] > 2:
            top = i
            gap = 0
        else:
            gap += 1
            if gap > int(h * 0.01):
                break
    xs, dark = [], []
    for y in range(y0 + top, y0 + bottom + 1):
        for x in range(x0, x1):
            c = px[x, y]
            if is_text(c):
                xs.append(x)
            elif max(c) < 60:
                dark.append(c)
    ys = [y0 + top, y0 + bottom]
    if not xs or not dark:
        print("%s: no label found" % path)
        return
    pad = int(w * 0.012)
    box = (max(x0, min(xs) - pad), max(y0, min(ys) - pad), min(x1, max(xs) + pad), min(y1, max(ys) + pad))
    dark.sort(key=lambda c: sum(c))
    bg = dark[len(dark) // 2]
    patch = Image.new("RGB", (box[2] - box[0], box[3] - box[1]), bg)
    im.paste(patch, box[:2])
    # Soften the patch edge into the surrounding background.
    region = im.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)).filter(ImageFilter.GaussianBlur(pad // 2 or 1))
    inner = im.crop(box)
    region.paste(inner, (pad, pad))
    im.paste(region, (box[0] - pad, box[1] - pad))
    im.save(path)
    print("%s: removed label in %s" % (path, box))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        strip(p)
