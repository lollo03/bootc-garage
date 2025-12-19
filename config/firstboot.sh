#!/bin/bash

GARAGE_CONFIG="/etc/garage.toml"

# Only run if placeholders still exist
if grep -q "__RPC_SECRET__" "$GARAGE_CONFIG"; then
    echo "Generating Garage secrets..."
    
    RPC_SECRET=$(openssl rand -hex 32)
    ADMIN_TOKEN=$(openssl rand -base64 32)
    METRICS_TOKEN=$(openssl rand -base64 32)

    sed -i "s|__RPC_SECRET__|$RPC_SECRET|g" "$GARAGE_CONFIG"
    sed -i "s|__ADMIN_TOKEN__|$ADMIN_TOKEN|g" "$GARAGE_CONFIG"
    sed -i "s|__METRICS_TOKEN__|$METRICS_TOKEN|g" "$GARAGE_CONFIG"
    
    echo "Secrets generated. Restarting Garage."
    systemctl enable --now garage
    systemctl enable --now garage-webui
else
    echo "Garage secrets already set."
fi