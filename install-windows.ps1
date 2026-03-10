# ─────────────────────────────────────────────────────────
# DataSovNet Node Installer — Windows
# Installs llama.cpp with RPC for distributed AI inference
# + Tailscale for secure mesh networking
# ─────────────────────────────────────────────────────────
#
# Run in PowerShell as Administrator:
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\install-windows.ps1
# ─────────────────────────────────────────────────────────

$DATASOVNET_VERSION = "0.2.0"
$DATASOVNET_DIR = "$env:USERPROFILE\.datasovnet"
$CONFIG_FILE = "$DATASOVNET_DIR\config.json"
$LOG_FILE = "$DATASOVNET_DIR\install.log"
$LLAMA_CPP_DIR = "$DATASOVNET_DIR\llama.cpp"
$RPC_PORT = 50052

function Write-Banner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        DataSovNet Node Setup          ║" -ForegroundColor Cyan
    Write-Host "  ║   Distributed AI Compute Network      ║" -ForegroundColor Cyan
    Write-Host "  ║    llama.cpp RPC + Tailscale          ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Version: $DATASOVNET_VERSION"
    Write-Host ""
}

function Write-Log($msg) {
    Add-Content -Path $LOG_FILE -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host "  + $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Add-Content -Path $LOG_FILE -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WARN: $msg"
    Write-Host "  ! $msg" -ForegroundColor Yellow
}

function Write-Err($msg) {
    Add-Content -Path $LOG_FILE -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: $msg"
    Write-Host "  x $msg" -ForegroundColor Red
}

# ─── System Detection ────────────────────────────────────

function Detect-System {
    Write-Host ""
    Write-Host "  Detecting system..." -NoNewline
    Write-Host ""

    $script:GPU_TYPE = "none"
    $script:GPU_VRAM = 0
    $script:GPU_NAME = "Unknown"
    $script:TOTAL_RAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $script:CMAKE_GPU_FLAGS = ""

    Write-Log "OS: Windows ($env:PROCESSOR_ARCHITECTURE)"
    Write-Log "System RAM: ${TOTAL_RAM}GB"

    # Check for NVIDIA GPU
    try {
        $nvidiaSmi = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null
        if ($nvidiaSmi) {
            $parts = $nvidiaSmi.Split(',').Trim()
            $script:GPU_NAME = $parts[0]
            $script:GPU_VRAM = [math]::Round([int]$parts[1] / 1024)
            $script:GPU_TYPE = "nvidia"
            $script:CMAKE_GPU_FLAGS = "-DGGML_CUDA=ON"
            Write-Log "GPU: NVIDIA $GPU_NAME (${GPU_VRAM}GB VRAM)"
        }
    } catch {
        $script:GPU_TYPE = "cpu-only"
        Write-Warn "No NVIDIA GPU detected — CPU-only mode"
    }

    # Determine tier
    $availMem = if ($GPU_VRAM -gt 0) { $GPU_VRAM } else { $TOTAL_RAM }
    if ($availMem -ge 32) {
        $script:MODEL_TIER = "large"
        Write-Log "Tier: LARGE — can contribute 32GB+ to distributed models"
    } elseif ($availMem -ge 16) {
        $script:MODEL_TIER = "medium"
        Write-Log "Tier: MEDIUM — can contribute 16GB+ to distributed models"
    } elseif ($availMem -ge 8) {
        $script:MODEL_TIER = "small"
        Write-Log "Tier: SMALL — can contribute 8GB+ to distributed models"
    } else {
        $script:MODEL_TIER = "minimal"
        Write-Warn "Tier: MINIMAL — limited contribution"
    }
}

# ─── Install Prerequisites ───────────────────────────────

