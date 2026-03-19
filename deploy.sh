#!/bin/bash

# Deployment script for SaaS Platform
set -e

echo "🚀 Starting deployment..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Pull latest changes
echo -e "${YELLOW}📥 Pulling latest changes...${NC}"
git pull origin main

# Stop running containers
echo -e "${YELLOW}🛑 Stopping containers...${NC}"
docker-compose down

# Build new images
echo -e "${YELLOW}🔨 Building Docker images...${NC}"
docker-compose build --no-cache

# Start containers
echo -e "${YELLOW}🚀 Starting containers...${NC}"
docker-compose up -d

# Wait for health check
echo -e "${YELLOW}⏳ Waiting for application to be healthy...${NC}"
sleep 10

# Check if container is running
if [ "$(docker ps -q -f name=saas-platform-web)" ]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    docker-compose ps
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    docker-compose logs
    exit 1
fi

# Clean up old images
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
docker system prune -af --volumes

echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
