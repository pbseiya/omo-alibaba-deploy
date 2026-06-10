#!/bin/bash
set -e

# ============================================================
# OMO (Oh My OpenAgent) Deployment Script
# Deploys OpenCode + OMO plugin + custom config to a new machine
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

CONFIG_DIR="${CONFIG_DIR:-.}"
TARGET_DIR="$HOME/.config/opencode"
ENV_FILE="$CONFIG_DIR/.env"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --config-dir DIR    Path to config files (default: current dir)"
  echo "  --dry-run           Show what would be done without making changes"
  echo "  --skip-install      Skip OpenCode/Bun installation"
  echo "  --skip-omo          Skip OMO plugin installation"
  echo "  --help              Show this help"
  echo ""
  echo "Required files in config directory:"
  echo "  opencode.json"
  echo "  oh-my-openagent.json"
  echo "  plugins/vision-auto.ts"
  echo ""
  echo "Examples:"
  echo "  $0 --config-dir /path/to/configs"
  echo "  $0 --config-dir . --dry-run"
}

DRY_RUN=false
SKIP_INSTALL=false
SKIP_OMO=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    --skip-omo) SKIP_OMO=true; shift ;;
    --help) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

echo ""
echo "============================================"
echo "  OMO Deployment Script"
echo "============================================"
echo ""

if [ "$DRY_RUN" = true ]; then
  log_warn "DRY RUN MODE - no changes will be made"
  echo ""
fi

# ============================================================
# Step 0: Load .env file if present
# ============================================================
if [ -f "$ENV_FILE" ]; then
  log_info "Loading environment variables from $ENV_FILE"
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY] Would load: $ENV_FILE"
  else
    set -a
    source "$ENV_FILE"
    set +a
    log_ok "Environment variables loaded"
  fi
elif [ -f "$CONFIG_DIR/.env_example" ]; then
  log_warn ".env file not found. Copy .env_example to .env and fill in your values:"
  log_info "  cp $CONFIG_DIR/.env_example $CONFIG_DIR/.env"
  log_info "  # Edit .env with your actual API keys"
  if [ "$DRY_RUN" = false ]; then
    log_info "Creating .env from template..."
    cp "$CONFIG_DIR/.env_example" "$CONFIG_DIR/.env"
    log_warn "Please edit $CONFIG_DIR/.env with your actual API keys before running again"
    exit 1
  fi
fi

echo ""

# ============================================================
# Step 1: Check prerequisites
# ============================================================
log_info "Checking prerequisites..."

# Check OS
OS=$(uname -s)
ARCH=$(uname -m)
log_info "OS: $OS ($ARCH)"

# Check Node.js
if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  log_ok "Node.js: $NODE_VER"
else
  if [ "$SKIP_INSTALL" = true ]; then
    log_error "Node.js not found. Install Node.js >= 18 first."
    exit 1
  fi
  log_warn "Node.js not found. Will install via OpenCode installer."
fi

# Check Bun
if command -v bun &>/dev/null; then
  BUN_VER=$(bun --version)
  log_ok "Bun: $BUN_VER"
else
  if [ "$SKIP_INSTALL" = true ]; then
    log_error "Bun not found. Install Bun first: curl -fsSL https://bun.sh/install | bash"
    exit 1
  fi
  log_warn "Bun not found. Will install."
fi

# Check OpenCode
if command -v opencode &>/dev/null; then
  OC_VER=$(opencode --version 2>/dev/null || echo "unknown")
  log_ok "OpenCode: $OC_VER"
else
  if [ "$SKIP_INSTALL" = true ]; then
    log_error "OpenCode not found."
    exit 1
  fi
  log_warn "OpenCode not found. Will install."
fi

echo ""

# ============================================================
# Step 2: Install OpenCode
# ============================================================
if [ "$SKIP_INSTALL" = false ]; then
  log_info "Installing/updating OpenCode..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY] Would run: curl -fsSL https://opencode.ai/install | bash"
  else
    curl -fsSL https://opencode.ai/install | bash
    log_ok "OpenCode installed: $(opencode --version)"
  fi
else
  log_info "Skipping OpenCode installation."
fi

echo ""

# ============================================================
# Step 3: Install Bun (if needed)
# ============================================================
if [ "$SKIP_INSTALL" = false ] && ! command -v bun &>/dev/null; then
  log_info "Installing Bun..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY] Would run: curl -fsSL https://bun.sh/install | bash"
  else
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    log_ok "Bun installed: $(bun --version)"
  fi
fi

echo ""

# ============================================================
# Step 4: Validate config files exist
# ============================================================
log_info "Validating config files..."

REQUIRED_FILES=(
  "opencode.json"
  "oh-my-openagent.json"
  "plugins/vision-auto.ts"
)

