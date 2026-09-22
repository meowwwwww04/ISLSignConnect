#!/usr/bin/env bash
# Run this in your terminal: bash setup-metered-key.sh
set -euo pipefail
ENV_FILE="$(dirname "$0")/.env"

echo ""
echo "=== Metered.ca API Key Setup ==="
echo ""
echo "1. Go to https://dashboard.metered.ca → sign up or log in"
echo "2. Click 'API Keys' in the left sidebar"
echo "3. Copy your API key"
echo ""
read -rsp "Paste your API key here: " KEY
echo ""

if [ -z "$KEY" ]; then
  echo "Empty key — aborting."
  exit 1
fi

cat > "$ENV_FILE" <<EOF
PORT=8080
METERED_API_KEY=$KEY
METERED_API_URL=https://openrelay.metered.ca/api/v1/turn/credentials
EOF

echo ""
echo "Done. .env created at $ENV_FILE"
echo "Verifying..."

# Verify without printing the full key
KEY_LEN=${#KEY}
echo "  METERED_API_KEY: ${KEY:0:4}...${KEY: -4} (${KEY_LEN} chars)"
echo "  Format: OK"
