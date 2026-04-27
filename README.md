# image-curl

`image-curl` is a Codex skill for generating local image files by calling an OpenAI-compatible image endpoint directly with `curl`.

`image-curl` 是一个 Codex skill，用于通过 `curl` 直接调用 OpenAI 兼容图片接口，并把生成结果保存为本地图片文件。

- Direct API call: `POST /v1/images/generations`
- Default model: `gpt-image-2`
- No `cpa`, no `cliproxy-image-cli`, no extra image CLI dependency
- Reads `base_url` and API key from local Codex config by default
- Saves `data[0].b64_json` as a local `png`, `jpeg`, or `webp` file

## 中文说明

### 功能

- 在 Codex 中通过 `$image-curl` 生成图片
- 默认读取本机 Codex 配置，不需要在 prompt 里写 API key
- 直接使用 `curl -X POST <base>/v1/images/generations`
- 自动解码响应里的 `data[0].b64_json`
- 支持输出文件、metadata、覆盖保护、dry run

这个 skill 只做文字生成图片，不做图片编辑、蒙版、网页搜图或 SVG 编辑。

### 安装

```bash
git clone git@github.com:zwenooo/image-curl.git
cd image-curl

mkdir -p ~/.codex/skills
cp -R ./skill_src/image-curl ~/.codex/skills/image-curl
chmod +x ~/.codex/skills/image-curl/scripts/generate_image.sh
```

如果你使用了自定义 `CODEX_HOME`：

```bash
mkdir -p "$CODEX_HOME/skills"
cp -R ./skill_src/image-curl "$CODEX_HOME/skills/image-curl"
chmod +x "$CODEX_HOME/skills/image-curl/scripts/generate_image.sh"
```

### 在 Codex 中使用

显式调用：

```text
$image-curl 可爱猫女
```

指定保存路径：

```text
$image-curl 生成一张横版赛博城市壁纸，保存为 ./cyber-city.png
```

普通图片请求也可以触发这个 skill：

```text
画一只坐在窗边的橘猫，温暖自然光，保存到当前目录
```

### 调用 skill 时传参

Codex skill 没有固定的参数协议。你可以在聊天里用 `key=value` 写清楚参数，Codex 会把它们转换成脚本参数。

常规参数：

```text
$image-curl prompt="可爱猫女" output="./catgirl.png" size="1024x1024" quality="auto" format="png"
```

自定义 base URL 和 API key：

```text
$image-curl prompt="一只猫咪" output="./cat.png" base_url="https://api.example.com/v1" api_key="<API_KEY>"
```

自然语言写法也可以：

```text
$image-curl 画一只可爱猫咪，保存为 ./cat.png，尺寸 1024x1024，使用 base_url=https://api.example.com/v1，api_key=<API_KEY>
```

更推荐把密钥放在环境变量里，不要把真实 API key 发进聊天：

```text
$image-curl 画一只猫咪，保存为 ./cat.png，使用环境变量 IMAGE_CURL_BASE_URL 和 IMAGE_CURL_API_KEY
```

可在聊天中表达的常用参数：

```text
prompt, output, size, quality, format, moderation, background, metadata, overwrite, dry_run, base_url, api_key
```

`size` 可以写成 `auto` 或任意上游支持的 `宽x高`，例如：

```text
$image-curl prompt="新疆旅游宣传海报" output="./xinjiang.png" size="1200x1800"
```

不要为了适配固定尺寸强行裁剪；如果用户给出具体宽高，就按原样传给接口。如果用户只说 1K、2K、4K 或横版/竖版，Codex 应按对应档位和方向选择合适宽高。

### 直接运行脚本

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "一只可爱的猫咪，毛茸茸的，正坐着看向镜头，干净背景，温暖自然光，写实风格，高质量" \
  --output ./cat.png \
  --size 1024x1024 \
  --quality auto \
  --format png \
  --moderation auto
```

保存 metadata：

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "一张日系插画风格的可爱猫女头像" \
  --output ./catgirl.png \
  --metadata ./catgirl.metadata.json
```

只检查配置和请求体，不调用接口：

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "一只猫咪" \
  --output ./cat.png \
  --dry-run
