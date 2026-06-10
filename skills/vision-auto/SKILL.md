---
name: vision-auto
description: "Auto-detect and process images in messages for vision models. Provides browser screenshot and image-to-base64 tools."
license: MIT
metadata:
  author: user
  version: "1.0.0"
---

## Vision Auto Plugin

When users reference image files in their messages, the vision-auto plugin automatically detects and processes them for vision-capable models.

### Auto-Detection

The plugin scans user messages for image file paths (png, jpg, jpeg, gif, webp, bmp) and automatically:
1. Reads the image file
2. Resizes if larger than 2MB (using ImageMagick or raw)
3. Converts to base64 data URI
4. Injects as multimodal content (image_url type)

### Important Note

**OpenCode chat interface currently does not support image attachments.** To analyze images, you must:

**Option A: Use `vision_analyze` tool** (Recommended)
- One-step: converts image + calls vision API in a single tool call
- Works around the OpenCode attachment limitation

**Option B: Reference image path in text**
- Type the image path in your message, e.g. `~/Downloads/image.png`
- Plugin will auto-convert and inject base64 into the message

### Available Tools

**vision_analyze** (NEW - One-step analysis)
- Args: 
  - `path` (string) - Image file path, supports `~` for home directory
  - `prompt` (optional string) - Custom analysis prompt (default: "Describe this image in detail")
  - `maxSize` (optional number) - Max dimension for resize (default: 800)
- Returns: Text analysis from vision model
- Example: `vision_analyze({ path: "~/Downloads/chart.png", prompt: "What does this chart show?" })`

**vision_file_to_base64**
- Args: `path` (string), `maxSize` (optional number, default 800)
- Returns: Base64 data URI
- Use when: You need the base64 string for manual API calls

**vision_screenshot**
- Args: `url` (string), `fullPage` (optional boolean)
- Returns: Base64 data URI of webpage screenshot
- Requires: Playwright installed (`npm install -g playwright`)

### How to Use

**For local image files:**
```
# One-step analysis (recommended)
vision_analyze({ path: "~/Downloads/report.png" })

# With custom prompt
vision_analyze({ 
  path: "~/Downloads/chart.png", 
  prompt: "Summarize the key trends in this chart" 
})
```

**For browser screenshots:**
```
# One-step: screenshot + analyze
vision_analyze({ 
  path: vision_screenshot({ url: "https://example.com" }),
  prompt: "Describe the layout and content of this webpage" 
})
```

### Supported Models

This works with vision-capable models:
- GPT 5.4 / 5.4-mini / 5.4-nano
- Kimi K2.5 / K2.6
- Claude Sonnet 4.6 / Opus 4.6 / Haiku 4.5

### Important Notes

- **Kimi models**: Require `max_tokens: 4096` when processing images due to reasoning content generation
- **Base64 strings are large**: 800x800 image ~1MB base64. Keep original images reasonable in size
- **ImageMagick**: Used for resizing. If not available, raw files under 5MB are used
- **SVG**: Not supported - convert to PNG first

### Fallback Workflow (if auto-detection fails)

```
1. User: "อธิบายภาพนี้"
2. [System fails to auto-detect]
3. Model: "ใช้ vision_analyze tool เพื่อวิเคราะห์ภาพครับ/ค่ะ"
4. User: vision_analyze({ path: "~/Downloads/image.png" })
5. [Tool returns analysis directly]
```
