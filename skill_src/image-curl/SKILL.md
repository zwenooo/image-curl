---
name: image-curl
description: Use when the user asks Codex to draw, generate, create, edit, transform, or do image-to-image work as a local bitmap file, including generic Chinese requests such as "画一张图", "生成一张海报", "做一张插画", or "把这张图的背景换成星空". This skill calls OpenAI-compatible `/v1/images/generations` and `/v1/images/edits` endpoints directly with curl, reading the base URL and API key from local Codex config instead of using cpa or cliproxy CLI commands.
---

# Image Curl

## Overview

Generate or edit local bitmap image files by POSTing directly to the configured OpenAI-compatible image endpoint with `curl`. Do not use `cpa`, `cliproxy-image-cli`, or other image CLIs for this skill.

## When to use

- The user asks to draw, generate, create, render, or make a raster image and wants a local file result.
- The user asks to transform one or more local images with a prompt, such as changing a background, restyling a product photo, or combining references.
- The request is a generic prompt such as "画一只猫咪", "生成一张横版封面", "做一张产品海报", or "create an avatar".
- The user asks to use the local Codex/OpenAI-compatible image API configuration.

Do not use this skill for web image search or SVG/vector-only work. This skill covers text-to-image generation through `images/generations` and image-to-image edits through `images/edits`.

## Defaults

- Default model: `gpt-image-2`
- Default size: `1024x1024`
- Default quality: `auto`
- Default output format: `png`
- Default moderation: `auto`
- Config source: `CODEX_HOME` when set, otherwise `~/.codex`
- Base URL source order: `IMAGE_CURL_BASE_URL`, `OPENAI_BASE_URL`, `CLIPROXY_BASE_URL`, then `[model_providers.<model_provider>].base_url` in `config.toml`, then the first model provider with `base_url`
- API key source order: `IMAGE_CURL_API_KEY`, `OPENAI_API_KEY`, `CLIPROXY_API_KEY`, then `auth.json` keys `OPENAI_API_KEY`, `OPENAI_API_TOKEN`, `api_key`, `token`, or `openai_api_key`

## Size selection

The upstream supports arbitrary `WIDTHxHEIGHT` sizes within its available 1K, 2K, and 4K output budgets. Do not restrict requests to a fixed whitelist and do not locally crop or resize after generation.

Confirmed upstream constraints:

- longest edge must be less than or equal to `3840`
- both edges must be multiples of `16`
- maximum supported aspect ratio is `3:1`
- total pixels must be in `[655360, 8294400]`

Selection rules:

- If the user gives an exact valid size such as `1344x768`, `1200x1600`, or `2048x1152`, pass it exactly.
- If the user gives an invalid size, adjust only as much as needed to fit the constraints and preserve the user's intent. Example: `4096x1024` should become `3840x1280` for a 4K horizontal long image because the longest edge limit is `3840` and the aspect ratio limit is `3:1`.
- If the user gives only an aspect/orientation, choose dimensions that preserve that intent instead of forcing square output.
- If the user asks for 1K, 2K, or 4K, choose dimensions in that output tier while preserving the requested aspect ratio.
- If no size, tier, or orientation is specified, use `1024x1024`.
- Use `auto` only when the user explicitly asks for automatic, original-ratio, or adaptive sizing.

Examples:

- wide poster or banner: `1536x864`, `1600x900`, or another suitable wide size
- 4K horizontal long image: `3840x1280`
- vertical poster or phone wallpaper: `896x1600`, `1024x1536`, or another suitable tall size
- square avatar/icon: `1024x1024`

## Workflow

1. Decide the output path. If the user did not provide one, save in the current working directory with a descriptive, non-overwriting filename such as `generated-image.png`.
2. Decide whether the user's prompt is already specific enough for `gpt-image-2`. If it is vague, rewrite it into a concise image-ready prompt before calling the API.
3. For text-to-image, run this skill's `scripts/generate_image.sh`. The script builds JSON, calls `curl -X POST <base>/v1/images/generations`, saves the raw response temporarily, decodes returned `data[].b64_json`, and writes image files.
4. For image-to-image edits, run this skill's `scripts/edit_image.sh`. The script sends multipart form data to `curl -X POST <base>/v1/images/edits`, including repeated `image[]=@<file>` fields.
5. Verify the command exits with code `0` and the output file exists and is non-empty.
6. Report the saved path to the user. Mention metadata only when requested.

## Text-to-image command

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "一只可爱的猫咪，毛茸茸的，正坐着看向镜头，干净背景，温暖自然光，写实风格，高质量" \
  --output ./cat.png \
  --size 1024x1024 \
  --count 1 \
  --quality auto \
  --format png \
  --moderation auto
