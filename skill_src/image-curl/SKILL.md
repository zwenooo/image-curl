---
name: image-curl
description: Use when the user asks Codex to draw, generate, create, or render a bitmap image as a local file, including generic Chinese requests such as "画一张图", "生成一张海报", or "做一张插画". This skill calls an OpenAI-compatible `/v1/images/generations` endpoint directly with curl, reading the base URL and API key from local Codex config instead of using cpa or cliproxy CLI commands.
---

# Image Curl

## Overview

Generate local bitmap image files by POSTing directly to the configured OpenAI-compatible image endpoint with `curl`. Do not use `cpa`, `cliproxy-image-cli`, or other image CLIs for this skill.

## When to use

- The user asks to draw, generate, create, render, or make a raster image and wants a local file result.
- The request is a generic prompt such as "画一只猫咪", "生成一张横版封面", "做一张产品海报", or "create an avatar".
- The user asks to use the local Codex/OpenAI-compatible image API configuration.

Do not use this skill for web image search, SVG/vector-only work, or image editing/inpainting. This skill only covers text-to-image generation through `images/generations`.

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

If the user did not specify a size, choose:

- `1536x1024` for clearly wide outputs: 横图, 横版, banner, hero, landscape wallpaper, 全景, 宽屏, YouTube thumbnail
- `1024x1536` for clearly tall outputs: 竖图, 竖版, 海报, 手机壁纸, poster, book cover
- `1024x1024` for generic images, avatars, icons, square compositions, or unclear orientation
- `auto` only when the user explicitly asks for automatic, original-ratio, or adaptive sizing

## Workflow

1. Decide the output path. If the user did not provide one, save in the current working directory with a descriptive, non-overwriting filename such as `generated-image.png`.
2. Decide whether the user's prompt is already specific enough for `gpt-image-2`. If it is vague, rewrite it into a concise image-ready prompt before calling the API.
3. Run this skill's `scripts/generate_image.sh`. The script builds JSON, calls `curl -X POST <base>/v1/images/generations`, saves the raw response temporarily, decodes `data[0].b64_json`, and writes the image file.
4. Verify the command exits with code `0` and the output file exists and is non-empty.
5. Report the saved path to the user. Mention metadata only when requested.

## Command

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "一只可爱的猫咪，毛茸茸的，正坐着看向镜头，干净背景，温暖自然光，写实风格，高质量" \
  --output ./cat.png \
  --size 1024x1024 \
  --quality auto \
  --format png \
  --moderation auto
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
    "quality": "auto",
    "output_format": "png",
    "moderation": "auto"
  }'
```

## Failure handling

- Missing base URL: check `~/.codex/config.toml` or pass `--base-url`.
- Missing API key: check `~/.codex/auth.json` or pass `--api-key`.
- Existing output: choose a new path or use `--overwrite` if the user approved replacement.
- Non-JSON/HTTP error: preserve the error body in the command output and report the upstream message.
- Missing `b64_json`: inspect the response JSON; the image was not returned in the expected format.