```

### 配置读取规则

默认会从本机 Codex 配置读取：

```text
~/.codex/config.toml
~/.codex/auth.json
```

如果设置了 `CODEX_HOME`，则读取：

```text
$CODEX_HOME/config.toml
$CODEX_HOME/auth.json
```

`base_url` 读取顺序：

1. `IMAGE_CURL_BASE_URL`
2. `OPENAI_BASE_URL`
3. `CLIPROXY_BASE_URL`
4. `config.toml` 中当前 `model_provider` 对应的 `base_url`
5. `config.toml` 中第一个带 `base_url` 的 `model_providers.*`

API key 读取顺序：

1. `IMAGE_CURL_API_KEY`
2. `OPENAI_API_KEY`
3. `CLIPROXY_API_KEY`
4. `auth.json` 中的 `OPENAI_API_KEY`、`OPENAI_API_TOKEN`、`api_key`、`token` 或 `openai_api_key`

也可以显式覆盖：

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --base-url https://api.example.com/v1 \
  --api-key "$OPENAI_API_KEY" \
  --prompt "一只猫咪" \
  --output ./cat.png
```

不要把真实 API key 提交到 Git 仓库。

### 参数

```text
--prompt TEXT          图片提示词
--prompt-file FILE     从文件读取提示词
--output FILE          输出图片路径，必填
--model NAME           默认 gpt-image-2
--size SIZE            auto 或任意上游支持的 宽x高，例如 1024x1024, 1344x768, 1200x1800
--quality VALUE        默认 auto
--format FORMAT        png, jpeg, webp
--moderation VALUE     默认 auto
--background VALUE     可选，例如 transparent 或 auto
--metadata FILE        保存不含 b64_json 的响应 metadata
--timeout SECONDS      curl 超时时间，默认 300
--overwrite            允许覆盖已有输出文件
--dry-run              打印脱敏请求信息，不调用接口
```

### 请求格式

脚本最终发送的请求形态如下：

```bash
curl -sS --fail-with-body -X POST "$BASE_URL/v1/images/generations" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Cache-Control: no-store, no-cache, max-age=0" \
  -H "Pragma: no-cache" \
  -d '{
    "model": "gpt-image-2",
    "prompt": "一只猫咪",
    "size": "1024x1024",
    "quality": "auto",
    "output_format": "png",
    "moderation": "auto"
  }'
```

### 项目结构

```text
skill_src/
  image-curl/
    SKILL.md
    agents/
      openai.yaml
    scripts/
      generate_image.sh
README.md
```

## English

### What It Does

- Lets Codex generate images through `$image-curl`
- Reuses local Codex configuration, so prompts do not need API keys
- Calls `curl -X POST <base>/v1/images/generations` directly
- Decodes `data[0].b64_json` into a local image file
- Supports output paths, metadata export, overwrite protection, and dry runs

This skill is for text-to-image generation only. It does not handle image editing, masks, web image search, or SVG editing.

### Installation

```bash
git clone git@github.com:zwenooo/image-curl.git
cd image-curl

mkdir -p ~/.codex/skills
cp -R ./skill_src/image-curl ~/.codex/skills/image-curl
chmod +x ~/.codex/skills/image-curl/scripts/generate_image.sh
```

If you use a custom `CODEX_HOME`:

```bash
mkdir -p "$CODEX_HOME/skills"
cp -R ./skill_src/image-curl "$CODEX_HOME/skills/image-curl"
chmod +x "$CODEX_HOME/skills/image-curl/scripts/generate_image.sh"
```

### Using It In Codex

Explicit invocation:

```text
$image-curl cute catgirl
```

With an output path:

```text
$image-curl Generate a wide cyberpunk city wallpaper and save it as ./cyber-city.png
```

Plain image requests may also trigger the skill:

```text
Draw an orange cat sitting beside a window in warm natural light and save it in the current directory.
```

### Passing Parameters To The Skill

Codex skills do not have a strict argument protocol. You can write `key=value` arguments in chat, and Codex maps them to script flags.

Common parameters:

```text
$image-curl prompt="cute catgirl" output="./catgirl.png" size="1024x1024" quality="auto" format="png"
```

