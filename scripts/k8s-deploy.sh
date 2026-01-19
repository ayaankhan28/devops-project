#!/bin/bash

# Kubernetes Deployment Script for DevOps FastAPI Project
# This script is executed on the VM to deploy to K3s
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

# Full image name
FULL_IMAGE="${DOCKER_IMAGE}:${IMAGE_TAG}"

# Deployment directories
DEPLOY_DIR="$HOME/deployments/k8s"
LOG_DIR="$HOME/deployments/logs"

# Create directories if they don't exist
mkdir -p "$DEPLOY_DIR" "$LOG_DIR"

# Log file
LOG_FILE="$LOG_DIR/k8s-deploy-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=========================================="
echo "🚀 Kubernetes Deployment to ${ENVIRONMENT}"
echo "=========================================="
log "Kubernetes deployment started"
log "Image: ${FULL_IMAGE}"
log "Namespace: ${ENVIRONMENT}"
log "Port: ${DEPLOYMENT_PORT}"

# Check if K3s is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Is K3s installed?"
    log "ERROR: kubectl not found"
    exit 1
fi

# Set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verify cluster is running
print_info "Verifying Kubernetes cluster..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Kubernetes cluster is not accessible"
    log "ERROR: Kubernetes cluster is not accessible"
    exit 1
fi
print_success "Kubernetes cluster is accessible"
log "Kubernetes cluster verified"

# Check if namespace exists
print_info "Checking namespace: ${ENVIRONMENT}"
if ! kubectl get namespace "${ENVIRONMENT}" &> /dev/null; then
    print_warning "Namespace ${ENVIRONMENT} does not exist, creating..."
    kubectl create namespace "${ENVIRONMENT}"
    kubectl label namespace "${ENVIRONMENT}" environment="${ENVIRONMENT}" app=devops-fastapi
    print_success "Namespace created"
    log "Namespace ${ENVIRONMENT} created"
else
    print_success "Namespace ${ENVIRONMENT} exists"
    log "Namespace ${ENVIRONMENT} verified"
fi

# Update deployment image
print_info "Updating deployment image to ${FULL_IMAGE}..."
log "Updating deployment image..."

# Check if deployment exists
if kubectl get deployment devops-fastapi -n "${ENVIRONMENT}" &> /dev/null; then
    print_info "Deployment exists, updating image..."
    log "Updating existing deployment"
    
    # Save current deployment for rollback
    kubectl get deployment devops-fastapi -n "${ENVIRONMENT}" -o yaml > "${DEPLOY_DIR}/deployment-${ENVIRONMENT}-backup-$(date +%Y%m%d-%H%M%S).yaml"
    
    # Update the image
    kubectl set image deployment/devops-fastapi \
        fastapi="${FULL_IMAGE}" \
        -n "${ENVIRONMENT}" \
        --record
    
    print_success "Deployment image updated"
    log "Deployment image updated to ${FULL_IMAGE}"
else
    print_info "Deployment does not exist, applying manifests..."
    log "Creating new deployment"
    
    # Apply deployment manifest
    if [ -f "${DEPLOY_DIR}/deployment-${ENVIRONMENT}.yaml" ]; then
        # Update image in manifest
        sed "s|image:.*|image: ${FULL_IMAGE}|g" "${DEPLOY_DIR}/deployment-${ENVIRONMENT}.yaml" | kubectl apply -f -
        print_success "Deployment created"
        log "Deployment created from manifest"
    else
        print_error "Deployment manifest not found: ${DEPLOY_DIR}/deployment-${ENVIRONMENT}.yaml"
        log "ERROR: Deployment manifest not found"
        exit 1
    fi
fi

# Apply service if not exists
print_info "Checking service..."
if ! kubectl get service devops-fastapi -n "${ENVIRONMENT}" &> /dev/null; then
    if [ -f "${DEPLOY_DIR}/service-${ENVIRONMENT}.yaml" ]; then
        kubectl apply -f "${DEPLOY_DIR}/service-${ENVIRONMENT}.yaml"
        print_success "Service created"
        log "Service created"
    else
        print_warning "Service manifest not found, skipping..."
        log "WARNING: Service manifest not found"
    fi
else
    print_success "Service already exists"
    log "Service verified"
fi

# Wait for rollout to complete
print_info "Waiting for rollout to complete..."
log "Waiting for rollout..."

if kubectl rollout status deployment/devops-fastapi -n "${ENVIRONMENT}" --timeout=120s; then
    print_success "Rollout completed successfully"
    log "Rollout completed successfully"
