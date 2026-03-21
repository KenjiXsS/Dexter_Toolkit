#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  DEXTER TOOLKIT — Build & Install                        ║
# ║  Installs 'dexter' command to ~/.local/bin               ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/dexter.sh"
INSTALL_DIR="$HOME/.local/bin"
TARGET="$INSTALL_DIR/dexter"

# Colors
G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' R='\033[1;31m' D='\033[2m' RST='\033[0m'

printf '%b\n' "${C}"
cat <<'BANNER'
  ██████╗ ███████╗██╗  ██╗████████╗███████╗██████╗
  ██╔══██╗██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝██╔══██╗
  ██║  ██║█████╗   ╚███╔╝    ██║   █████╗  ██████╔╝
  ██║  ██║██╔══╝   ██╔██╗    ██║   ██╔══╝  ██╔══██╗
  ██████╔╝███████╗██╔╝ ██╗   ██║   ███████╗██║  ██║
  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
BANNER
printf '%b\n' "${RST}"

printf '%b  Build & Install Script%b\n\n' "${D}" "${RST}"

# Check source exists
if [[ ! -f "$SRC" ]]; then
  printf '%b[✘] Source not found: %s%b\n' "${R}" "$SRC" "${RST}"
  exit 1
fi

# Syntax check
printf '%b[*] Checking syntax...%b\n' "${C}" "${RST}"
if bash -n "$SRC"; then
  printf '%b[✔] Syntax OK%b\n' "${G}" "${RST}"
else
  printf '%b[✘] Syntax errors found — aborting%b\n' "${R}" "${RST}"
  exit 1
fi

# Create install dir
mkdir -p "$INSTALL_DIR"

# Attempt shc compilation (true binary)
BUILT_BINARY=false
if command -v shc >/dev/null 2>&1; then
  printf '%b[*] shc found — compiling to binary...%b\n' "${C}" "${RST}"
  if shc -f "$SRC" -o "$TARGET" 2>/dev/null; then
    chmod +x "$TARGET"
    BUILT_BINARY=true
    printf '%b[✔] Binary compiled: %s%b\n' "${G}" "$TARGET" "${RST}"
    # shc also creates a .x.c file, clean it up
    rm -f "${SRC}.x.c" 2>/dev/null || true
  else
    printf '%b[!] shc compilation failed — falling back to script install%b\n' "${Y}" "${RST}"
  fi
fi

# Fallback: install as symlink (preserves SCRIPT_DIR resolution via readlink -f)
if ! $BUILT_BINARY; then
  printf '%b[*] Creating symlink...%b\n' "${C}" "${RST}"
  ln -sf "$SRC" "$TARGET"
  printf '%b[✔] Symlink created: %s → %s%b\n' "${G}" "$TARGET" "$SRC" "${RST}"
fi

# Ensure ~/.local/bin is in PATH
PATH_OK=false
if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
  PATH_OK=true
fi

echo ""
printf '%b╔══ Installation complete ══════════════════════════╗%b\n' "${D}" "${RST}"
printf '  Installed to: %b%s%b\n' "${G}" "$TARGET" "${RST}"
if $BUILT_BINARY; then
  printf '  Type:         %btrue binary (shc)%b\n' "${G}" "${RST}"
else
  printf '  Type:         %bexecutable bash script%b\n' "${C}" "${RST}"
fi
printf '%b╚════════════════════════════════════════════════════╝%b\n' "${D}" "${RST}"
echo ""

if ! $PATH_OK; then
  printf '%b[!] ~/.local/bin is not in your PATH%b\n' "${Y}" "${RST}"
  printf '    Add this to your ~/.zshrc or ~/.bashrc:\n\n'
  printf '    %bexport PATH="$HOME/.local/bin:$PATH"%b\n\n' "${C}" "${RST}"
  printf '    Then reload: %bsource ~/.zshrc%b\n\n' "${D}" "${RST}"
else
  printf '%b[✔] Ready! Run with: %bdexter%b\n\n' "${G}" "${C}" "${RST}"
fi
