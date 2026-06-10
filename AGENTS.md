# AGENTS.md - OMO Deployment Instructions

This document provides step-by-step instructions for AI agents to deploy the OMO (Oh My OpenAgent) configuration.

## Task: Deploy OMO Configuration

### Goal
Deploy a complete OpenCode + OMO plugin configuration with Alibaba Coding Plan models on the target machine.

### Success Criteria
- OpenCode is installed and running (version >= 1.17.0)
- OMO plugin is loaded and functional
- All 10 Alibaba Coding Plan models are available
- Vision capability works for qwen3.7-plus, qwen3.6-plus, qwen3.5-plus, kimi-k2.5
- API key fallback rotation is configured (3 keys)
- Config files are valid JSON

---

## Step-by-Step Instructions

### Step 1: Check Prerequisites

```bash
# Check if OpenCode is installed
opencode --version

# Check if Node.js is available
node --version

# Check if Bun is available
bun --version
```

**If any are missing:** Proceed to Step 2 (auto-install).
**If all present:** Skip to Step 3.

---

### Step 2: Install Missing Prerequisites

```bash
# Install OpenCode (latest)
curl -fsSL https://opencode.ai/install | bash

# Install Bun (if missing)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc  # or source ~/.zshrc

# Install Node.js (if missing, via package manager)
# Ubuntu/Debian:
# curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
# sudo apt-get install -y nodejs

# macOS:
# brew install node
```

Verify installations:
```bash
opencode --version  # Should be >= 1.17.0
node --version      # Should be >= 18
bun --version
```

---

### Step 3: Setup API Keys

The config files use environment variable references (`{env:VAR}`). You MUST set these before deployment.

```bash
# Navigate to config directory
cd /path/to/omo-config

# Copy template
cp .env_example .env

# Edit .env with actual API keys
# Required: ALIBABA_API_KEY
# Optional: ALIBABA_API_KEY_SPARE, ALIBABA_API_KEY_LAST, TAVILY_API_KEY
```

**Important:** The `.env` file must contain valid API keys. Without `ALIBABA_API_KEY`, the deployment will fail.

To load environment variables in current session:
```bash
set -a
source .env
set +a
```

---

### Step 4: Deploy Configuration

#### Option A: Using deploy script (recommended)

```bash
# Linux/macOS
bash deploy-omo.sh --config-dir .

# Windows (PowerShell)
.\deploy-omo.ps1 -ConfigDir .
```

#### Option B: Manual deployment

```bash
# Create target directory
mkdir -p ~/.config/opencode/plugins

# Copy config files
cp opencode.json ~/.config/opencode/
cp oh-my-openagent.json ~/.config/opencode/
cp plugins/vision-auto.ts ~/.config/opencode/plugins/
cp mcp.json ~/.config/opencode/ 2>/dev/null || true

# Copy skills if present
if [ -d skills ]; then
    mkdir -p ~/.config/opencode/skills
    cp -r skills/* ~/.config/opencode/skills/
fi

# Install npm dependencies
cd ~/.config/opencode
npm install
```

---

### Step 5: Verify Deployment

```bash
# Check config is valid JSON
python3 -c "import json; json.load(open('$HOME/.config/opencode/opencode.json'))"
python3 -c "import json; json.load(open('$HOME/.config/opencode/oh-my-openagent.json'))"

# Check plugin file exists
ls -la ~/.config/opencode/plugins/vision-auto.ts

# Check OpenCode version
opencode --version

# Check models are available
opencode models | grep "acp/"

# Check OMO plugin
bunx oh-my-openagent doctor
```

**Expected output:**
- `opencode.json: valid JSON`
- `oh-my-openagent.json: valid JSON`
- `vision-auto.ts: present`
- `OpenCode: 1.17.0` (or higher)
- Models listed: `acp/qwen3.7-plus`, `acp/qwen3.6-plus`, etc.

---

### Step 6: Start OpenCode

```bash
opencode
```

In the OpenCode TUI:
1. Press `/models` to see available models
2. Verify `acp/qwen3.7-plus` is listed
3. Test vision by attaching an image

---

### Step 7: Troubleshooting

#### OMO plugin not loaded
```bash
bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no
```

