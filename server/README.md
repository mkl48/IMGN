# IMGN image service

A tiny FastAPI service that turns a real image URL into pixel JSON the IMGN client draws with
`Canvas:LoadPixels` / `IMGN.PixelCanvas`. It does the PNG decoding **and** the resize server-side,
so Roblox never decodes a file or ships a giant grid.

```
GET /convert?url=<image-url>&max_width=64&format=rle
```

- `format=rle` *(default)* → `{ width, height, rows: [[ [count,r,g,b,a], … ], … ] }` — compact, great for flat / pixel art.
- `format=raw` → `{ width, height, pixels: [[ [r,g,b,a], … ], … ] }` — simplest for noisy photos.
- `max_width` resizes down (capped at 256) so instance counts stay sane.

## Run locally

```sh
cd server
pip install -r requirements.txt
uvicorn main:app --reload
# http://127.0.0.1:8000/convert?url=https://.../pic.png&max_width=64
```

## Host it free

All three give you a public HTTPS URL to point Roblox at:

- **[Render](https://render.com)** *(easiest)* — New → Web Service → connect this repo (root = `server/`). Build `pip install -r requirements.txt`, start `uvicorn main:app --host 0.0.0.0 --port $PORT` (or the included `Procfile`). Free tier **sleeps after 15 min** idle, so the first request may take ~30s to wake.
- **[Hugging Face Spaces](https://huggingface.co/spaces)** — new Space → Docker/FastAPI. Rarely sleeps; good for an always-warm demo.
- **[Vercel](https://vercel.com)** — serverless Python. No sleep, but per-request time limits (~10–60s) — fine for small images.

## Use from Roblox

Enable **Allow HTTP Requests**, then:

```lua
local HttpService = game:GetService("HttpService")
local IMGN = require(game.ReplicatedStorage.IMGN)

local API = "https://your-app.onrender.com/convert"
local imageUrl = "https://upload.wikimedia.org/.../something.png"

local json = HttpService:GetAsync(
    API .. "?url=" .. HttpService:UrlEncode(imageUrl) .. "&max_width=64&format=rle"
)
local data = HttpService:JSONDecode(json)

local canvas = IMGN.PixelCanvas(data, { Parent = surfaceGui, Driver = "GreedyMesh" })
```

See `examples/WebImage.server.luau`.
