# ============================================================
# OMO (Oh My OpenAgent) Deployment Script - Windows
# Deploys OpenCode + OMO plugin + custom config to a new Windows machine
# ============================================================

param(
    [string]$ConfigDir = ".",
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$SkipOmo,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\deploy-omo.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -ConfigDir DIR    Path to config files (default: current dir)"
    Write-Host "  -DryRun           Show what would be done without making changes"
    Write-Host "  -SkipInstall      Skip OpenCode installation"
    Write-Host "  -SkipOmo          Skip OMO plugin installation"
    Write-Host "  -Help             Show this help"
    exit 0
}

$ErrorActionPreference = "Stop"

$EnvFile = Join-Path $ConfigDir ".env"

function Log-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Log-Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }
function Log-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Log-Error($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

$TargetDir = "$env:USERPROFILE\.config\opencode"

Write-Host ""
Write-Host "============================================"
Write-Host "  OMO Deployment Script (Windows)"
Write-Host "============================================"
Write-Host ""

if ($DryRun) {
    Log-Warn "DRY RUN MODE - no changes will be made"
    Write-Host ""
}

# ============================================================
# Step 0: Load .env file if present
# ============================================================
if (Test-Path $EnvFile) {
    Log-Info "Loading environment variables from $EnvFile"
    if (-not $DryRun) {
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
                Set-Item -Path "env:$name" -Value $value
            }
        }
        Log-Ok "Environment variables loaded"
    }
} elseif (Test-Path (Join-Path $ConfigDir ".env_example")) {
    Log-Warn ".env file not found. Copy .env_example to .env and fill in your values:"
    Log-Info "  Copy-Item .env_example .env"
    Log-Info "  # Edit .env with your actual API keys"
    if (-not $DryRun) {
        Log-Info "Creating .env from template..."
        Copy-Item (Join-Path $ConfigDir ".env_example") $EnvFile
        Log-Warn "Please edit $EnvFile with your actual API keys before running again"
        exit 1
    }
}

Write-Host ""

# ============================================================
# Step 1: Check prerequisites
# ============================================================
Log-Info "Checking prerequisites..."

# Check Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVer = node --version
    Log-Ok "Node.js: $nodeVer"
} else {
    if ($SkipInstall) {
        Log-Error "Node.js not found. Install Node.js >= 18 first."
        exit 1
    }
    Log-Warn "Node.js not found. Will install via OpenCode installer."
}

# Check Bun
if (Get-Command bun -ErrorAction SilentlyContinue) {
    $bunVer = bun --version
    Log-Ok "Bun: $bunVer"
} else {
    if ($SkipInstall) {
        Log-Error "Bun not found. Install Bun first."
        exit 1
    }
    Log-Warn "Bun not found. Will install."
}

# Check OpenCode
if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $ocVer = opencode --version 2>$null
    Log-Ok "OpenCode: $ocVer"
} else {
    if ($SkipInstall) {
        Log-Error "OpenCode not found."
        exit 1
    }
    Log-Warn "OpenCode not found. Will install."
}

Write-Host ""

# ============================================================
# Step 2: Install OpenCode
# ============================================================
if (-not $SkipInstall) {
    Log-Info "Installing/updating OpenCode..."
    if ($DryRun) {
        Log-Info "[DRY] Would download and install OpenCode"
    } else {
        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Log-Info "Installing via winget..."
            winget install --id Anomaly.OpenCode -e --accept-package-agreements --accept-source-agreements 2>$null
            if ($LASTEXITCODE -ne 0) {
                Log-Warn "winget install failed, trying npm..."
                npm install -g opencode-ai@latest
            }
        } else {
            Log-Info "Installing via npm..."
            npm install -g opencode-ai@latest
        }
        $newVer = opencode --version 2>$null
        Log-Ok "OpenCode installed: $newVer"
    }
} else {
    Log-Info "Skipping OpenCode installation."
}

Write-Host ""

# ============================================================
# Step 3: Install Bun (if needed)
# ============================================================
if (-not $SkipInstall -and -not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Log-Info "Installing Bun..."
    if ($DryRun) {
        Log-Info "[DRY] Would install Bun via npm"
    } else {
        npm install -g bun
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Log-Ok "Bun installed: $(bun --version)"
    }
}

Write-Host ""

# ============================================================
# Step 4: Validate config files exist
# ============================================================
Log-Info "Validating config files..."

$RequiredFiles = @(
    "opencode.json",
    "oh-my-openagent.json",
    "plugins\vision-auto.ts"
)

$Missing = $false
foreach ($f in $RequiredFiles) {
    $fullPath = Join-Path $ConfigDir $f
    if (Test-Path $fullPath) {
        $size = (Get-Item $fullPath).Length
        Log-Ok "Found: $f ($size bytes)"
    } else {
        Log-Error "Missing: $f (expected at $fullPath)"
        $Missing = $true
    }
}

