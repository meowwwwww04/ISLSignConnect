#!/bin/bash
# SignConnect Deployment Script
# Run this on your Oracle Cloud VM after uploading the project

set -e

echo "========================================="
echo "  SignConnect Server Deployment"
echo "========================================="

# Update system
echo "[1/7] Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

# Install Node.js 18.x
echo "[2/7] Installing Node.js..."
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  sudo apt install -y nodejs
fi
echo "Node.js $(node -v) installed"
echo "npm $(npm -v) installed"

# Install PM2 globally
echo "[3/7] Installing PM2 process manager..."
sudo npm install -g pm2

# Install coturn (TURN server)
echo "[4/7] Installing coturn TURN server..."
if ! command -v turnserver &> /dev/null; then
  sudo apt install -y coturn
fi

# Detect public and private IPs
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 icanhazip.com)
PRIVATE_IP=$(hostname -I | awk '{print $1}')

if [ -z "$PUBLIC_IP" ]; then
  echo "  WARNING: Could not detect public IP. Set TURN_HOST manually in .env"
else
  echo "  Detected public IP: $PUBLIC_IP"
  echo "  Detected private IP: $PRIVATE_IP"
fi

# Generate TURN secret if not already set
TURN_SECRET_FILE="/home/ubuntu/signconnect/.turn-secret"
if [ ! -f "$TURN_SECRET_FILE" ]; then
  NEW_SECRET=$(openssl rand -hex 32)
  echo "$NEW_SECRET" > "$TURN_SECRET_FILE"
  chmod 600 "$TURN_SECRET_FILE"
  echo "  Generated new TURN secret: $TURN_SECRET_FILE"
else
  echo "  Using existing TURN secret: $TURN_SECRET_FILE"
fi
TURN_SECRET=$(cat "$TURN_SECRET_FILE")

# Configure coturn
echo "[5/7] Configuring coturn..."
sudo cp turnserver.conf /etc/turnserver.conf
sudo sed -i "s|static-auth-secret=.*|static-auth-secret=$TURN_SECRET|" /etc/turnserver.conf
if [ -n "$PUBLIC_IP" ] && [ -n "$PRIVATE_IP" ]; then
  sudo sed -i "s|# external-ip=<PUBLIC_IP>/<PRIVATE_IP>|external-ip=$PUBLIC_IP/$PRIVATE_IP|" /etc/turnserver.conf
fi

# Enable coturn as a systemd service
sudo systemctl enable coturn
sudo systemctl restart coturn
echo "  coturn service started on port 3478 (UDP/TCP) and 5349 (TLS)"

# Configure coturn firewall rules
sudo ufw allow 3478/udp
sudo ufw allow 3478/tcp
sudo ufw allow 5349/tcp
sudo ufw allow 49152:65535/udp

# Install project dependencies
echo "[6/7] Installing project dependencies..."
cd /home/ubuntu/signconnect
npm install --production

# Update .env with TURN config
ENV_FILE="/home/ubuntu/signconnect/.env"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
PORT=8080
TURN_HOST=$PUBLIC_IP
TURN_SECRET=$TURN_SECRET
TURN_PORT=3478
TURN_TLS_PORT=5349
EOF
  echo "  Created .env with TURN config"
else
  echo "  .env already exists — update TURN_HOST and TURN_SECRET manually if needed"
fi

# Start the server with PM2
echo "[7/7] Starting SignConnect server..."
pm2 delete signconnect 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save
pm2 startup | grep "sudo" | bash || true

# Open firewall ports
echo "Configuring firewall..."
sudo ufw allow 8080/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable

echo ""
echo "========================================="
echo "  Deployment Complete!"
echo "========================================="
echo ""
echo "  Signaling Server: http://$(curl -s ifconfig.me):8080"
echo "  TURN Server:      turn:$(curl -s ifconfig.me):3478"
echo ""
echo "  TURN Secret saved at: $TURN_SECRET_FILE"
echo "  coturn is running as systemd service (auto-restarts on reboot)"
echo ""
echo "  Share the signaling URL with anyone, anywhere in India!"
echo "========================================="
