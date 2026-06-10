import { tool } from "@opencode-ai/plugin"
import { readFileSync, existsSync, statSync } from "fs"
import { resolve, extname } from "path"
import { homedir } from "os"

function expandPath(filePath: string, cwd: string): string {
  if (filePath.startsWith("~/")) return resolve(homedir(), filePath.slice(2))
  if (filePath.startsWith("/")) return filePath
  return resolve(cwd, filePath)
}

const IMAGE_EXTS = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]
const IMAGE_RE = new RegExp(
  `(?:^|[\\s"'<>|;(])` +
  `([^\\s"'<>|;()]+\\.(${IMAGE_EXTS.join("|")}))` +
  `(?=[\\s"'<>|;)]|$)`,
  "gi"
)

async function imageToBase64(
  filePath: string,
  maxDim: number,
  $: any
): Promise<string | null> {
  try {
    const full = expandPath(filePath, process.cwd())
    if (!existsSync(full)) return null
    const stats = statSync(full)
    const ext = extname(full).slice(1).toLowerCase() || "png"
    const mime = ext === "jpg" ? "jpeg" : ext
    const sizeMB = stats.size / (1024 * 1024)

    if (sizeMB <= 2) {
      const buf = readFileSync(full)
      return `data:image/${mime};base64,${buf.toString("base64")}`
    }
    const out = `/tmp/vision_auto_${Date.now()}.${ext}`
    try {
      await $`convert ${full} -resize ${maxDim}x${maxDim} -quality 85 ${out}`
    } catch (e) {
      if (sizeMB <= 5) {
        const buf = readFileSync(full)
        return `data:image/${mime};base64,${buf.toString("base64")}`
      }
      return null
    }
    if (!existsSync(out)) return null
    const buf = readFileSync(out)
    return `data:image/${mime};base64,${buf.toString("base64")}`
  } catch (e) {
    return null
  }
}

