#!/bin/bash

# Setup script for git hooks
# This script installs the pre-commit hook to prevent committing actual SSH keys

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BLUE}=== Git Hooks Setup for Azure Private Network Infrastructure ===${NC}"
echo -e "${YELLOW}This script will install git hooks to protect against committing actual SSH keys.${NC}"
echo ""

# Check if we're in a git repository
if [ ! -d "${REPO_ROOT}/.git" ]; then
    echo -e "${RED}ERROR: Not in a git repository root. Please run this script from the repository.${NC}"
    exit 1
fi

# Check if jq is installed (required for the hook)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}WARNING: 'jq' is not installed.${NC}"
    echo -e "${YELLOW}The pre-commit hook requires 'jq' to parse JSON files.${NC}"
    echo -e "${YELLOW}Please install jq:${NC}"
    echo -e "${YELLOW}  - Ubuntu/Debian: sudo apt-get install jq${NC}"
    echo -e "${YELLOW}  - CentOS/RHEL: sudo yum install jq${NC}"
    echo -e "${YELLOW}  - macOS: brew install jq${NC}"
    echo ""
    read -p "Continue without jq? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted. Please install jq and run this script again.${NC}"
        exit 1
    fi
fi

# Create .git/hooks directory if it doesn't exist
HOOKS_DIR="${REPO_ROOT}/.git/hooks"
mkdir -p "${HOOKS_DIR}"

# Copy pre-commit hook
PRE_COMMIT_SOURCE="${SCRIPT_DIR}/pre-commit"
PRE_COMMIT_DEST="${HOOKS_DIR}/pre-commit"

if [ -f "${PRE_COMMIT_DEST}" ]; then
    echo -e "${YELLOW}Pre-commit hook already exists. Creating backup...${NC}"
    cp "${PRE_COMMIT_DEST}" "${PRE_COMMIT_DEST}.backup.$(date +%Y%m%d_%H%M%S)"
fi

echo -e "${YELLOW}Installing pre-commit hook...${NC}"
cp "${PRE_COMMIT_SOURCE}" "${PRE_COMMIT_DEST}"
chmod +x "${PRE_COMMIT_DEST}"

echo -e "${GREEN}✓ Pre-commit hook installed successfully${NC}"

# Test the hook
echo -e "${YELLOW}Testing the pre-commit hook...${NC}"

# Create a temporary test to ensure the hook works
cd "${REPO_ROOT}"

# Check current status
if git diff --cached --quiet; then
    echo -e "${BLUE}No staged changes detected. Hook is ready to protect future commits.${NC}"
else
    echo -e "${YELLOW}Staged changes detected. Running hook test...${NC}"
    if "${PRE_COMMIT_DEST}"; then
        echo -e "${GREEN}✓ Hook test passed${NC}"
    else
        echo -e "${RED}⚠ Hook test failed - this is expected if you have actual SSH keys staged${NC}"
        echo -e "${YELLOW}The hook is working correctly by preventing the commit.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo -e "${YELLOW}The pre-commit hook is now active and will:${NC}"
echo -e "${YELLOW}  • Prevent committing actual SSH public keys${NC}"
echo -e "${YELLOW}  • Ensure only the placeholder 'YOUR_SSH_PUBLIC_KEY_HERE' is committed${NC}"
echo -e "${YELLOW}  • Scan all staged files for potential SSH keys${NC}"
echo ""
echo -e "${BLUE}Usage:${NC}"
echo -e "${YELLOW}  • The hook runs automatically on every commit${NC}"
echo -e "${YELLOW}  • If it detects actual SSH keys, the commit will be blocked${NC}"
echo -e "${YELLOW}  • Replace any real SSH keys with 'YOUR_SSH_PUBLIC_KEY_HERE' before committing${NC}"
echo ""
echo -e "${GREEN}Repository is now protected against accidental SSH key commits!${NC}"
