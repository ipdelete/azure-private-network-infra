#!/bin/bash

# ─────────────────────────────────────────────
# 🔑 SSH Key Generation Helper Script
# ─────────────────────────────────────────────

KEY_NAME="vm-pi-localdev-key"
KEY_PATH="$HOME/.ssh/$KEY_NAME"

echo "🔑 Generating SSH key pair for VM access..."

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""

if [ $? -eq 0 ]; then
    echo "✅ SSH key pair generated successfully!"
    echo ""
    echo "📁 Files created:"
    echo "   Private key: $KEY_PATH"
    echo "   Public key:  $KEY_PATH.pub"
    echo ""
    echo "📋 Your SSH public key (copy this to main.parameters.json):"
    echo "────────────────────────────────────────────────────────"
    cat "$KEY_PATH.pub"
    echo "────────────────────────────────────────────────────────"
    echo ""
    echo "📝 To update the parameters file automatically:"
    echo "   1. Copy the public key above"
    echo "   2. Replace 'YOUR_SSH_PUBLIC_KEY_HERE' in main.parameters.json"
    echo ""
    echo "🔐 To connect to the VM later (via Bastion):"
    echo "   ssh -i $KEY_PATH azureuser@<VM_PRIVATE_IP>"
else
    echo "❌ Failed to generate SSH key pair."
fi
