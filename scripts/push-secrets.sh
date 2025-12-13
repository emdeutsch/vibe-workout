#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==================================="
echo "  Push Secrets to Doppler"
echo "==================================="
echo ""

# Check if Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo -e "${RED}Doppler CLI is not installed.${NC}"
    echo "Install with: brew install dopplerhq/cli/doppler"
    exit 1
fi

# Check if user is logged in to Doppler
if ! doppler me &> /dev/null; then
    echo -e "${YELLOW}You are not logged in to Doppler.${NC}"
    echo "Run: doppler login"
    exit 1
fi

echo "This script will upload your local .env files to Doppler."
echo ""
echo "Prerequisites:"
echo "  1. Create a project named 'viberunner' in Doppler dashboard"
echo "     (keep the default 'dev' config)"
echo ""
read -p "Have you created the project? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please create the project first:"
    echo "  1. Go to https://dashboard.doppler.com"
    echo "  2. Create project: viberunner"
    exit 1
fi

# Merge all .env files (api has the most complete set)
MERGED_ENV=$(mktemp)
trap "rm -f $MERGED_ENV" EXIT

# Start with api .env (most complete)
if [ -f "$PROJECT_ROOT/services/api/.env" ]; then
    cat "$PROJECT_ROOT/services/api/.env" > "$MERGED_ENV"
fi

# Add any unique vars from worker
if [ -f "$PROJECT_ROOT/services/worker/.env" ]; then
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        # Get the key
        key=$(echo "$line" | cut -d'=' -f1)
        # Add if not already present
        if ! grep -q "^$key=" "$MERGED_ENV" 2>/dev/null; then
            echo "$line" >> "$MERGED_ENV"
        fi
    done < "$PROJECT_ROOT/services/worker/.env"
fi

echo ""
echo "Uploading merged secrets to Doppler..."

if doppler secrets upload "$MERGED_ENV" --project viberunner --config dev; then
    echo -e "${GREEN}✓${NC} Secrets uploaded successfully"
else
    echo -e "${RED}✗${NC} Failed to upload secrets"
    exit 1
fi

echo ""
echo -e "${GREEN}==================================="
echo "  Secrets pushed successfully!"
echo "===================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Team members can now run: ./scripts/setup.sh"
echo "  2. Or manually: ./scripts/pull-secrets.sh"
echo ""
echo "To add a new team member:"
echo "  1. Invite them to your Doppler workspace"
echo "  2. They run: doppler login && ./scripts/setup.sh"
echo ""