MISSING=false
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$CONFIG_DIR/$f" ]; then
    SIZE=$(wc -c < "$CONFIG_DIR/$f")
    log_ok "Found: $f ($SIZE bytes)"
  else
    log_error "Missing: $f (expected at $CONFIG_DIR/$f)"
    MISSING=true
  fi
done

# Optional files
for f in mcp.json; do
  if [ -f "$CONFIG_DIR/$f" ]; then
    SIZE=$(wc -c < "$CONFIG_DIR/$f")
    log_ok "Found (optional): $f ($SIZE bytes)"
  fi
done

if [ "$MISSING" = true ]; then
  log_error "Missing required config files. Use --config-dir to specify path."
  exit 1
fi

echo ""

# ============================================================
# Step 5: Deploy config files
# ============================================================
log_info "Deploying config files to $TARGET_DIR..."

if [ "$DRY_RUN" = true ]; then
  log_info "[DRY] Would create directory: $TARGET_DIR"
  log_info "[DRY] Would copy config files"
else
  # Backup existing config if present
  if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/opencode.json" ]; then
    BACKUP_DIR="$TARGET_DIR/.backup-$(date +%Y%m%d_%H%M%S)"
    log_warn "Backing up existing config to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -r "$TARGET_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
    log_ok "Backup created"
  fi

  # Create target directory
  mkdir -p "$TARGET_DIR/plugins"

  # Copy config files
  cp "$CONFIG_DIR/opencode.json" "$TARGET_DIR/opencode.json"
  log_ok "Copied: opencode.json"

  cp "$CONFIG_DIR/oh-my-openagent.json" "$TARGET_DIR/oh-my-openagent.json"
  log_ok "Copied: oh-my-openagent.json"

  cp "$CONFIG_DIR/plugins/vision-auto.ts" "$TARGET_DIR/plugins/vision-auto.ts"
  log_ok "Copied: plugins/vision-auto.ts"

  # Copy optional files
  if [ -f "$CONFIG_DIR/mcp.json" ]; then
    cp "$CONFIG_DIR/mcp.json" "$TARGET_DIR/mcp.json"
    log_ok "Copied: mcp.json"
  fi

  # Copy skills if present
  if [ -d "$CONFIG_DIR/skills" ]; then
    mkdir -p "$TARGET_DIR/skills"
    cp -r "$CONFIG_DIR/skills/"* "$TARGET_DIR/skills/" 2>/dev/null || true
    log_ok "Copied: skills/"
  fi
fi

echo ""

# ============================================================
# Step 6: Install dependencies
# ============================================================
if [ "$DRY_RUN" = true ]; then
  log_info "[DRY] Would run: cd $TARGET_DIR && npm install"
else
  log_info "Installing npm dependencies..."
  cd "$TARGET_DIR"
  if [ -f package.json ]; then
    npm install 2>&1 | tail -3
    log_ok "npm dependencies installed"
  else
    log_warn "No package.json found, skipping npm install"
  fi
fi

echo ""

# ============================================================
# Step 7: Install OMO plugin
# ============================================================
if [ "$SKIP_OMO" = false ]; then
  log_info "Checking OMO plugin..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY] Would run: bunx oh-my-openagent doctor"
  else
    if bunx oh-my-openagent doctor 2>/dev/null; then
      log_ok "OMO plugin is working"
    else
      log_warn "OMO plugin not installed. Run manually:"
      log_info "  bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no"
    fi
  fi
else
  log_info "Skipping OMO plugin check."
fi

echo ""

# ============================================================
# Step 8: Verify
# ============================================================
log_info "Verifying deployment..."

if [ "$DRY_RUN" = true ]; then
  log_info "[DRY] Would verify config"
else
  # Check config is valid JSON
  python3 -c "import json; json.load(open('$TARGET_DIR/opencode.json'))" 2>/dev/null && log_ok "opencode.json: valid JSON" || log_error "opencode.json: invalid JSON"
  python3 -c "import json; json.load(open('$TARGET_DIR/oh-my-openagent.json'))" 2>/dev/null && log_ok "oh-my-openagent.json: valid JSON" || log_error "oh-my-openagent.json: invalid JSON"

  # Check plugin file exists
  [ -f "$TARGET_DIR/plugins/vision-auto.ts" ] && log_ok "vision-auto.ts: present" || log_error "vision-auto.ts: missing"

  # Show version
  log_ok "OpenCode: $(opencode --version)"

  echo ""
  echo "============================================"
  echo "  Deployment Complete!"
  echo "============================================"
  echo ""
  log_info "Run 'opencode' to start."
  log_info "If OMO plugin is not loaded, run:"
  log_info "  bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no"
fi

echo ""
log_ok "Done!"