#### Vision not working
Check that `opencode.json` has:
```json
{
  "provider": {
    "acp": {
      "models": {
        "qwen3.7-plus": {
          "attachment": true,
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          }
        }
      }
    }
  }
}
```

#### API key errors
```bash
# Test API key directly
curl -H "Authorization: Bearer $ALIBABA_API_KEY" \
  https://coding-intl.dashscope.aliyuncs.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.7-plus","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
```

#### Config not loading
```bash
opencode debug config
```

---

## Configuration Details

### Provider Setup

Three providers are configured for API key rotation:

| Provider | Env Var | Role |
|---|---|---|
| `acp` | `ALIBABA_API_KEY` | Primary |
| `acp-spare` | `ALIBABA_API_KEY_SPARE` | Fallback 1 |
| `acp-last` | `ALIBABA_API_KEY_LAST` | Fallback 2 |

All use the same base URL: `https://coding-intl.dashscope.aliyuncs.com/v1`

### Vision Models

Four models support image input:

```json
{
  "attachment": true,
  "modalities": {
    "input": ["text", "image"],
    "output": ["text"]
  }
}
```

Models: `qwen3.7-plus`, `qwen3.6-plus`, `qwen3.5-plus`, `kimi-k2.5`

### Fallback Chain

Each agent/category has 26 fallback models:
- Primary model → spare key → last key → next model spare → next model last → ...
- Runtime fallback: OMO defaults (3 attempts, 60s cooldown, 30s timeout)

### Runtime Fallback Configuration

Runtime fallback is in `oh-my-openagent.json` under `runtime_fallback`.

**OMO Default Values** (from [constants.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/packages/omo-opencode/src/hooks/runtime-fallback/constants.ts)):

```json
{
  "runtime_fallback": {
    "enabled": true,
    "retry_on_errors": [400, 401, 403, 404, 429, 500, 502, 503, 504],
    "max_fallback_attempts": 3,
    "cooldown_seconds": 60,
    "timeout_seconds": 30,
    "notify_on_fallback": true
  }
}
```

| Setting | Default | Meaning |
|---|---|---|
| `timeout_seconds` | 30 | Max wait for response before triggering fallback. **Must be > 0** — setting to 0 DISABLES the timeout watchdog ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/packages/omo-opencode/src/hooks/runtime-fallback/message-update-handler.ts#L24)) |
| `cooldown_seconds` | 60 | Wait between retrying a failed model |
| `max_fallback_attempts` | 3 | Max fallback tries before giving up |
| `retry_on_errors` | 429,500,502,503,504 | HTTP status codes that trigger fallback |
| `notify_on_fallback` | true | Show notification when model switches |

**Max total wait:** 30s timeout + 60s cooldown × 3 attempts = ~3.5 minutes

**CRITICAL:** Never set `timeout_seconds: 0`. This disables the timeout watchdog and causes OpenCode to wait indefinitely on hung requests, resulting in 30+ minute hangs with no response.

### Disabled Providers

These providers are disabled to avoid conflicts:
- `anthropic`, `azure`, `azure-cognitive-services`
- `openai`, `copilot`, `gemini`
- `groq`, `xai`, `deepseek`, `openrouter`, `mistral`
- `alibaba`, `alibaba-cn`, `alibaba-coding-plan` (built-in)

---

## File Reference

| File | Purpose |
|---|---|
| `opencode.json` | Provider config, models, vision capabilities, disabled providers |
| `oh-my-openagent.json` | Agent models, category models, fallback chains, team mode |
| `plugins/vision-auto.ts` | Vision plugin for image analysis via API |
| `mcp.json` | Tavily MCP server for web search |
| `skills/vision-auto/SKILL.md` | Vision skill definition |
| `.env_example` | API key template |
| `deploy-omo.sh` | Linux/macOS deployment script |
| `deploy-omo.ps1` | Windows deployment script |

---

## Notes for Agents

1. **Always check if `.env` exists** before deploying. If not, copy from `.env_example` and prompt user to fill in API keys.
2. **Backup existing config** before overwriting (deploy scripts do this automatically).
3. **Verify JSON validity** after copying config files.
4. **Test vision** by attaching an image after deployment.
5. **If OMO plugin fails**, run the install command manually.
6. **Environment variables** must be loaded before starting OpenCode.
