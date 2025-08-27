# Git Hooks for SSH Key Protection

This directory contains git hooks and setup scripts to prevent accidental commits of actual SSH public keys.

## Quick Setup

To set up the git hooks for this repository:

```bash
./scripts/setup-hooks.sh
```

## What's Included

### `pre-commit`
A git pre-commit hook that:
- Checks `vm/main.parameters.json` and other parameter files for actual SSH keys
- Ensures only the placeholder `YOUR_SSH_PUBLIC_KEY_HERE` is committed
- Scans all staged files for potential SSH public key patterns
- Blocks commits if actual SSH keys are detected

### `setup-hooks.sh`
A setup script that:
- Installs the pre-commit hook into your local `.git/hooks/` directory
- Checks for required dependencies (like `jq`)
- Creates backups of existing hooks
- Tests the hook installation

## How It Works

1. **Before each commit**, the pre-commit hook automatically runs
2. It checks the `adminPublicKey` parameter in JSON files
3. If it finds anything other than `YOUR_SSH_PUBLIC_KEY_HERE`, the commit is blocked
4. You must replace actual SSH keys with the placeholder before committing

## Prerequisites

- `jq` - JSON processor (required for parsing parameter files)
  - Ubuntu/Debian: `sudo apt-get install jq`
  - CentOS/RHEL: `sudo yum install jq`
  - macOS: `brew install jq`

## Usage Example

❌ **This will be blocked:**
```json
{
  "adminPublicKey": {
    "value": "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7..."
  }
}
```

✅ **This will be allowed:**
```json
{
  "adminPublicKey": {
    "value": "YOUR_SSH_PUBLIC_KEY_HERE"
  }
}
```

## Troubleshooting

If the hook blocks your commit:
1. Edit the parameter file to replace the actual SSH key with `YOUR_SSH_PUBLIC_KEY_HERE`
2. Stage your changes: `git add .`
3. Retry your commit

To temporarily bypass the hook (not recommended):
```bash
git commit --no-verify
```

## For New Contributors

When you clone this repository:
1. Run `./scripts/setup-hooks.sh` to install the protective hooks
2. The hooks will automatically protect against accidental key commits
3. Always use the placeholder `YOUR_SSH_PUBLIC_KEY_HERE` in parameter files
