#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo -e "${RED}Doppler CLI is not installed.${NC}"
    echo "Install with: brew install dopplerhq/cli/doppler"
    exit 1
fi

# Check if user is logged in to Doppler
if ! doppler me &> /dev/null; then
    echo -e "${YELLOW}You are not logged in to Doppler.${NC}"
    echo ""
    echo "To set up Doppler:"
    echo "  1. Create a free account at https://doppler.com"
    echo "  2. Run: doppler login"
    echo "  3. Run this script again"
    echo ""
    echo -e "${YELLOW}Skipping secrets pull - using existing .env files if present.${NC}"
    exit 0
fi

# Check if Doppler can access the project
if ! doppler secrets --project viberunner --config dev &> /dev/null; then
    echo -e "${YELLOW}Cannot access Doppler project 'viberunner'.${NC}"
    echo ""
    echo "Either:"
    echo "  - The project doesn't exist yet (run ./scripts/push-secrets.sh first)"
    echo "  - You don't have access (ask team lead to invite you)"
    echo ""
    echo -e "${YELLOW}Skipping secrets pull - using existing .env files if present.${NC}"
    exit 0
fi

echo "Pulling secrets from Doppler..."

# Pull secrets to a temp file first
SECRETS=$(doppler secrets download --project viberunner --config dev --no-file --format env 2>/dev/null)

# Write to all .env locations (services pick what they need)
echo "$SECRETS" > "$PROJECT_ROOT/services/api/.env"
echo -e "${GREEN}✓${NC} services/api/.env"

echo "$SECRETS" > "$PROJECT_ROOT/services/worker/.env"
echo -e "${GREEN}✓${NC} services/worker/.env"

echo "$SECRETS" > "$PROJECT_ROOT/packages/db/.env"
echo -e "${GREEN}✓${NC} packages/db/.env"

echo ""
echo -e "${GREEN}Secrets pulled successfully!${NC}"