# Optional files
$OptionalFiles = @("mcp.json")
foreach ($f in $OptionalFiles) {
    $fullPath = Join-Path $ConfigDir $f
    if (Test-Path $fullPath) {
        $size = (Get-Item $fullPath).Length
        Log-Ok "Found (optional): $f ($size bytes)"
    }
}

if ($Missing) {
    Log-Error "Missing required config files. Use -ConfigDir to specify path."
    exit 1
}

Write-Host ""

# ============================================================
# Step 5: Deploy config files
# ============================================================
Log-Info "Deploying config files to $TargetDir..."

if ($DryRun) {
    Log-Info "[DRY] Would create directory: $TargetDir"
    Log-Info "[DRY] Would copy config files"
} else {
    # Backup existing config if present
    if ((Test-Path $TargetDir) -and (Test-Path "$TargetDir\opencode.json")) {
        $BackupDir = "$TargetDir\.backup-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Log-Warn "Backing up existing config to $BackupDir"
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Get-ChildItem "$TargetDir\*" -Exclude ".backup-*" | Copy-Item -Destination $BackupDir -Recurse -Force
        Log-Ok "Backup created"
    }

    # Create target directory
    New-Item -ItemType Directory -Path "$TargetDir\plugins" -Force | Out-Null

    # Copy config files
    Copy-Item "$ConfigDir\opencode.json" "$TargetDir\opencode.json" -Force
    Log-Ok "Copied: opencode.json"

    Copy-Item "$ConfigDir\oh-my-openagent.json" "$TargetDir\oh-my-openagent.json" -Force
    Log-Ok "Copied: oh-my-openagent.json"

    New-Item -ItemType Directory -Path "$TargetDir\plugins" -Force | Out-Null
    Copy-Item "$ConfigDir\plugins\vision-auto.ts" "$TargetDir\plugins\vision-auto.ts" -Force
    Log-Ok "Copied: plugins\vision-auto.ts"

    # Copy optional files
    foreach ($f in $OptionalFiles) {
        $fullPath = Join-Path $ConfigDir $f
        if (Test-Path $fullPath) {
            Copy-Item $fullPath "$TargetDir\$f" -Force
            Log-Ok "Copied: $f"
        }
    }

    # Copy skills if present
    $SkillsDir = Join-Path $ConfigDir "skills"
    if (Test-Path $SkillsDir) {
        New-Item -ItemType Directory -Path "$TargetDir\skills" -Force | Out-Null
        Copy-Item "$SkillsDir\*" "$TargetDir\skills\" -Recurse -Force
        Log-Ok "Copied: skills\"
    }
}

Write-Host ""

# ============================================================
# Step 6: Install dependencies
# ============================================================
if ($DryRun) {
    Log-Info "[DRY] Would run: cd $TargetDir && npm install"
} else {
    Log-Info "Installing npm dependencies..."
    Set-Location $TargetDir
    if (Test-Path "package.json") {
        npm install 2>&1 | Select-Object -Last 3
        Log-Ok "npm dependencies installed"
    } else {
        Log-Warn "No package.json found, skipping npm install"
    }
}

Write-Host ""

# ============================================================
# Step 7: Install OMO plugin
# ============================================================
if (-not $SkipOmo) {
    Log-Info "Checking OMO plugin..."
    if ($DryRun) {
        Log-Info "[DRY] Would run: bunx oh-my-openagent doctor"
    } else {
        $omoCheck = bunx oh-my-openagent doctor 2>$null
        if ($LASTEXITCODE -eq 0) {
            Log-Ok "OMO plugin is working"
        } else {
            Log-Warn "OMO plugin not installed. Run manually:"
            Log-Info "  bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no"
        }
    }
} else {
    Log-Info "Skipping OMO plugin check."
}

Write-Host ""

# ============================================================
# Step 8: Verify
# ============================================================
Log-Info "Verifying deployment..."

if ($DryRun) {
    Log-Info "[DRY] Would verify config"
} else {
    # Check config is valid JSON
    try {
        Get-Content "$TargetDir\opencode.json" | ConvertFrom-Json | Out-Null
        Log-Ok "opencode.json: valid JSON"
    } catch {
        Log-Error "opencode.json: invalid JSON"
    }

    try {
        Get-Content "$TargetDir\oh-my-openagent.json" | ConvertFrom-Json | Out-Null
        Log-Ok "oh-my-openagent.json: valid JSON"
    } catch {
        Log-Error "oh-my-openagent.json: invalid JSON"
    }

    # Check plugin file exists
    if (Test-Path "$TargetDir\plugins\vision-auto.ts") {
        Log-Ok "vision-auto.ts: present"
    } else {
        Log-Error "vision-auto.ts: missing"
    }

    # Show version
    $ver = opencode --version 2>$null
    Log-Ok "OpenCode: $ver"

    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Deployment Complete!"
    Write-Host "============================================"
    Write-Host ""
    Log-Info "Run 'opencode' to start."
    Log-Info "If OMO plugin is not loaded, run:"
    Log-Info "  bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no"
}

Write-Host ""
Log-Ok "Done!"
