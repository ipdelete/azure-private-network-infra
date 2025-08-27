#!/bin/bash

# ─────────────────────────────────────────────
# 🗑️  VM Removal Script
# ─────────────────────────────────────────────

# 🔧 Configuration
RESOURCE_GROUP="aet-pi-localdev-es2-tst3"
VM_NAME="vm-pi-localdev"
NIC_NAME="${VM_NAME}-nic"
DISK_NAME="${VM_NAME}-osdisk"

echo "🗑️  VM Removal Script"
echo "════════════════════════════════════════════"
echo "Resource Group: $RESOURCE_GROUP"
echo "VM Name: $VM_NAME"
echo "Network Interface: $NIC_NAME"
echo "OS Disk: $DISK_NAME"
echo ""
echo "⚠️  This will permanently delete:"
echo "   • Virtual Machine: $VM_NAME"
echo "   • Network Interface: $NIC_NAME"
echo "   • OS Disk: $DISK_NAME"
echo ""
echo "✅ This will PRESERVE:"
echo "   • Azure Bastion Host"
echo "   • Virtual Network & Subnets"
echo "   • Storage Account & NFS Share"
echo "   • Network Security Groups"
echo ""

# Confirmation prompt
read -p "❓ Are you sure you want to remove the VM? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operation cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting VM removal process..."

# Function to check if resource exists
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "vm")
            az vm show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
        "nic")
            az network nic show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
        "disk")
            az disk show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
    esac
    return $?
}

# Step 1: Remove Virtual Machine
echo "🔄 Step 1: Removing Virtual Machine..."
if check_resource_exists "vm" "$VM_NAME"; then
    az vm delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --yes \
        --no-wait
    
    if [ $? -eq 0 ]; then
        echo "✅ VM deletion initiated successfully"
        
        # Wait for VM deletion to complete before proceeding
        echo "⏳ Waiting for VM deletion to complete..."
        while check_resource_exists "vm" "$VM_NAME"; do
            echo "   Still deleting VM..."
            sleep 10
        done
        echo "✅ VM deletion completed"
    else
        echo "❌ Failed to delete VM"
        exit 1
    fi
else
    echo "ℹ️  VM '$VM_NAME' not found (may already be deleted)"
fi

# Step 2: Remove Network Interface
echo ""
echo "🔄 Step 2: Removing Network Interface..."
if check_resource_exists "nic" "$NIC_NAME"; then
    az network nic delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --no-wait
    
    if [ $? -eq 0 ]; then
        echo "✅ Network Interface deletion initiated successfully"
    else
        echo "❌ Failed to delete Network Interface"
        exit 1
    fi
else
    echo "ℹ️  Network Interface '$NIC_NAME' not found (may already be deleted)"
fi

# Step 3: Remove OS Disk
echo ""
echo "🔄 Step 3: Removing OS Disk..."
if check_resource_exists "disk" "$DISK_NAME"; then
    az disk delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DISK_NAME" \
        --yes \
        --no-wait
    
    if [ $? -eq 0 ]; then
        echo "✅ OS Disk deletion initiated successfully"
    else
        echo "❌ Failed to delete OS Disk"
        exit 1
    fi
else
    echo "ℹ️  OS Disk '$DISK_NAME' not found (may already be deleted)"
fi

echo ""
echo "🎉 VM removal process completed!"
echo ""
echo "📊 Summary:"
echo "   ✅ VM '$VM_NAME' - Removed"
echo "   ✅ Network Interface '$NIC_NAME' - Removed" 
echo "   ✅ OS Disk '$DISK_NAME' - Removed"
echo ""
echo "🔄 To recreate the VM with cloud-init NFS mounting:"
echo "   1. Update vm/main.parameters.json with your SSH public key"
echo "   2. Run: cd vm && ./deploy.sh"
echo ""
echo "🔗 The existing Bastion host will provide immediate access to the new VM!"