export const VisionAutoPlugin = async ({ $, directory }: any) => {
  function readOpencodeConfig(): { apiKey: string; openaiBaseUrl: string; anthropicBaseUrl: string } {
    const fallback = {
      apiKey: "",
      openaiBaseUrl: "https://coding-intl.dashscope.aliyuncs.com/v1",
      anthropicBaseUrl: "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic"
    }
    try {
      const configPath = resolve(homedir(), ".config/opencode/opencode.json")
      if (!existsSync(configPath)) return fallback
      const config = JSON.parse(readFileSync(configPath, "utf-8"))
      const providers = config.provider || {}
      let apiKey = ""
      let openaiBaseUrl = fallback.openaiBaseUrl
      let anthropicBaseUrl = fallback.anthropicBaseUrl
      for (const [, provider] of Object.entries(providers) as any[]) {
        if (!provider?.options?.apiKey) continue
        const url = provider.options.baseURL || ""
        if (url.includes("dashscope") || url.includes("/openai/v1")) {
          if (!apiKey) apiKey = provider.options.apiKey
          if (url.includes("dashscope")) openaiBaseUrl = url
        }
        if (url.includes("anthropic")) {
          anthropicBaseUrl = url
        }
      }
      return { apiKey, openaiBaseUrl, anthropicBaseUrl }
    } catch (_) {}
    return fallback
  }

  const cfg = readOpencodeConfig()
  const apiKey = cfg.apiKey || process.env.AZURE_FOUNDRY_API_KEY || ""
  const openaiBaseUrl = cfg.openaiBaseUrl || process.env.AZURE_FOUNDRY_BASE_URL || "https://coding-intl.dashscope.aliyuncs.com/v1"
  const anthropicBaseUrl = process.env.AZURE_FOUNDRY_ANTHROPIC_BASE_URL || cfg.anthropicBaseUrl
  const visionModel = process.env.AZURE_FOUNDRY_VISION_MODEL || process.env.VISION_MODEL || "qwen3.7-plus"

  function isClaudeModel(model: string): boolean {
    return model.toLowerCase().startsWith("claude-")
  }

  async function callOpenAIApi(
    endpoint: string,
    model: string,
    prompt: string,
    base64Image: string
  ): Promise<any> {
    const resp = await fetch(
      `${endpoint}/chat/completions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`
        },
        body: JSON.stringify({
          model: model,
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: prompt },
                { type: "image_url", image_url: { url: base64Image } }
              ]
            }
          ],
          max_tokens: 4096
        })
      }
    )
    return resp.json()
  }

  async function callAnthropicApi(
    endpoint: string,
    model: string,
    prompt: string,
    base64Image: string
  ): Promise<any> {
    const mime = base64Image.match(/data:image\/([^;]+)/)?.[1] || "png"
    const base64Data = base64Image.split(",")[1]
    
    const resp = await fetch(
      `${endpoint.replace("/openai/v1", "")}/anthropic/v1/messages`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01"
        },
        body: JSON.stringify({
          model: model,
          max_tokens: 4096,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: `image/${mime}`,
                    data: base64Data
                  }
                },
                {
                  type: "text",
                  text: prompt
                }
              ]
            }
          ]
        })
      }
    )
    return resp.json()
  }

  return {
    tool: {
      vision_screenshot: tool({
        description:
          "Capture browser screenshot using Playwright. Returns base64 data URI. Requires: npm install -g playwright",
        args: {
          url: tool.schema.string(),
          fullPage: tool.schema.boolean().optional(),
        },
        async execute(args: any) {
          const out = `/tmp/screenshot_${Date.now()}.png`
          try {
            const fp = args.fullPage ? "--full-page" : ""
            await $`npx playwright screenshot ${fp} ${args.url} ${out}`
            if (!existsSync(out)) throw new Error("Screenshot not created")
            const buf = readFileSync(out)
            return `data:image/png;base64,${buf.toString("base64")}`
          } catch (e: any) {
            return `Screenshot failed: ${e.message || e}. Install Playwright: npm install -g playwright`
          }
        },
      }),

      vision_file_to_base64: tool({
        description:
          "Convert an image file to base64 data URI for vision models. Supports ~ for home directory.",
        args: {
          path: tool.schema.string(),
          maxSize: tool.schema.number().optional(),
        },
        async execute(args: any) {
          const result = await imageToBase64(
            args.path,
            args.maxSize || 800,
            $
          )
          return result || `Error: Could not process ${args.path}`
        },
      }),

      vision_analyze: tool({
        description: "Analyze an image using a vision model. Converts the image to base64 and sends it to a vision-capable API for analysis. Supports ~ for home directory. Supports both Claude (Anthropic) and OpenAI-compatible models.",
        args: {
          path: tool.schema.string(),
          prompt: tool.schema.string().optional(),
          maxSize: tool.schema.number().optional(),
        },
        async execute(args: any, _: any) {
          try {
            const base64Image = await imageToBase64(
              args.path,
              args.maxSize || 800,
              $
            )
            if (!base64Image) {
              return `Error: Could not process image at ${args.path}`
            }

            const promptText = args.prompt || "Describe this image in detail"
            const modelToUse = visionModel
            
            try {
              let data
              if (isClaudeModel(modelToUse)) {
                data = await callAnthropicApi(anthropicBaseUrl, modelToUse, promptText, base64Image)
                const content = data.content?.[0]?.text
                if (!content) {
                  return `API Error: ${JSON.stringify(data.error || data)}`
                }
                return content
              } else {
                data = await callOpenAIApi(openaiBaseUrl, modelToUse, promptText, base64Image)
                const content = data.choices?.[0]?.message?.content
                if (!content) {
                  return `API Error: ${JSON.stringify(data.error || data)}`
                }
                return content
              }
            } catch (apiError: any) {
              return `API call failed: ${apiError.message}. Base64 length: ${base64Image.length}. Try using vision_file_to_base64 then calling the API manually.`
            }
          } catch (e: any) {
            return `Analysis failed: ${e.message}`
          }
        },
      }),
    },

    "message.updated": async (input: any, output: any) => {
      try {
        const msg = input.message
        if (!msg || msg.role !== "user") return
        const content = msg.content
        if (!content || typeof content !== "string") return
        if (content.includes("[VISION AUTO:") || content.includes("data:image/"))
          return
        const images: { original: string; full: string }[] = []
        let m
        while ((m = IMAGE_RE.exec(content)) !== null) {
          const full = expandPath(m[1], directory || process.cwd())
          if (existsSync(full)) images.push({ original: m[1], full })
        }
        if (images.length === 0) return
        const processed: { original: string; base64: string }[] = []
        for (const img of images) {
          const b64 = await imageToBase64(img.full, 800, $)
          if (b64) processed.push({ original: img.original, base64: b64 })
        }
        if (processed.length === 0) return
        try {
          if (output && output.message) {
            const parts: any[] = [{ type: "text", text: content }]
            for (const p of processed) {
              parts.push({
                type: "image_url",
                image_url: { url: p.base64 },
              })
            }
            output.message.content = parts
            console.log(
              `[vision-auto] Injected ${processed.length} image(s) into message`
            )
          }
        } catch (e) {
          const info = processed.map((p) => `- ${p.original}`).join("\n")
          if (output && output.message && typeof output.message.content === "string") {
            output.message.content +=
              `\n\n[VISION AUTO: Detected images]\n${info}\nUse vision_file_to_base64 tool to analyze them.`
          }
        }
      } catch (e) {
        console.error("[vision-auto] Error:", e)
      }
    },
  }
}
