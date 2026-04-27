#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  generate_image.sh --prompt TEXT --output FILE [options]
  generate_image.sh --prompt-file FILE --output FILE [options]

Options:
  --model NAME          Image model. Default: gpt-image-2
  --size SIZE           auto or WIDTHxHEIGHT, for example 1024x1024, 1344x768, 2048x1152
  --quality VALUE       Default: auto
  --format FORMAT       png, jpeg, or webp. Default: png
  --moderation VALUE    Default: auto
  --background VALUE    Optional background value, for example transparent or auto
  --metadata FILE       Save response metadata with b64_json omitted
  --base-url URL        Override local Codex config base_url
  --api-key KEY         Override local Codex auth API key
  --timeout SECONDS     curl max time. Default: 300
  --overwrite           Allow replacing an existing output file
  --dry-run             Print redacted request details without calling the API
  -h, --help            Show this help
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

model="gpt-image-2"
prompt=""
prompt_file=""
output=""
size="1024x1024"
quality="auto"
format="png"
moderation="auto"
background=""
metadata=""
base_url=""
api_key=""
timeout="300"
overwrite=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="${2:-}"; shift 2 ;;
    --prompt) prompt="${2:-}"; shift 2 ;;
    --prompt-file) prompt_file="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --size) size="${2:-}"; shift 2 ;;
    --quality) quality="${2:-}"; shift 2 ;;
    --format|--output-format) format="${2:-}"; shift 2 ;;
    --moderation) moderation="${2:-}"; shift 2 ;;
    --background) background="${2:-}"; shift 2 ;;
    --metadata|--metadata-path) metadata="${2:-}"; shift 2 ;;
    --base-url) base_url="${2:-}"; shift 2 ;;
    --api-key) api_key="${2:-}"; shift 2 ;;
    --timeout) timeout="${2:-}"; shift 2 ;;
    --overwrite) overwrite=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$output" ]] || die "--output is required."
[[ -n "$model" ]] || die "--model must not be empty."
[[ -n "$size" ]] || die "--size must not be empty."
[[ -n "$format" ]] || die "--format must not be empty."
size="${size,,}"
[[ "$size" == "auto" || "$size" =~ ^[1-9][0-9]{1,5}x[1-9][0-9]{1,5}$ ]] || die "--size must be auto or WIDTHxHEIGHT, for example 1024x1024, 1344x768, 2048x1152."
[[ "$format" =~ ^(png|jpeg|jpg|webp)$ ]] || die "--format must be png, jpeg, jpg, or webp."
[[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]] || die "--timeout must be a positive integer."

if [[ -n "$prompt" && -n "$prompt_file" ]]; then
  die "Provide either --prompt or --prompt-file, not both."
fi

if [[ -n "$prompt_file" ]]; then
  [[ -f "$prompt_file" ]] || die "Prompt file not found: $prompt_file"
  prompt="$(<"$prompt_file")"
fi

prompt="${prompt#"${prompt%%[![:space:]]*}"}"
prompt="${prompt%"${prompt##*[![:space:]]}"}"
[[ -n "$prompt" ]] || die "--prompt or --prompt-file is required."

output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
output_dir="$(dirname "$output")"
[[ -d "$output_dir" ]] || mkdir -p "$output_dir"
if [[ -e "$output" && "$overwrite" -ne 1 ]]; then
  die "Output already exists: $output (use --overwrite to replace it)"
fi

if [[ -n "$metadata" ]]; then
  metadata="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$metadata")"
  mkdir -p "$(dirname "$metadata")"
fi

config_json="$(python3 - "$base_url" "$api_key" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

override_base_url = sys.argv[1].strip()
override_api_key = sys.argv[2].strip()

def first(*values):
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""

codex_home = Path(first(os.environ.get("CODEX_HOME")) or Path.home() / ".codex").expanduser()
config_path = codex_home / "config.toml"
auth_path = codex_home / "auth.json"

def strip_comment(line):
    result = []
    in_string = False
    escaped = False
    for char in line:
        if char == '"' and not escaped:
            in_string = not in_string
        if char == "#" and not in_string:
            break
        result.append(char)
        escaped = char == "\\" and not escaped
        if char != "\\":
            escaped = False
    return "".join(result)