Custom base URL and API key:

```text
$image-curl prompt="A cat" output="./cat.png" base_url="https://api.example.com/v1" api_key="<API_KEY>"
```

Natural language works too:

```text
$image-curl Draw a cute cat and save it as ./cat.png, size 1024x1024, using base_url=https://api.example.com/v1 and api_key=<API_KEY>
```

Prefer environment variables for secrets instead of sending a real API key in chat:

```text
$image-curl Draw a cat, save it as ./cat.png, and use IMAGE_CURL_BASE_URL and IMAGE_CURL_API_KEY from the environment.
```

Common fields you can express in chat:

```text
prompt, output, size, quality, format, moderation, background, metadata, overwrite, dry_run, base_url, api_key
```

`size` can be `auto` or any upstream-supported `WIDTHxHEIGHT`, for example:

```text
$image-curl prompt="Xinjiang travel poster" output="./xinjiang.png" size="1200x1800"
```

Do not force fixed-size cropping. If the user gives exact dimensions, pass them through unchanged. If the user only asks for 1K, 2K, 4K, wide, or tall output, Codex should choose dimensions in that tier while preserving the requested orientation.

### Running The Script Directly

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "A cute fluffy cat sitting and looking at the camera, clean background, warm natural light, realistic style, high quality" \
  --output ./cat.png \
  --size 1024x1024 \
  --quality auto \
  --format png \
  --moderation auto
```

Save metadata:

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "A cute catgirl avatar in Japanese illustration style" \
  --output ./catgirl.png \
  --metadata ./catgirl.metadata.json
```

Validate configuration and payload without calling the API:

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --prompt "A cat" \
  --output ./cat.png \
  --dry-run
```

### Configuration Discovery

By default, the script reads:

```text
~/.codex/config.toml
~/.codex/auth.json
```

When `CODEX_HOME` is set, it reads:

```text
$CODEX_HOME/config.toml
$CODEX_HOME/auth.json
```

Base URL lookup order:

1. `IMAGE_CURL_BASE_URL`
2. `OPENAI_BASE_URL`
3. `CLIPROXY_BASE_URL`
4. `base_url` for the active `model_provider` in `config.toml`
5. the first `model_providers.*` entry in `config.toml` with a `base_url`

API key lookup order:

1. `IMAGE_CURL_API_KEY`
2. `OPENAI_API_KEY`
3. `CLIPROXY_API_KEY`
4. `OPENAI_API_KEY`, `OPENAI_API_TOKEN`, `api_key`, `token`, or `openai_api_key` in `auth.json`

You can also override both explicitly:

```bash
~/.codex/skills/image-curl/scripts/generate_image.sh \
  --base-url https://api.example.com/v1 \
  --api-key "$OPENAI_API_KEY" \
  --prompt "A cat" \
  --output ./cat.png
```

Do not commit real API keys to the repository.

### Options

```text
--prompt TEXT          image prompt
--prompt-file FILE     read prompt from file
--output FILE          output image path, required
--model NAME           default: gpt-image-2
--size SIZE            auto or any upstream-supported WIDTHxHEIGHT, for example 1024x1024, 1344x768, 1200x1800
--quality VALUE        default: auto
--format FORMAT        png, jpeg, webp
--moderation VALUE     default: auto
--background VALUE     optional, for example transparent or auto
--metadata FILE        save response metadata with b64_json omitted
--timeout SECONDS      curl timeout, default: 300
--overwrite            allow replacing an existing output file
--dry-run              print redacted request details without calling the API
```

### Request Shape

The script sends a request like this:

```bash
curl -sS --fail-with-body -X POST "$BASE_URL/v1/images/generations" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Cache-Control: no-store, no-cache, max-age=0" \
  -H "Pragma: no-cache" \
  -d '{
    "model": "gpt-image-2",
    "prompt": "A cat",
    "size": "1024x1024",
    "quality": "auto",
    "output_format": "png",
    "moderation": "auto"
  }'
```

### Project Structure

```text
skill_src/
  image-curl/
    SKILL.md
    agents/
      openai.yaml
    scripts/
      generate_image.sh
README.md
```