else
    print_error "Rollout failed or timed out"
    log "ERROR: Rollout failed"
    
    # Show pod status
    print_info "Pod status:"
    kubectl get pods -n "${ENVIRONMENT}" -l app=devops-fastapi
    
    # Show pod logs
    print_info "Recent pod logs:"
    kubectl logs -n "${ENVIRONMENT}" -l app=devops-fastapi --tail=50 || true
    
    # Attempt rollback
    print_warning "Attempting rollback..."
    log "Attempting rollback..."
    kubectl rollout undo deployment/devops-fastapi -n "${ENVIRONMENT}"
    
    exit 1
fi

# Get pod information
print_info "Getting pod information..."
POD_NAME=$(kubectl get pods -n "${ENVIRONMENT}" -l app=devops-fastapi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    print_error "No pods found"
    log "ERROR: No pods found"
    exit 1
fi

print_success "Pod running: ${POD_NAME}"
log "Pod: ${POD_NAME}"

# Wait for pod to be ready
print_info "Waiting for pod to be ready..."
log "Waiting for pod readiness..."

if kubectl wait --for=condition=ready pod -l app=devops-fastapi -n "${ENVIRONMENT}" --timeout=120s; then
    print_success "Pod is ready"
    log "Pod is ready"
else
    print_error "Pod failed to become ready"
    log "ERROR: Pod not ready"
    
    # Show pod details
    kubectl describe pod "${POD_NAME}" -n "${ENVIRONMENT}"
    kubectl logs "${POD_NAME}" -n "${ENVIRONMENT}" --tail=50 || true
    
    exit 1
fi

# Determine the node port based on environment
if [ "$ENVIRONMENT" = "production" ]; then
    NODE_PORT=30000
else
    NODE_PORT=30001
fi

# Health check
print_info "Running health check on port ${NODE_PORT}..."
log "Running health check..."

MAX_ATTEMPTS=15
ATTEMPT=1
HEALTH_CHECK_PASSED=false

sleep 5  # Give service a moment to be ready

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log "Health check attempt $ATTEMPT/$MAX_ATTEMPTS"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NODE_PORT}/health" || echo "000")
    
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
    log "ERROR: Health check failed"
    
    # Show service info
    print_info "Service information:"
    kubectl get service devops-fastapi -n "${ENVIRONMENT}"
    
    # Show pod logs
    print_info "Pod logs:"
    kubectl logs "${POD_NAME}" -n "${ENVIRONMENT}" --tail=100
    
    exit 1
fi

# Run smoke tests
print_info "Running smoke tests..."
log "Running smoke tests..."

SMOKE_TESTS_PASSED=true

# Test health endpoint
if curl -f "http://localhost:${NODE_PORT}/health" > /dev/null 2>&1; then
    print_success "Health endpoint test passed"
    log "Health endpoint test passed"
else
    print_error "Health endpoint test failed"
    log "ERROR: Health endpoint test failed"
    SMOKE_TESTS_PASSED=false
fi

# Test items endpoint
if curl -f "http://localhost:${NODE_PORT}/items" > /dev/null 2>&1; then
    print_success "Items endpoint test passed"
    log "Items endpoint test passed"
else
    print_error "Items endpoint test failed"
    log "ERROR: Items endpoint test failed"
    SMOKE_TESTS_PASSED=false
fi

# Test root endpoint
if curl -f "http://localhost:${NODE_PORT}/" > /dev/null 2>&1; then
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

# Cleanup old deployment backups (keep last 5)
print_info "Cleaning up old backup manifests..."
log "Cleaning up old backups..."
find "$DEPLOY_DIR" -name "deployment-${ENVIRONMENT}-backup-*.yaml" -type f | sort -r | tail -n +6 | xargs -r rm
print_success "Old backups cleaned up"
log "Old backups cleaned up"

# Display deployment summary
echo ""
echo "=========================================="
echo "🎉 Kubernetes Deployment Successful!"
echo "=========================================="
log "Deployment completed successfully"
echo "Environment: ${ENVIRONMENT}"
echo "Namespace: ${ENVIRONMENT}"
echo "Image: ${FULL_IMAGE}"
echo "Pod: ${POD_NAME}"
echo "NodePort: ${NODE_PORT}"
echo "Status: ✅ Running"
echo "Log file: ${LOG_FILE}"
echo "=========================================="
echo ""

# Show pod status
print_info "Pod Status:"
kubectl get pods -n "${ENVIRONMENT}" -l app=devops-fastapi

# Show service info
echo ""
print_info "Service Info:"
kubectl get service devops-fastapi -n "${ENVIRONMENT}"

# Show pod resource usage
echo ""
print_info "Pod Resource Usage:"
kubectl top pod "${POD_NAME}" -n "${ENVIRONMENT}" 2>/dev/null || echo "Metrics not available (metrics-server disabled)"

log "Deployment summary displayed"
log "Deployment process completed"

exit 0