function Install-Prerequisites {
    Write-Host ""
    Write-Host "  Installing prerequisites..." -ForegroundColor White
    Write-Host ""

    # Check for Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "  Git is required. Install from: https://git-scm.com/download/win"
        Write-Host "  Or with winget: winget install Git.Git"
        $installGit = Read-Host "  Install with winget now? [Y/n]"
        if ($installGit -ne 'n') {
            winget install Git.Git --accept-source-agreements --accept-package-agreements
        } else {
            Write-Err "Git required. Install and re-run."
            exit 1
        }
    }
    Write-Log "Git available"

    # Check for CMake
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        Write-Host "  CMake is required."
        $installCmake = Read-Host "  Install with winget? [Y/n]"
        if ($installCmake -ne 'n') {
            winget install Kitware.CMake --accept-source-agreements --accept-package-agreements
            $env:PATH += ";C:\Program Files\CMake\bin"
        } else {
            Write-Err "CMake required. Install from https://cmake.org/download/"
            exit 1
        }
    }
    Write-Log "CMake available"

    # Check for Visual Studio Build Tools
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) {
        Write-Warn "Visual Studio Build Tools not found."
        Write-Host "  Install: winget install Microsoft.VisualStudio.2022.BuildTools"
        Write-Host "  Then add C++ workload in Visual Studio Installer."
        $installVS = Read-Host "  Install with winget now? [Y/n]"
        if ($installVS -ne 'n') {
            winget install Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements
            Write-Host "  After install, open Visual Studio Installer and add 'Desktop Development with C++'"
            Read-Host "  Press Enter when ready..."
        }
    }
    Write-Log "Build tools checked"

    # CUDA check for NVIDIA
    if ($GPU_TYPE -eq "nvidia") {
        if (-not (Get-Command nvcc -ErrorAction SilentlyContinue)) {
            if (Test-Path "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA") {
                $cudaDirs = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA" -Directory | Sort-Object Name -Descending
                if ($cudaDirs) {
                    $env:PATH += ";$($cudaDirs[0].FullName)\bin"
                    Write-Log "Found CUDA at $($cudaDirs[0].FullName)"
                }
            } else {
                Write-Warn "CUDA toolkit not found. Download from: https://developer.nvidia.com/cuda-downloads"
                $skipCuda = Read-Host "  Continue without CUDA (CPU-only)? [y/N]"
                if ($skipCuda -eq 'y') {
                    $script:CMAKE_GPU_FLAGS = ""
                    $script:GPU_TYPE = "cpu-only"
                } else {
                    exit 1
                }
            }
        } else {
            Write-Log "CUDA toolkit available"
        }
    }
}

# ─── Build llama.cpp ─────────────────────────────────────

function Build-LlamaCpp {
    Write-Host ""
    Write-Host "  Building llama.cpp with RPC support..." -ForegroundColor White
    Write-Host ""

    if ((Test-Path "$LLAMA_CPP_DIR\build\bin\Release\rpc-server.exe") -and (Test-Path "$LLAMA_CPP_DIR\build\bin\Release\llama-server.exe")) {
        Write-Log "llama.cpp already built"
        $rebuild = Read-Host "  Rebuild? [y/N]"
        if ($rebuild -ne 'y') { return }
    }

    New-Item -ItemType Directory -Path $DATASOVNET_DIR -Force | Out-Null

    if (Test-Path $LLAMA_CPP_DIR) {
        Write-Host "  Updating llama.cpp..."
        Push-Location $LLAMA_CPP_DIR
        git pull --quiet 2>>$LOG_FILE
        Pop-Location
    } else {
        Write-Host "  Cloning llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git $LLAMA_CPP_DIR 2>>$LOG_FILE
    }

    Write-Log "Source ready at $LLAMA_CPP_DIR"
    Push-Location $LLAMA_CPP_DIR

    Write-Host "  Building with: -DGGML_RPC=ON $CMAKE_GPU_FLAGS"
    Write-Host "  (This takes several minutes on first build...)"

    $cmakeArgs = @("-B", "build", "-DGGML_RPC=ON", "-DCMAKE_BUILD_TYPE=Release")
    if ($CMAKE_GPU_FLAGS) {
        $cmakeArgs += $CMAKE_GPU_FLAGS
    }

    & cmake @cmakeArgs 2>>$LOG_FILE
    & cmake --build build --config Release -j $env:NUMBER_OF_PROCESSORS 2>>$LOG_FILE

    Pop-Location

    # Check for binaries (Release subfolder on Windows)
    $rpcPath = "$LLAMA_CPP_DIR\build\bin\Release\rpc-server.exe"
    $serverPath = "$LLAMA_CPP_DIR\build\bin\Release\llama-server.exe"

    # Fallback to non-Release path
    if (-not (Test-Path $rpcPath)) { $rpcPath = "$LLAMA_CPP_DIR\build\bin\rpc-server.exe" }
    if (-not (Test-Path $serverPath)) { $serverPath = "$LLAMA_CPP_DIR\build\bin\llama-server.exe" }

    if (Test-Path $rpcPath) {
        Write-Log "rpc-server built: $rpcPath"
    } else {
        Write-Err "rpc-server not found after build"
        exit 1
    }

    if (Test-Path $serverPath) {
        Write-Log "llama-server built: $serverPath"
    } else {
        Write-Err "llama-server not found after build"
        exit 1
    }

    $script:RPC_SERVER_PATH = $rpcPath
    $script:LLAMA_SERVER_PATH = $serverPath
}

