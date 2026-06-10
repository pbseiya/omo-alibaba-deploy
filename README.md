# OMO Deployment Package

Oh My OpenAgent (OMO) configuration for OpenCode with Alibaba Coding Plan.

## Overview

This package contains a complete OpenCode + OMO plugin configuration optimized for **Alibaba Coding Plan** models. It includes:

- **10 models** from Alibaba Coding Plan (Qwen, GLM, Kimi, MiniMax)
- **3 API keys** for automatic fallback rotation
- **Vision support** for 4 models (qwen3.7-plus, qwen3.6-plus, qwen3.5-plus, kimi-k2.5)
- **12 discipline agents** with model-specific assignments
- **8 task categories** with optimized model routing

## Quick Start

### Linux/macOS

```bash
tar -xzf omo-config.tar.gz
cd omo-config
cp .env_example .env
# Edit .env with your actual API keys
bash deploy-omo.sh --config-dir .
```

### Windows (PowerShell)

```powershell
tar -xzf omo-config.tar.gz
cd omo-config
Copy-Item .env_example .env
# Edit .env with your actual API keys
.\deploy-omo.ps1 -ConfigDir .
```

If PowerShell blocks the script:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy-omo.ps1 -ConfigDir .
```

## Prerequisites

- **Node.js** >= 18 (auto-installed if missing)
- **Bun** (auto-installed if missing)
- **OpenCode** (auto-installed if missing)

## Configuration

### API Keys

Copy `.env_example` to `.env` and fill in your values:

| Variable | Required | Description |
|---|---|---|
| `ALIBABA_API_KEY` | Yes | Primary Alibaba Coding Plan API key |
| `ALIBABA_API_KEY_SPARE` | No | Fallback key when primary is exhausted |
| `ALIBABA_API_KEY_LAST` | No | Last resort fallback key |
| `TAVILY_API_KEY` | No | Tavily web search API key |
| `VISION_MODEL` | No | Vision model (default: `qwen3.7-plus`) |

### Models

| Model | Capabilities | Used By |
|---|---|---|
| `qwen3.7-plus` | text, deep-thinking, **vision** | sisyphus, prometheus, oracle, ultrabrain |
| `qwen3.6-plus` | text, deep-thinking, **vision** | atlas, metis, multimodal-looker, deep, artistry |
| `qwen3.5-plus` | text, deep-thinking, **vision** | writing |
| `qwen3-max-2026-01-23` | text, deep-thinking | (fallback) |
| `qwen3-coder-next` | text, coding | hephaestus, momus, code-reviewer |
| `qwen3-coder-plus` | text, coding | (fallback) |
| `glm-5` | text, deep-thinking | (fallback) |
| `glm-4.7` | text, deep-thinking | sisyphus-junior, quick, unspecified-low |
| `kimi-k2.5` | text, deep-thinking, **vision** | (fallback vision) |
| `MiniMax-M2.5` | text, deep-thinking | explore, librarian |

### Agent Model Mapping

| Agent | Primary Model | Role |
|---|---|---|
| **sisyphus** | qwen3.7-plus | Main orchestrator |
| **prometheus** | qwen3.7-plus | Strategic planner |
| **oracle** | qwen3.7-plus | Architecture/debugging |
| **atlas** | qwen3.6-plus | Todo orchestrator |
| **metis** | qwen3.6-plus | Plan consultant |
| **multimodal-looker** | qwen3.6-plus | Vision/PDF analysis |
| **hephaestus** | qwen3-coder-next | Deep autonomous coder |
| **momus** | qwen3-coder-next | High-accuracy reviewer |
| **code-reviewer** | qwen3-coder-next | Code quality review |
| **explore** | MiniMax-M2.5 | Fast codebase grep |
| **librarian** | MiniMax-M2.5 | External docs search |
| **sisyphus-junior** | glm-4.7 | Lightweight executor |

### Category Model Mapping

| Category | Primary Model | Use Case |
|---|---|---|
| **ultrabrain** | qwen3.7-plus | Hard logic, architecture |
| **visual-engineering** | qwen3.7-plus | Frontend, UI/UX |
| **deep** | qwen3.7-plus | Autonomous research |
| **artistry** | qwen3.7-plus | Creative approaches |
| **unspecified-high** | qwen3.7-plus | Complex work |
| **writing** | qwen3-max-2026-01-23 | Documentation, prose |
| **quick** | MiniMax-M2.5 | Trivial tasks |
| **unspecified-low** | MiniMax-M2.5 | Low effort tasks |

### Fallback Chain

Every agent/category has **26 fallback models** that rotate through 3 API keys:

```
primary → spare → last → next model spare → next model last → ...
```

### Runtime Fallback (OMO defaults)

| Setting | Value | Meaning |
|---|---|---|
| `timeout_seconds` | 30 | Max wait for model response before fallback |
| `cooldown_seconds` | 60 | Wait between retrying a failed model |
| `max_fallback_attempts` | 3 | Max fallback tries before giving up |
| `retry_on_errors` | 400,401,403,404,429,500,502,503,504 | HTTP errors that trigger fallback |
| `notify_on_fallback` | true | Show toast when model switches |

**Max total wait:** 30s timeout + 60s cooldown × 3 attempts = ~3.5 minutes

> **CRITICAL:** `timeout_seconds: 0` DISABLES the timeout watchdog entirely.
> This causes OpenCode to wait indefinitely on hung requests. Never set to 0.
> Source: [message-update-handler.ts#L24](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/packages/omo-opencode/src/hooks/runtime-fallback/message-update-handler.ts#L24)

## Script Options

| Option | Linux/macOS | Windows | Description |
|---|---|---|---|
| Config dir | `--config-dir DIR` | `-ConfigDir DIR` | Path to config files |
| Dry run | `--dry-run` | `-DryRun` | Test without changes |
| Skip install | `--skip-install` | `-SkipInstall` | Skip OpenCode/Bun install |
| Skip OMO | `--skip-omo` | `-SkipOmo` | Skip OMO plugin check |
| Help | `--help` | `-Help` | Show help |

## Post-Deploy

After deployment:

```bash
opencode
```

If OMO plugin is not loaded:

```bash
bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no
```

## File Structure

```
omo-config/
├── deploy-omo.sh              # Linux/macOS deployment script
├── deploy-omo.ps1             # Windows deployment script
├── .env_example               # API key template (copy to .env)
├── opencode.json              # Provider config with env var references
├── oh-my-openagent.json       # Agent/category model mapping
├── plugins/
│   └── vision-auto.ts         # Vision plugin (user plugin, not overwritten by updates)
├── mcp.json                   # MCP server config (Tavily)
├── skills/
│   ── vision-auto/
│       └── SKILL.md           # Vision skill definition
├── README.md                  # This file
└── AGENTS.md                  # AI agent deployment guide
```

## Notes

- Config files use `{env:VAR}` syntax — values are resolved from environment variables at runtime
- Vision plugin (`vision-auto.ts`) is a user plugin — **not overwritten** by OpenCode updates
- All models use Alibaba Coding Plan via DashScope API (`https://coding-intl.dashscope.aliyuncs.com/v1`)
- API key rotation handles quota exhaustion automatically via fallback chains
- Runtime fallback uses OMO defaults: 3 attempts, 60s cooldown, 30s timeout

## Troubleshooting

### OMO plugin not loaded
```bash
bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no
```

### Vision not working
1. Ensure `attachment: true` is set for vision models in `opencode.json`
2. Ensure `modalities.input` includes `"image"`
3. Restart OpenCode after config changes

### API key errors
1. Check `.env` file exists and has correct keys
2. Verify keys work: `curl -H "Authorization: Bearer $ALIBABA_API_KEY" https://coding-intl.dashscope.aliyuncs.com/v1/models`
3. Check fallback chain in `oh-my-openagent.json`

### Config not loading
```bash
opencode debug config
```
