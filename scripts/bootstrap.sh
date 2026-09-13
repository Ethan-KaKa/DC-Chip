#!/usr/bin/env bash
# ==============================================================================
# DC-Chip Repository Fast Bootstrap Script
# Implements one-command setup following BUILD_RULES.md standard:
# 1. Dependency diagnosis & platform-specific package suggestions (Doctor)
# 2. Shallow & concurrent submodule synchronization
# 3. Kconfig default configuration bootstrap
# 4. Optional external tools pre-build (NVBoard, Spike)
# 5. Git security hook activation & local configuration guidance
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_RESET="\033[0m"

log_info() { printf "${COLOR_CYAN}[INFO]${COLOR_RESET} %s\n" "$*"; }
log_ok()   { printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$*"; }
log_warn() { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$*"; }
log_err()  { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*"; }

printf "%b\n" "${COLOR_CYAN}=== DC-Chip Repository Fast Bootstrap ===${COLOR_RESET}"

# ------------------------------------------------------------------------------
# Layer 0: System Dependency Doctor
# ------------------------------------------------------------------------------
log_info "Step 0: Checking system dependencies..."

missing_pkgs=()

check_cmd() {
    local cmd="$1"
    local pkg_hint="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_pkgs+=("$pkg_hint")
        return 1
    fi
    return 0
}

check_cmd "make" "build-essential" || true
check_cmd "gcc" "build-essential" || true
check_cmd "g++" "build-essential" || true
check_cmd "python3" "python3" || true
check_cmd "verilator" "verilator" || true
check_cmd "iverilog" "iverilog" || true
check_cmd "vvp" "iverilog" || true

# Cross toolchain check (either riscv64-unknown-elf-gcc or riscv64-linux-gnu-gcc)
if ! command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 && ! command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
    missing_pkgs+=("gcc-riscv64-linux-gnu (or riscv-gnu-toolchain)")
fi

# Graphical and simulator dependencies (optional but recommended)
if ! command -v sdl2-config >/dev/null 2>&1; then
    missing_pkgs+=("libsdl2-dev")
fi
if ! command -v dtc >/dev/null 2>&1; then
    missing_pkgs+=("device-tree-compiler")
fi

if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    log_warn "Some recommended packages are missing from your system:"
    for pkg in "${missing_pkgs[@]}"; do
        printf "  - %s\n" "$pkg"
    done
    printf "\n"
    if [ -f /etc/debian_version ] || [ -f /etc/ubuntu-release ] || grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
        log_info "Suggested installation command for Ubuntu / Debian:"
        printf "  ${COLOR_YELLOW}sudo apt update && sudo apt install -y build-essential verilator iverilog python3 gcc-riscv64-linux-gnu libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev device-tree-compiler libboost-system-dev libboost-regex-dev${COLOR_RESET}\n\n"
    elif [ -f /etc/arch-release ] || grep -qi "arch" /etc/os-release 2>/dev/null; then
        log_info "Suggested installation command for Arch Linux:"
        printf "  ${COLOR_YELLOW}sudo pacman -S --needed base-devel verilator iverilog python riscv64-linux-gnu-gcc sdl2 sdl2_image sdl2_ttf dtc boost${COLOR_RESET}\n\n"
    fi
else
    log_ok "Core development tools verified."
fi

# ------------------------------------------------------------------------------
# Layer 1: Submodule Initialization (Shallow clone for fast download)
# ------------------------------------------------------------------------------
log_info "Step 1: Synchronizing submodules (shallow)..."
if [ -f .gitmodules ]; then
    git submodule update --init --recursive --depth 1
    log_ok "Submodules are up to date."
else
    log_info "No submodules configured."
fi

# ------------------------------------------------------------------------------
# Layer 2: Default Configuration Bootstrap
# ------------------------------------------------------------------------------
log_info "Step 2: Ensuring configuration exists..."
if [ ! -f .config ]; then
    if [ -f configs/default_defconfig ]; then
        make defconfig
        log_ok "Created default configuration (.config)."
    fi
else
    log_ok "Existing .config found."
fi

# ------------------------------------------------------------------------------
# Layer 3: External Tools Initialization
# ------------------------------------------------------------------------------
log_info "Step 3: Checking external tools readiness..."
if [ -d "tools/nvboard" ] && [ -f "tools/nvboard/scripts/nvboard.mk" ]; then
    log_ok "NVBoard source is ready; configured builds use build/tools/nvboard."
fi

# ------------------------------------------------------------------------------
# Layer 4: Git Security Hooks & Local Customization
# ------------------------------------------------------------------------------
log_info "Step 4: Activating local repository defense..."
if [ -d ".githooks" ]; then
    git config --local core.hooksPath .githooks
    log_ok "Activated local Git hooks from .githooks (pre-commit)."
fi

if [ ! -f "AGENTS.local.md" ] && [ ! -f ".localset.md" ]; then
    log_info "Private configuration tip:"
    printf "  You can copy ${COLOR_CYAN}AGENTS.local.example.md${COLOR_RESET} to ${COLOR_CYAN}AGENTS.local.md${COLOR_RESET} to configure your external ysyx path, private papers directory, or personal AI preferences.\n"
fi

printf "\n%b\n" "${COLOR_GREEN}✔ DC-Chip environment fast bootstrap complete!${COLOR_RESET}"
printf "Quick start commands:\n"
printf "  - Browse all test suites:      ${COLOR_CYAN}make list${COLOR_RESET}\n"
printf "  - Run unit testbenches:        ${COLOR_CYAN}make testunit${COLOR_RESET}\n"
printf "  - Run software smoke tests:    ${COLOR_CYAN}make sw tests${COLOR_RESET}\n"
printf "  - Run CPU UART simulation:     ${COLOR_CYAN}make sw tests ALL=uart_hello${COLOR_RESET}\n"
printf "  - Run full regression suite:   ${COLOR_CYAN}make test${COLOR_RESET}\n"
