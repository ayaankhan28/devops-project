#!/bin/bash

# Remote VM Deployment Script
# This script is executed on the VM to deploy Docker containers
# Called by GitHub Actions CD workflows via SSH

set -e

# Configuration from arguments
ENVIRONMENT=${1:-staging}
DOCKER_IMAGE=${2}
IMAGE_TAG=${3:-latest}
DEPLOYMENT_PORT=${4:-8000}

# Validate required arguments
if [ -z "$DOCKER_IMAGE" ]; then
    echo "❌ Error: DOCKER_IMAGE is required"
    echo "Usage: $0 <environment> <docker_image> <image_tag> <deployment_port>"
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Container name
CONTAINER_NAME="devops-fastapi-${ENVIRONMENT}"
BACKUP_CONTAINER_NAME="${CONTAINER_NAME}-backup-$(date +%Y%m%d-%H%M%S)"
FULL_IMAGE="${DOCKER_IMAGE}:${IMAGE_TAG}"

# Deployment directories
DEPLOY_DIR="$HOME/deployments/${ENVIRONMENT}"
LOG_DIR="$HOME/deployments/logs"
BACKUP_DIR="$HOME/deployments/backups"

# Create directories if they don't exist
mkdir -p "$DEPLOY_DIR" "$LOG_DIR" "$BACKUP_DIR"

# Log file
LOG_FILE="$LOG_DIR/deploy-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=========================================="
echo "🚀 Starting Deployment to ${ENVIRONMENT}"
echo "=========================================="
log "Deployment started"
log "Image: ${FULL_IMAGE}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${DEPLOYMENT_PORT}"

# Pull latest Docker image
print_info "Pulling Docker image: ${FULL_IMAGE}"
log "Pulling Docker image..."
if docker pull "${FULL_IMAGE}"; then
    print_success "Docker image pulled successfully"
    log "Docker image pulled successfully"
else
    print_error "Failed to pull Docker image"
    log "ERROR: Failed to pull Docker image"
    exit 1
fi

# Check if container is running
if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
    print_info "Container ${CONTAINER_NAME} is currently running"
    log "Existing container found: ${CONTAINER_NAME}"
    
    # Create backup of current container
    print_info "Creating backup of current container..."
    log "Creating backup..."
    if docker commit "${CONTAINER_NAME}" "${BACKUP_CONTAINER_NAME}" > /dev/null 2>&1; then
        print_success "Backup created: ${BACKUP_CONTAINER_NAME}"
        log "Backup created: ${BACKUP_CONTAINER_NAME}"
        
        # Save backup metadata
        echo "${FULL_IMAGE}" > "${BACKUP_DIR}/${BACKUP_CONTAINER_NAME}.txt"
    else
        print_warning "Failed to create backup (continuing anyway)"
        log "WARNING: Failed to create backup"
    fi
    
    # Stop existing container
    print_info "Stopping existing container..."
    log "Stopping container..."
    if docker stop "${CONTAINER_NAME}" > /dev/null 2>&1; then
        print_success "Container stopped"
        log "Container stopped successfully"
    else
        print_warning "Failed to stop container gracefully"
        log "WARNING: Failed to stop container gracefully"
    fi
    
    # Remove existing container
    print_info "Removing existing container..."
    log "Removing container..."
    if docker rm "${CONTAINER_NAME}" > /dev/null 2>&1; then
        print_success "Container removed"
        log "Container removed successfully"
    else
        print_warning "Failed to remove container"
        log "WARNING: Failed to remove container"
    fi
else
    print_info "No existing container found"
    log "No existing container found"
fi

# Deploy new container
print_info "Deploying new container..."
log "Starting new container..."

if docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${DEPLOYMENT_PORT}:8000" \
    --restart unless-stopped \
    -e ENVIRONMENT="${ENVIRONMENT}" \
    "${FULL_IMAGE}"; then
    print_success "Container started successfully"
    log "Container started successfully"
else
    print_error "Failed to start container"
    log "ERROR: Failed to start container"
    
    # Attempt rollback if backup exists
    if docker images -q "${BACKUP_CONTAINER_NAME}" | grep -q .; then
        print_warning "Attempting rollback to backup..."
        log "Attempting rollback..."
        
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -p "${DEPLOYMENT_PORT}:8000" \
            --restart unless-stopped \
            -e ENVIRONMENT="${ENVIRONMENT}" \
            "${BACKUP_CONTAINER_NAME}"
        
        print_info "Rolled back to previous version"
        log "Rolled back to previous version"
    fi
    
    exit 1
fi

# Wait for application to start
print_info "Waiting for application to start..."
log "Waiting for application startup..."
sleep 10

# Health check
print_info "Running health check..."
log "Running health check..."

