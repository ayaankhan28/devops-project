#!/bin/bash
###############################################################################
# K3s Installation Script for DevOps FastAPI Project
# Optimized for 512MB RAM Digital Ocean Droplet
# Run this ONCE on your VM to set up Kubernetes
###############################################################################

set -e  # Exit on error

echo "=========================================="
echo "K3s Installation for DevOps FastAPI"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root or with sudo${NC}"
    exit 1
fi

# Check system resources
echo -e "${YELLOW}📊 Checking system resources...${NC}"
total_mem=$(free -m | awk 'NR==2{print $2}')
echo "Total RAM: ${total_mem}MB"

if [ "$total_mem" -lt 400 ]; then
    echo -e "${RED}❌ Warning: Less than 400MB RAM available. K3s may not run properly.${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if K3s is already installed
if command -v k3s &> /dev/null; then
    echo -e "${YELLOW}⚠️  K3s is already installed${NC}"
    k3s --version
    read -p "Reinstall K3s? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  Uninstalling existing K3s...${NC}"
        /usr/local/bin/k3s-uninstall.sh || true
    else
        echo -e "${GREEN}✅ Using existing K3s installation${NC}"
        exit 0
    fi
fi

# Install K3s in lightweight mode
echo -e "${YELLOW}📦 Installing K3s (lightweight mode)...${NC}"
echo "This will take 1-2 minutes..."

curl -sfL https://get.k3s.io | sh -s - \
    --disable traefik \
    --disable servicelb \
    --disable metrics-server \
    --disable local-storage \
    --write-kubeconfig-mode 644 \
    --kube-apiserver-arg="--service-node-port-range=30000-32767"

# Wait for K3s to be ready
echo -e "${YELLOW}⏳ Waiting for K3s to be ready...${NC}"
sleep 10

# Check K3s status
if systemctl is-active --quiet k3s; then
    echo -e "${GREEN}✅ K3s service is running${NC}"
else
    echo -e "${RED}❌ K3s service failed to start${NC}"
    systemctl status k3s
    exit 1
fi

# Configure kubectl for non-root user (if not root)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    echo -e "${YELLOW}🔧 Configuring kubectl for user: $SUDO_USER${NC}"
    
    mkdir -p "$USER_HOME/.kube"
    cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"
    chown -R $SUDO_USER:$SUDO_USER "$USER_HOME/.kube"
    chmod 600 "$USER_HOME/.kube/config"
    
    echo -e "${GREEN}✅ kubectl configured for $SUDO_USER${NC}"
fi

# Set KUBECONFIG for current session
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verify kubectl works
echo -e "${YELLOW}🔍 Verifying kubectl...${NC}"
kubectl version --short || kubectl version

# Wait for node to be ready
echo -e "${YELLOW}⏳ Waiting for node to be ready...${NC}"
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get nodes | grep -q "Ready"; then
        echo -e "${GREEN}✅ Node is ready${NC}"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${RED}❌ Timeout waiting for node to be ready${NC}"
    exit 1
fi

# Create namespaces
echo -e "${YELLOW}📁 Creating namespaces...${NC}"

kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace staging environment=staging app=devops-fastapi --overwrite

kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace production environment=production app=devops-fastapi --overwrite

echo -e "${GREEN}✅ Namespaces created${NC}"

# Create deployment directory structure
echo -e "${YELLOW}📂 Creating deployment directories...${NC}"
mkdir -p ~/deployments/scripts
mkdir -p ~/deployments/k8s
chmod 755 ~/deployments
chmod 755 ~/deployments/scripts
chmod 755 ~/deployments/k8s

echo -e "${GREEN}✅ Directories created${NC}"

# Display cluster info
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 K3s Installation Complete!${NC}"
echo "=========================================="
echo ""
echo "Cluster Information:"
kubectl get nodes
echo ""
echo "Namespaces:"
kubectl get namespaces | grep -E "staging|production|NAME"
echo ""
echo "System Resources:"
free -h
echo ""
echo "=========================================="
echo "Next Steps:"
echo "1. Your CD pipeline will automatically deploy to this cluster"
echo "2. Access staging:    http://YOUR_VM_IP:30001/health"
echo "3. Access production: http://YOUR_VM_IP:30000/health"
echo ""
echo "Useful Commands:"
echo "  kubectl get all -n staging"
echo "  kubectl get all -n production"
echo "  kubectl logs -f deployment/devops-fastapi -n staging"
echo "  kubectl describe pod -n production"
echo "=========================================="