def parse_value(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        return raw[1:-1].replace(r'\"', '"')
    if raw.lower() == "true":
        return True
    if raw.lower() == "false":
        return False
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    return raw

top = {}
tables = {}
current = None
if config_path.is_file():
    for raw_line in config_path.read_text(encoding="utf-8-sig").splitlines():
        line = strip_comment(raw_line).strip()
        if not line:
            continue
        match = re.fullmatch(r"\[(.+)\]", line)
        if match:
            current = match.group(1).strip()
            tables.setdefault(current, {})
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        target = tables[current] if current else top
        target[key.strip()] = parse_value(value)

def normalize_base_url(value):
    return value.rstrip("/")

base_url = first(
    override_base_url,
    os.environ.get("IMAGE_CURL_BASE_URL"),
    os.environ.get("OPENAI_BASE_URL"),
    os.environ.get("CLIPROXY_BASE_URL"),
)

if not base_url:
    provider = first(str(top.get("model_provider", "")))
    if provider:
        provider_base = tables.get(f"model_providers.{provider}", {}).get("base_url")
        base_url = first(provider_base)

if not base_url:
    for name in sorted(tables):
        if name.startswith("model_providers."):
            base_url = first(tables[name].get("base_url"))
            if base_url:
                break

api_key = first(
    override_api_key,
    os.environ.get("IMAGE_CURL_API_KEY"),
    os.environ.get("OPENAI_API_KEY"),
    os.environ.get("CLIPROXY_API_KEY"),
)

if not api_key and auth_path.is_file():
    try:
        auth = json.loads(auth_path.read_text(encoding="utf-8"))
    except Exception:
        auth = {}
    if isinstance(auth, dict):
        api_key = first(
            auth.get("OPENAI_API_KEY"),
            auth.get("OPENAI_API_TOKEN"),
            auth.get("api_key"),
            auth.get("token"),
            auth.get("openai_api_key"),
        )

print(json.dumps({
    "codex_home": str(codex_home),
    "config_path": str(config_path),
    "auth_path": str(auth_path),
    "base_url": normalize_base_url(base_url) if base_url else "",
    "api_key": api_key,
}, ensure_ascii=False))
PY
)"

base_url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["base_url"])' "$config_json")"
api_key="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["api_key"])' "$config_json")"
config_path="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["config_path"])' "$config_json")"
auth_path="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["auth_path"])' "$config_json")"

[[ -n "$base_url" ]] || die "Unable to discover base URL from $config_path. Pass --base-url or set IMAGE_CURL_BASE_URL."
[[ -n "$api_key" ]] || die "Unable to discover API key from $auth_path. Pass --api-key or set IMAGE_CURL_API_KEY."

route_base="${base_url%/}"
if [[ "$route_base" == */v1 ]]; then
  endpoint="$route_base/images/generations"
else
  endpoint="$route_base/v1/images/generations"
fi

payload="$(python3 - "$model" "$prompt" "$size" "$quality" "$format" "$moderation" "$background" <<'PY'
import json
import sys

model, prompt, size, quality, output_format, moderation, background = sys.argv[1:8]
if output_format == "jpg":
    output_format = "jpeg"

payload = {
    "model": model,
    "prompt": prompt,
    "size": size,
    "quality": quality,
    "output_format": output_format,
    "moderation": moderation,
}
if background.strip():
    payload["background"] = background.strip()
print(json.dumps(payload, ensure_ascii=False))
PY
)"

if [[ "$dry_run" -eq 1 ]]; then
  python3 - "$endpoint" "$payload" "$output" "$metadata" <<'PY'
import json
import sys

endpoint, payload, output, metadata = sys.argv[1:5]
print(json.dumps({
    "endpoint": endpoint,
    "authorization": "Bearer ***",
    "payload": json.loads(payload),
    "output": output,
    "metadata": metadata or None,
}, ensure_ascii=False, indent=2))
PY
  exit 0
fi

response_file="$(mktemp "${TMPDIR:-/tmp}/image-curl-response.XXXXXX.json")"
cleanup() {
  rm -f "$response_file"
}
trap cleanup EXIT

curl -sS --fail-with-body -X POST "$endpoint" \
  -H "Authorization: Bearer $api_key" \
  -H "Content-Type: application/json" \
  -H "Cache-Control: no-store, no-cache, max-age=0" \
  -H "Pragma: no-cache" \
  --max-time "$timeout" \
  -d "$payload" > "$response_file"

python3 - "$response_file" "$output" "$metadata" <<'PY'
import base64
import json
import sys
from pathlib import Path

response_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
metadata_path = Path(sys.argv[3]) if sys.argv[3] else None

try:
    response = json.loads(response_path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"Response is not valid JSON: {exc}")

data = response.get("data")
if not isinstance(data, list) or not data:
    raise SystemExit("Response JSON does not contain data[0].")

b64 = data[0].get("b64_json") if isinstance(data[0], dict) else None
if not isinstance(b64, str) or not b64:
    raise SystemExit("Response JSON does not contain data[0].b64_json.")

try:
    image_bytes = base64.b64decode(b64, validate=True)
except Exception as exc:
    raise SystemExit(f"Invalid base64 image data: {exc}")

output_path.write_bytes(image_bytes)

if metadata_path:
    sanitized = json.loads(json.dumps(response))
    for item in sanitized.get("data", []):
        if isinstance(item, dict) and "b64_json" in item:
            item["b64_json"] = "<omitted>"
    sanitized["saved_file"] = str(output_path)
    metadata_path.write_text(json.dumps(sanitized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(json.dumps({
    "saved_file": str(output_path),
    "bytes": len(image_bytes),
    "revised_prompt": data[0].get("revised_prompt") if isinstance(data[0], dict) else None,
}, ensure_ascii=False))
PY
