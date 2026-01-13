#!/bin/bash

# Deployment script for FastAPI application
# Usage: ./deploy.sh <environment> <version>
# Example: ./deploy.sh staging latest

set -e

# Configuration
ENVIRONMENT=${1:-staging}
VERSION=${2:-latest}
DOCKER_IMAGE="${DOCKERHUB_USERNAME}/devops-fastapi:${VERSION}"
CONTAINER_NAME="devops-fastapi-${ENVIRONMENT}"

# Port configuration
if [ "$ENVIRONMENT" = "production" ]; then
    PORT=8000
else
    PORT=8001
fi

echo "🚀 Starting deployment to ${ENVIRONMENT}"
echo "================================"
echo "Image: ${DOCKER_IMAGE}"
echo "Container: ${CONTAINER_NAME}"
echo "Port: ${PORT}"
echo "================================"

# Pull latest image
echo "📦 Pulling Docker image..."
docker pull "${DOCKER_IMAGE}"

# Stop existing container
echo "🔄 Stopping existing container..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

# Start new container
echo "🚀 Starting new container..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:8000" \
    --restart unless-stopped \
    -e ENVIRONMENT="${ENVIRONMENT}" \
    "${DOCKER_IMAGE}"

# Wait for application to start
echo "⏳ Waiting for application to start..."
sleep 10

# Health check
echo "🔍 Running health check..."
if ./scripts/health-check.sh "${PORT}"; then
    echo "✅ Deployment successful!"
    echo "================================"
    echo "Application is running on port ${PORT}"
    echo "Health: http://localhost:${PORT}/health"
    echo "API Docs: http://localhost:${PORT}/docs"
    echo "================================"
    exit 0
else
    echo "❌ Deployment failed - Health check did not pass"
    echo "🔄 Rolling back..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    exit 1
fi
