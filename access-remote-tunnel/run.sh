#!/bin/bash
set -e

# --- Configurable via environment variables ---
SERVER=${SSH_SERVER:-tunnel.awdqr.com}
PORT=${SSH_PORT:-2222}
LOCAL_PORT=${LOCAL_PORT:-8123}

# Persistent file location inside mapped volume
SUBDOMAIN_FILE="/config/.subdomain.txt"
CONFIG_FILE="/config/configuration.yaml"

# Generate a random 4-letter + 4-number subdomain
generate_subdomain() {
    letters=$(tr -dc 'A-Z' </dev/urandom | head -c4)
    numbers=$(tr -dc '0-9' </dev/urandom | head -c4)
    echo "${letters}${numbers}"
}

# Determine the subdomain
if [ -f "$SUBDOMAIN_FILE" ]; then
    SUBDOMAIN=$(cat "$SUBDOMAIN_FILE")
else
    SUBDOMAIN=$(generate_subdomain)
    echo "$SUBDOMAIN" > "$SUBDOMAIN_FILE"
fi

EXTERNAL_URL="https://${SUBDOMAIN}.awdqr.com"

echo "Starting SSH tunnel..."
echo "Subdomain: $SUBDOMAIN"
echo "Forwarding $LOCAL_PORT to $SERVER:$PORT"
echo "Setting Home Assistant external_url: $EXTERNAL_URL"

# --- Update configuration.yaml ---
# Check if 'homeassistant:' exists; if not, add it
if ! grep -q "^homeassistant:" "$CONFIG_FILE"; then
    echo -e "\nhomeassistant:" >> "$CONFIG_FILE"
fi

# Remove any existing external_url line under homeassistant:
sed -i "\|^homeassistant:|,/^[^ ]/ s|^\s*external_url:.*$|  external_url: $EXTERNAL_URL|" "$CONFIG_FILE"

# If no external_url line was replaced, append it under homeassistant:
if ! grep -q "external_url: $EXTERNAL_URL" "$CONFIG_FILE"; then
    sed -i "/^homeassistant:/a \  external_url: $EXTERNAL_URL" "$CONFIG_FILE"
fi

# --- Auto-reconnect loop ---
while true; do
    echo "Establishing SSH tunnel..."
    ssh -p "$PORT" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -R "${SUBDOMAIN}:80:homeassistant:${LOCAL_PORT}" tunnel@"$SERVER"
    
    echo "SSH tunnel disconnected. Reconnecting in 5 seconds..."
    sleep 5
done
