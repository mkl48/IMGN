"""
IMGN image service — converts a real image URL into pixel JSON that IMGN can draw.

Roblox can't read an uploaded decal's pixels, and decoding a PNG in Luau is slow. This tiny
service does the decoding (and the resize, so you don't ship a huge grid to Roblox) and returns
JSON the IMGN client consumes with Canvas:LoadPixels / IMGN.PixelCanvas.

    GET /convert?url=<image-url>&max_width=64&format=rle

  format=rle  (default) -> { "width", "height", "rows":  [ [ [count,r,g,b,a], ... ], ... ] }
  format=raw            -> { "width", "height", "pixels": [ [ [r,g,b,a], ... ],       ... ] }

RLE is far smaller for flat / pixel art; raw is simplest for noisy photos.

Run locally:  uvicorn main:app --reload
"""

from io import BytesIO

import requests
from fastapi import FastAPI, HTTPException
from PIL import Image

app = FastAPI(title="IMGN image service")

MAX_ALLOWED_WIDTH = 256  # keep Roblox instance counts sane


@app.get("/")
def health():
    return {"ok": True, "service": "imgn-image"}


def fetch_and_resize(url: str, max_width: int) -> Image.Image:
    try:
        resp = requests.get(url, timeout=10)
    except requests.RequestException as exc:
        raise HTTPException(400, f"could not fetch image: {exc}")
    if resp.status_code != 200:
        raise HTTPException(400, f"image URL returned {resp.status_code}")

    img = Image.open(BytesIO(resp.content)).convert("RGBA")

    max_width = max(1, min(max_width, MAX_ALLOWED_WIDTH))
    if img.width > max_width:
        ratio = max_width / float(img.width)
        new_height = max(1, int(img.height * ratio))
        img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
    return img


@app.get("/convert")
def convert(url: str, max_width: int = 64, format: str = "rle"):
    img = fetch_and_resize(url, max_width)
    width, height = img.size
    px = img.load()

    if format == "raw":
        pixels = [[list(px[x, y]) for x in range(width)] for y in range(height)]
        return {"width": width, "height": height, "pixels": pixels}

    # run-length encode each row: [count, r, g, b, a]
    rows = []
    for y in range(height):
        runs = []
        current = px[0, y]
        count = 1
        for x in range(1, width):
            pixel = px[x, y]
            if pixel == current:
                count += 1
            else:
                runs.append([count, *current])
                current = pixel
                count = 1
        runs.append([count, *current])
        rows.append(runs)

    return {"width": width, "height": height, "rows": rows}
