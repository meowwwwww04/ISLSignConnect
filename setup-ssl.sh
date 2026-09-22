#!/bin/bash
# SignConnect SSL Setup (Nginx + Let's Encrypt)
# Run AFTER deploy.sh and AFTER you have a domain pointing to your VM

set -e

if [ -z "$1" ]; then
  echo "Usage: ./setup-ssl.sh yourdomain.com"
  echo "Example: ./setup-ssl.sh signconnect.yourdomain.com"
  echo ""
  echo "If you don't have a domain, you can use a free one:"
  1. Go to https://www.freenom.com"
  2. Get a free .tk or .ml domain"
  3. Point it to your VM's public IP"
  exit 1
fi

DOMAIN=$1

echo "========================================="
echo "  Setting up HTTPS for $DOMAIN"
echo "========================================="

# Install Nginx
echo "[1/4] Installing Nginx..."
sudo apt install -y nginx

# Install Certbot
echo "[2/4] Installing Certbot for Let's Encrypt..."
sudo apt install -y certbot python3-certbot-nginx

# Create Nginx config
echo "[3/4] Configuring Nginx..."
sudo tee /etc/nginx/sites-available/signconnect > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/signconnect /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Get SSL certificate
echo "[4/4] Getting SSL certificate from Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

# Auto-renewal
echo "Setting up auto-renewal..."
sudo systemctl enable certbot.timer

echo ""
echo "========================================="
echo "  HTTPS Setup Complete!"
echo "========================================="
echo ""
echo "  Your app is now available at:"
echo "  https://$DOMAIN"
echo ""
echo "  Camera access works on all devices!"
echo "========================================="
