#!/bin/bash
set -e

echo "==================================="
echo "  viberunner Development Setup"
echo "==================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        return 1
    fi
}

echo "Checking prerequisites..."
echo ""

# Check for Homebrew
if ! check_command brew; then
    echo ""
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# Check for Node.js
if ! check_command node; then
    echo ""
    echo -e "${YELLOW}Installing Node.js...${NC}"
    brew install node
fi

# Check for Docker
if ! check_command docker; then
    echo ""
    echo -e "${YELLOW}Installing Docker...${NC}"
    echo "Docker Desktop is required for local Supabase."
    echo "Please install from: https://www.docker.com/products/docker-desktop/"
    echo ""
    echo -e "${RED}After installing Docker Desktop, run this script again.${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo ""
    echo -e "${RED}Docker is installed but not running.${NC}"
    echo "Please start Docker Desktop and run this script again."
    exit 1
fi

# Check for Supabase CLI
if ! check_command supabase; then
    echo ""
    echo -e "${YELLOW}Installing Supabase CLI...${NC}"
    brew install supabase/tap/supabase
fi

# Check for xcodegen (for iOS development)
if ! check_command xcodegen; then
    echo ""
    echo -e "${YELLOW}Installing xcodegen...${NC}"
    brew install xcodegen
fi

# Check for Doppler CLI (secrets management)
if ! check_command doppler; then
    echo ""
    echo -e "${YELLOW}Installing Doppler CLI...${NC}"
    brew install dopplerhq/cli/doppler
fi

echo ""
echo "==================================="
echo "  Setting up environment secrets..."
echo "==================================="
echo ""

SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/pull-secrets.sh"

echo ""
echo "==================================="
echo "  Installing npm dependencies..."
echo "==================================="
echo ""

cd "$(dirname "$0")/.."
npm install

echo ""
echo "==================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "==================================="
echo ""
echo "Next steps:"
echo "  1. Make sure Docker Desktop is running"
echo "  2. Run: npm run dev"
echo ""
echo "For iOS development:"
echo "  1. Update your IP in apps/ios/viberunner/Config/Local.xcconfig"
echo "  2. Run: cd apps/ios/viberunner && xcodegen generate"
echo "  3. Open viberunner.xcodeproj in Xcode"
echo ""
