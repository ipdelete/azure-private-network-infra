#!/bin/bash

# ─────────────────────────────────────────────
# 🔑 SSH Key Setup for PKI CA VM
# ─────────────────────────────────────────────
# Reuses the existing VM SSH key or generates a new one.

KEY_NAME="vm-pi-localdev-key"
KEY_PATH="$HOME/.ssh/$KEY_NAME"

if [ -f "$KEY_PATH.pub" ]; then
    echo "✅ Reusing existing SSH key: $KEY_PATH"
    echo ""
    echo "📋 Your SSH public key (copy this to main.parameters.json):"
    echo "────────────────────────────────────────────────────────"
    cat "$KEY_PATH.pub"
    echo "────────────────────────────────────────────────────────"
else
    echo "🔑 Generating SSH key pair for PKI CA VM access..."
    ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""

    if [ $? -eq 0 ]; then
        echo "✅ SSH key pair generated successfully!"
        echo ""
        echo "📋 Your SSH public key (copy this to main.parameters.json):"
        echo "────────────────────────────────────────────────────────"
        cat "$KEY_PATH.pub"
        echo "────────────────────────────────────────────────────────"
    else
        echo "❌ Failed to generate SSH key pair."
    fi
fi