# ─── Install Tailscale ───────────────────────────────────

function Install-Tailscale {
    Write-Host ""
    Write-Host "  Installing Tailscale..." -ForegroundColor White
    Write-Host ""

    if (Get-Command tailscale -ErrorAction SilentlyContinue) {
        Write-Log "Tailscale already installed"
        return
    }

    $installTS = Read-Host "  Install Tailscale with winget? [Y/n]"
    if ($installTS -ne 'n') {
        winget install Tailscale.Tailscale --accept-source-agreements --accept-package-agreements
        Write-Log "Tailscale installed"
        Write-Host "  Open Tailscale from Start Menu and sign in."
        Read-Host "  Press Enter when connected..."
    } else {
        Write-Host "  Download from: https://tailscale.com/download/windows"
    }
}

# ─── Configure Node ──────────────────────────────────────

function Configure-Node {
    Write-Host ""
    Write-Host "  Configuring DataSovNet node..." -ForegroundColor White
    Write-Host ""

    $defaultName = $env:COMPUTERNAME.ToLower()
    $script:NODE_NAME = Read-Host "  Node name [$defaultName]"
    if (-not $NODE_NAME) { $script:NODE_NAME = $defaultName }

    $script:NODE_ROLE = "worker"
    Write-Host ""
    Write-Host "  This machine will be an RPC Worker (contributes GPU to the network)."
    Write-Host ""

    $script:COORDINATOR_IP = Read-Host "  Coordinator's Tailscale IP"
    if (-not $COORDINATOR_IP) {
        Write-Warn "No coordinator IP — set later in $CONFIG_FILE"
        $script:COORDINATOR_IP = "unknown"
    }

    # Get Tailscale IP
    $tsIP = "unknown"
    try { $tsIP = (& tailscale ip -4 2>$null).Trim() } catch {}

    $script:NODE_ID = "dsn-" + (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes("$NODE_NAME-$(Get-Date -UFormat %s)"))) -Algorithm SHA256).Hash.Substring(0, 8).ToLower()

    New-Item -ItemType Directory -Path $DATASOVNET_DIR -Force | Out-Null

    $config = @{
        version = $DATASOVNET_VERSION
        node_id = $NODE_ID
        node_name = $NODE_NAME
        role = $NODE_ROLE
        coordinator_ip = $COORDINATOR_IP
        tailscale_ip = $tsIP
        system = @{
            os = "windows"
            arch = $env:PROCESSOR_ARCHITECTURE
            gpu_type = $GPU_TYPE
            gpu_name = $GPU_NAME
            gpu_vram_gb = $GPU_VRAM
            total_ram_gb = $TOTAL_RAM
            model_tier = $MODEL_TIER
        }
        rpc = @{
            port = $RPC_PORT
            host = "0.0.0.0"
        }
        llama_cpp = @{
            dir = $LLAMA_CPP_DIR
            rpc_server = $RPC_SERVER_PATH
            llama_server = $LLAMA_SERVER_PATH
        }
        registered_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json -Depth 3

    Set-Content -Path $CONFIG_FILE -Value $config
    Write-Log "Node configured: $NODE_NAME ($NODE_ID)"
}

# ─── Create Helper Scripts ───────────────────────────────

