#!/bin/bash

# SSL Setup Script for kanban.diligentcrossbill.com.ru
set -e

DOMAIN="kanban.diligentcrossbill.com.ru"
EMAIL="your-email@example.com"  # Замените на ваш email

echo "🔒 Setting up SSL for $DOMAIN"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Stop Docker containers
echo "Stopping Docker containers..."
cd /opt/saas-platform
docker compose down

# Install Certbot if not installed
if ! command -v certbot &> /dev/null; then
    echo "Installing Certbot..."
    apt update
    apt install -y certbot
fi

# Get SSL certificate
echo "Obtaining SSL certificate for $DOMAIN..."
certbot certonly --standalone \
    -d $DOMAIN \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    --preferred-challenges http

# Check if certificate was obtained
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "❌ Failed to obtain SSL certificate"
    exit 1
fi

echo "✅ SSL certificate obtained successfully"

# Update docker-compose.yml to use SSL config
echo "Updating Docker configuration..."
cat > /opt/saas-platform/docker-compose-ssl.yml << 'EOF'
version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: saas-platform-web
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx-ssl.conf:/etc/nginx/conf.d/default.conf
    environment:
      - NODE_ENV=production
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  app-network:
    driver: bridge
EOF

# Start containers with SSL
echo "Starting containers with SSL..."
docker compose -f docker-compose-ssl.yml up -d --build

# Setup auto-renewal
echo "Setting up automatic certificate renewal..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && docker compose -f /opt/saas-platform/docker-compose-ssl.yml restart") | crontab -

echo "✅ SSL setup completed!"
echo "Your site is now available at: https://$DOMAIN"