MAX_ATTEMPTS=15
ATTEMPT=1
HEALTH_CHECK_PASSED=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log "Health check attempt $ATTEMPT/$MAX_ATTEMPTS"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${DEPLOYMENT_PORT}/health" || echo "000")
    
    if [ "$HTTP_CODE" -eq 200 ]; then
        print_success "Health check passed (HTTP $HTTP_CODE)"
        log "Health check passed (HTTP $HTTP_CODE)"
        HEALTH_CHECK_PASSED=true
        break
    fi
    
    print_info "Health check attempt $ATTEMPT/$MAX_ATTEMPTS (HTTP $HTTP_CODE)"
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$HEALTH_CHECK_PASSED" = false ]; then
    print_error "Health check failed after $MAX_ATTEMPTS attempts"
    log "ERROR: Health check failed after $MAX_ATTEMPTS attempts"
    
    # Get container logs
    print_info "Container logs:"
    docker logs "${CONTAINER_NAME}" --tail 50 | tee -a "$LOG_FILE"
    
    # Rollback
    print_warning "Rolling back to previous version..."
    log "Initiating rollback..."
    
    docker stop "${CONTAINER_NAME}" > /dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" > /dev/null 2>&1 || true
    
    if docker images -q "${BACKUP_CONTAINER_NAME}" | grep -q .; then
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -p "${DEPLOYMENT_PORT}:8000" \
            --restart unless-stopped \
            -e ENVIRONMENT="${ENVIRONMENT}" \
            "${BACKUP_CONTAINER_NAME}"
        
        print_info "Rolled back to previous version"
        log "Rolled back to previous version"
        
        # Verify rollback
        sleep 10
        ROLLBACK_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${DEPLOYMENT_PORT}/health" || echo "000")
        if [ "$ROLLBACK_HTTP_CODE" -eq 200 ]; then
            print_success "Rollback successful"
            log "Rollback successful"
        else
            print_error "Rollback failed - manual intervention required"
            log "ERROR: Rollback failed"
        fi
    else
        print_error "No backup available - manual intervention required"
        log "ERROR: No backup available for rollback"
    fi
    
    exit 1
fi

# Run smoke tests
print_info "Running smoke tests..."
log "Running smoke tests..."

SMOKE_TESTS_PASSED=true

# Test health endpoint
if curl -f "http://localhost:${DEPLOYMENT_PORT}/health" > /dev/null 2>&1; then
    print_success "Health endpoint test passed"
    log "Health endpoint test passed"
else
    print_error "Health endpoint test failed"
    log "ERROR: Health endpoint test failed"
    SMOKE_TESTS_PASSED=false
fi

# Test items endpoint
if curl -f "http://localhost:${DEPLOYMENT_PORT}/items" > /dev/null 2>&1; then
    print_success "Items endpoint test passed"
    log "Items endpoint test passed"
else
    print_error "Items endpoint test failed"
    log "ERROR: Items endpoint test failed"
    SMOKE_TESTS_PASSED=false
fi

# Test root endpoint
if curl -f "http://localhost:${DEPLOYMENT_PORT}/" > /dev/null 2>&1; then
    print_success "Root endpoint test passed"
    log "Root endpoint test passed"
else
    print_error "Root endpoint test failed"
    log "ERROR: Root endpoint test failed"
    SMOKE_TESTS_PASSED=false
fi

if [ "$SMOKE_TESTS_PASSED" = false ]; then
    print_error "Smoke tests failed"
    log "ERROR: Smoke tests failed"
    exit 1
fi

# Cleanup old backups (keep last 5)
print_info "Cleaning up old backups..."
log "Cleaning up old backups..."
docker images | grep "${CONTAINER_NAME}-backup" | awk '{print $1":"$2}' | tail -n +6 | xargs -r docker rmi > /dev/null 2>&1 || true
print_success "Old backups cleaned up"
log "Old backups cleaned up"

# Cleanup old logs (keep last 30 days)
find "$LOG_DIR" -name "deploy-${ENVIRONMENT}-*.log" -mtime +30 -delete 2>/dev/null || true

# Display deployment summary
echo ""
echo "=========================================="
echo "🎉 Deployment Successful!"
echo "=========================================="
log "Deployment completed successfully"
echo "Environment: ${ENVIRONMENT}"
echo "Image: ${FULL_IMAGE}"
echo "Container: ${CONTAINER_NAME}"
echo "Port: ${DEPLOYMENT_PORT}"
echo "Status: ✅ Running"
echo "Log file: ${LOG_FILE}"
echo "=========================================="
echo ""

# Show container status
docker ps | grep "${CONTAINER_NAME}"

# Show container resource usage
echo ""
print_info "Container resource usage:"
docker stats "${CONTAINER_NAME}" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

log "Deployment summary displayed"
log "Deployment process completed"

exit 0