function Create-HelperScripts {
    Write-Host ""
    Write-Host "  Creating helper scripts..." -ForegroundColor White
    Write-Host ""

    # Start worker
    @"
@echo off
echo Starting DataSovNet RPC Worker on port $RPC_PORT ...
"$RPC_SERVER_PATH" --host 0.0.0.0 --port $RPC_PORT
"@ | Set-Content "$DATASOVNET_DIR\start-worker.bat"
    Write-Log "Created: $DATASOVNET_DIR\start-worker.bat"

    # Stop worker
    @"
@echo off
taskkill /IM rpc-server.exe /F 2>nul && echo RPC worker stopped. || echo No RPC worker running.
"@ | Set-Content "$DATASOVNET_DIR\stop-worker.bat"
    Write-Log "Created: $DATASOVNET_DIR\stop-worker.bat"

    # Status
    @"
@echo off
echo.
echo   DataSovNet Node Status
echo   ======================
echo   Name:     $NODE_NAME
echo   Role:     $NODE_ROLE
echo   GPU:      $GPU_NAME (${GPU_VRAM}GB)
echo   RPC Port: $RPC_PORT
echo.
tasklist /FI "IMAGENAME eq rpc-server.exe" 2>nul | find /I "rpc-server" >nul && (echo   RPC Worker: RUNNING) || (echo   RPC Worker: STOPPED)
tailscale ip -4 2>nul && (echo   Tailscale: Connected) || (echo   Tailscale: Not connected)
echo.
"@ | Set-Content "$DATASOVNET_DIR\status.bat"
    Write-Log "Created: $DATASOVNET_DIR\status.bat"
}

# ─── Summary ─────────────────────────────────────────────

function Print-Summary {
    Write-Host ""
    Write-Host "  =========================================" -ForegroundColor Green
    Write-Host "  DataSovNet Node Setup Complete!" -ForegroundColor Green
    Write-Host "  =========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Node Name:   $NODE_NAME"
    Write-Host "  Node ID:     $NODE_ID"
    Write-Host "  Role:        $NODE_ROLE"
    Write-Host "  GPU:         $GPU_NAME (${GPU_VRAM}GB)"
    Write-Host "  RPC Port:    $RPC_PORT"

    $tsIP = "not connected"
    try { $tsIP = (& tailscale ip -4 2>$null).Trim() } catch {}

    Write-Host ""
    if ($tsIP -ne "not connected") {
        Write-Host "  Tailscale IP: $tsIP" -ForegroundColor Cyan
        Write-Host "  RPC endpoint: ${tsIP}:$RPC_PORT" -ForegroundColor Cyan
    } else {
        Write-Host "  Tailscale not connected. Open Tailscale app and sign in." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Quick Commands:"
    Write-Host "    $DATASOVNET_DIR\start-worker.bat   # Start RPC worker"
    Write-Host "    $DATASOVNET_DIR\stop-worker.bat    # Stop RPC worker"
    Write-Host "    $DATASOVNET_DIR\status.bat         # Check status"
    Write-Host ""
    Write-Host "  Tell the coordinator:" -ForegroundColor White
    Write-Host "    Node name:  $NODE_NAME"
    Write-Host "    Tailscale:  $tsIP"
    Write-Host "    RPC port:   $RPC_PORT"
    Write-Host ""
}

# ─── Main ────────────────────────────────────────────────

Write-Banner

New-Item -ItemType Directory -Path $DATASOVNET_DIR -Force | Out-Null
if (-not (Test-Path $LOG_FILE)) { New-Item $LOG_FILE -Force | Out-Null }

Write-Host "  This script will:" -ForegroundColor White
Write-Host "  1. Detect your GPU and system hardware"
Write-Host "  2. Install build tools (Git, CMake, VS Build Tools)"
Write-Host "  3. Build llama.cpp with RPC + CUDA support"
Write-Host "  4. Install Tailscale (secure mesh VPN)"
Write-Host "  5. Configure your node as an RPC worker"
Write-Host ""
$confirm = Read-Host "  Continue? [Y/n]"
if ($confirm -eq 'n') { Write-Host "  Cancelled."; exit 0 }

Detect-System
Install-Prerequisites
Build-LlamaCpp
Install-Tailscale
Configure-Node
Create-HelperScripts
Print-Summary
