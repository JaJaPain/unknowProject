"""Game copy of a textured GLB: embedded images larger than --max are scaled
down (Lanczos) and re-encoded; geometry, materials and names are untouched.
Base colour and emission maps go to JPEG when they have no alpha (--jpeg);
normal and ORM maps stay PNG (JPEG artefacts show up in lighting).

    python tools/art/shrink_glb_textures.py <in.glb> <out.glb> [--max=2048] [--jpeg]
"""
import io
import json
import struct
import sys

from PIL import Image


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2, "not a GLB v2 file"
    off, gltf, binary = 12, None, b""
    while off < len(data):
        length, kind = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + length]
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        off += 8 + length
    return gltf, binary


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    limit = 2048
    jpeg = "--jpeg" in argv
    for a in argv:
        if a.startswith("--max="):
            limit = int(a[6:])
    gltf, binary = read_glb(args[0])
    views = gltf["bufferViews"]
    image_views = {im["bufferView"]: i for i, im in enumerate(gltf.get("images", [])) if "bufferView" in im}
    # Rebuild the binary chunk view by view, replacing image bytes.
    out = bytearray()
    for vi, view in enumerate(views):
        start = view.get("byteOffset", 0)
        blob = binary[start:start + view["byteLength"]]
        if vi in image_views:
            image = gltf["images"][image_views[vi]]
            name = image.get("name", "")
            pic = Image.open(io.BytesIO(blob))
            if max(pic.size) > limit:
                scale = limit / max(pic.size)
                pic = pic.resize((round(pic.width * scale), round(pic.height * scale)), Image.LANCZOS)
            buf = io.BytesIO()
            colour = name.endswith("_basecolor") or name.endswith("_emission")
            if jpeg and colour and pic.mode in ("RGB", "L"):
                pic.save(buf, "JPEG", quality=90)
                image["mimeType"] = "image/jpeg"
            else:
                pic.save(buf, "PNG", optimize=True)
                image["mimeType"] = "image/png"
            print("%-24s %5d px  %6.1f MB -> %5.1f MB" % (name, max(pic.size), len(blob) / 1e6, buf.tell() / 1e6))
            blob = buf.getvalue()
        out += b"\0" * (-len(out) % 4)
        view["byteOffset"] = len(out)
        view["byteLength"] = len(blob)
        out += blob
    gltf["buffers"][0]["byteLength"] = len(out)
    write_glb(args[1], gltf, bytes(out))
    print("wrote %s (%.1f MB)" % (args[1], (len(out)) / 1e6))


if __name__ == "__main__":
    main(sys.argv[1:])
