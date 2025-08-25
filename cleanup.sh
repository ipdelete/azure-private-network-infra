#!/bin/bash

# Script to delete Azure resource group: aet-pi-localdev-es2-tst3

RESOURCE_GROUP="aet-pi-localdev-es2-tst3"

echo "Deleting resource group: $RESOURCE_GROUP"
echo "Warning: This will permanently delete all resources in the resource group!"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting resource group $RESOURCE_GROUP..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "Delete command issued. Use 'az group show --name $RESOURCE_GROUP' to check status."
else
    echo "Operation cancelled."
fi