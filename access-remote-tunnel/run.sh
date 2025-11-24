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


###############################################################
#                     UPDATE configuration.yaml               #
###############################################################

# -------- Ensure http: block exists and is correct --------

if ! grep -q '^http:' "$CONFIG_FILE"; then
    echo -e "\nhttp:" >> "$CONFIG_FILE"
    echo "  use_x_forwarded_for: true" >> "$CONFIG_FILE"
    echo "  trusted_proxies:" >> "$CONFIG_FILE"
    echo "    - 172.17.0.0/16" >> "$CONFIG_FILE"
else
    # Add use_x_forwarded_for if missing in http: block
    if ! sed -n '/^http:/,/^[^ ]/p' "$CONFIG_FILE" | grep -q 'use_x_forwarded_for:'; then
        sed -i '/^http:/a\  use_x_forwarded_for: true' "$CONFIG_FILE"
    fi

    # Add trusted_proxies if missing
    if ! sed -n '/^http:/,/^[^ ]/p' "$CONFIG_FILE" | grep -q 'trusted_proxies:'; then
        sed -i '/^http:/a\  trusted_proxies:\n    - 172.17.0.0/16' "$CONFIG_FILE"
    fi
fi

# Ensure 0.0.0.0/0 exists under trusted_proxies
if ! sed -n '/^http:/,/^[^ ]/p' "$CONFIG_FILE" | grep -q '172.17.0.0/16'; then
    sed -i '/trusted_proxies:/a\    - 172.17.0.0/16' "$CONFIG_FILE"
fi


# -------- Ensure homeassistant: block + external_url --------

if ! grep -q '^homeassistant:' "$CONFIG_FILE"; then
    echo -e "\nhomeassistant:" >> "$CONFIG_FILE"
fi

# Replace or insert external_url under homeassistant: block
sed -i "\|^homeassistant:|,/^[^ ]/ s|^\s*external_url:.*$|  external_url: $EXTERNAL_URL|" "$CONFIG_FILE"

# If no external_url exists yet, add it
if ! sed -n '/^homeassistant:/,/^[^ ]/p' "$CONFIG_FILE" | grep -q 'external_url:'; then
    sed -i "/^homeassistant:/a\  external_url: $EXTERNAL_URL" "$CONFIG_FILE"
fi


###############################################################
#                      SSH Tunnel Loop                        #
###############################################################

while true; do
    echo "Establishing SSH tunnel..."
    ssh -p "$PORT" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -R "${SUBDOMAIN}:80:homeassistant:${LOCAL_PORT}" tunnel@"$SERVER"
    
    echo "SSH tunnel disconnected. Reconnecting in 5 seconds..."
    sleep 5
done
