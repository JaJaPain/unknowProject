# Image generation: ChatGPT loop prompt

Paste everything in the box below into ChatGPT (a model with image
generation), then attach two files: `docs/image_needs.json` and
`assets/RandomIcon02.png` (the style reference). Save each image it produces
into `art_inbox/` under the filename it gives, then run:

```bash
python tools/compose_icon_sheet.py
```

That tiles the icons into `assets/RandomIcon04.png` and switches the store
items to the new icons. Items whose icon is missing keep their old one, so
you can run it again after regenerating any single image.

---

```text
You are generating game art for a space trading game. Attached are:
1. image_needs.json: the list of images to make.
2. RandomIcon02.png: a sheet of existing store icons. Match its style exactly.

Work through the "images" array in order, one image per reply:

For each entry:
- Build the prompt from: the entry's "prompt", then (unless the entry says
  it does not use the shared style) the file's "shared_style", with the
  entry's "label" as the only text on the image.
- Generate exactly one image at the entry's "size".
- Reply with the image and one line: "Save as: <filename>".
- Do not add any other text, logos, watermarks or extra labels.
- Keep the look consistent across the whole set: same frame, same dark
  background, same lighting, same label font and placement, so the new
  icons sit next to the reference sheet without standing out.

After each image, wait for me to say "next" (or "redo" with notes) before
moving on. When the list is finished, say "All images done" and list the
filenames.
```
