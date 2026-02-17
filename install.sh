#!/usr/bin/env bash
set -euo pipefail

REPO="marcjeffrey/git-kiss"
INSTALL_DIR="/usr/local/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# Check for git
command -v git &>/dev/null || error "git is required but not installed."

info "Installing git-kiss..."

# Download the gk script
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/bin/gk" -o "$TEMP_DIR/gk" \
  || error "Failed to download gk. Check your network connection."

chmod +x "$TEMP_DIR/gk"

# Install to /usr/local/bin (may need sudo)
if [[ -w "$INSTALL_DIR" ]]; then
  mv "$TEMP_DIR/gk" "$INSTALL_DIR/gk"
else
  info "Requesting sudo to install to $INSTALL_DIR..."
  sudo mv "$TEMP_DIR/gk" "$INSTALL_DIR/gk"
fi

success "git-kiss installed to $INSTALL_DIR/gk"
echo ""
echo -e "${BOLD}Get started:${NC}"
echo "  cd your-repo"
echo "  gk init"
echo "  gk nf my-feature"
echo ""
echo -e "Docs: https://github.com/${REPO}"