```

## Image-to-image command

```bash
~/.codex/skills/image-curl/scripts/edit_image.sh \
  --image ./photo1.png \
  --image ./photo2.jpg \
  --prompt "把背景换成星空，保留主体轮廓和服装细节" \
  --output ./edited.png \
  --size 1024x1024 \
  --count 1 \
  --quality auto \
  --format png \
  --moderation auto
```

## Calling the skill with parameters

Codex skills do not have a strict argument protocol. If the user writes `key=value` or natural-language parameter instructions, map them to the matching script flags.

Examples:

```text
$image-curl prompt="可爱猫女" output="./catgirl.png" size="1024x1024" quality="auto" format="png"
```

```text
$image-curl prompt="一只猫咪" output="./cat.png" base_url="https://api.example.com/v1" api_key="<API_KEY>"
```

```text
$image-curl 画一只可爱猫咪，保存为 ./cat.png，尺寸 1024x1024，使用 base_url=https://api.example.com/v1，api_key=<API_KEY>
```

```text
$image-curl 画一只猫咪，保存为 ./cat.png，使用环境变量 IMAGE_CURL_BASE_URL 和 IMAGE_CURL_API_KEY
```

Prefer environment variables for secrets. Avoid asking the user to put a real API key in chat unless they explicitly choose to do so.

Supported text-to-image chat-level fields map to script flags: `prompt`, `output`, `size`, `count`, `n`, `quality`, `format`, `output_compression`, `output-compression`, `moderation`, `background`, `metadata`, `overwrite`, `dry_run`, `base_url`, and `api_key`. For image-to-image, also support repeated `image` fields. `size` can be `auto` or any upstream-supported `WIDTHxHEIGHT`; keep the user's requested aspect ratio. `count`/`n` maps to the API's `n` parameter and requests multiple images in one API call. `output_compression` maps to `output_compression` and is only valid for `jpeg` or `webp` output.

When `count` is greater than 1, output paths are generated by inserting a numeric suffix before the extension. Example: `output="./poster.png" count=4` saves `poster-1.png`, `poster-2.png`, `poster-3.png`, and `poster-4.png`.

The script passes `count`/`n` through to the upstream as the API `n` parameter and saves every item returned in `data[]`. If an upstream accepts but ignores `n`, the script reports `requested_count` and `returned_count` so the mismatch is visible.

Multi-output example:

```text
$image-curl prompt="四张不同风格的新疆旅游海报" output="./xinjiang-poster.png" size="1280x1920" count=4
```

Compressed webp example:

```text
$image-curl prompt="两张猫咪头像" output="./cat.webp" size="1024x1024" format="webp" output_compression=80 count=2
```

Image-to-image examples:

```text
$image-curl image="./photo1.png" prompt="把背景换成星空" output="./starry.png" size="1024x1024"
```

```text
$image-curl image="./photo1.png" image="./photo2.jpg" prompt="融合两张参考图，生成统一风格海报" output="./merged.png"
```

Useful options:

- `--prompt-file <txt>` for long or multiline prompts
- `--metadata <json>` to save response details without embedding the large base64 image payload
- `--overwrite` only when replacing an existing output is intended
- `--dry-run` to validate config discovery and payload without calling the API
- `--base-url <url>` or `--api-key <key>` only for explicit overrides

The underlying request shape is:

```bash
curl -sS --fail-with-body -X POST "$BASE_URL/v1/images/generations" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Cache-Control: no-store, no-cache, max-age=0" \
  -H "Pragma: no-cache" \
  -d '{
    "model": "gpt-image-2",
    "prompt": "...",
    "size": "1024x1024",
    "n": 1,
    "quality": "auto",
    "output_format": "png",
    "output_compression": 80,
    "moderation": "auto"
  }'
```

For image-to-image edits, the request shape is:

```bash
curl -sS --fail-with-body -X POST "$BASE_URL/v1/images/edits" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Cache-Control: no-store, no-cache, max-age=0" \
  -H "Pragma: no-cache" \
  -F "model=gpt-image-2" \
  -F "prompt=把背景换成星空" \
  -F "size=1024x1024" \
  -F "n=1" \
  -F "quality=auto" \
  -F "output_format=png" \
  -F "output_compression=80" \
  -F "moderation=auto" \
  -F "image[]=@photo1.png" \
  -F "image[]=@photo2.jpg"
```

## Failure handling

- Missing base URL: check `~/.codex/config.toml` or pass `--base-url`.
- Missing API key: check `~/.codex/auth.json` or pass `--api-key`.
- Existing output: choose a new path or use `--overwrite` if the user approved replacement.
- Non-JSON/HTTP error: preserve the error body in the command output and report the upstream message.
- Missing `b64_json`: inspect the response JSON; the image was not returned in the expected format.
