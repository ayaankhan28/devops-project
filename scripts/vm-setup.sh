#!/bin/bash

# VM Setup Script for CI/CD Deployment
# This script prepares a VM for Docker-based deployments
# Run this script once on your VM to set up the environment

set -e

echo "🚀 Starting VM Setup for CI/CD Deployment"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if running as root or with sudo
if [[ $EUID -eq 0 ]]; then
    print_info "Running as root"
    SUDO=""
else
    print_info "Running with sudo"
    SUDO="sudo"
fi

# Update system packages
print_info "Updating system packages..."
$SUDO apt-get update -y
$SUDO apt-get upgrade -y
print_success "System packages updated"

# Install required dependencies
print_info "Installing required dependencies..."
$SUDO apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    wget \
    unzip
print_success "Dependencies installed"

# Install Docker
print_info "Checking if Docker is installed..."
if command -v docker &> /dev/null; then
    print_info "Docker is already installed: $(docker --version)"
    read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping Docker installation"
        SKIP_DOCKER=true
    fi
fi

if [ "$SKIP_DOCKER" != true ]; then
    print_info "Installing Docker..."
    
    # Add Docker's official GPG key
    $SUDO install -m 0755 -d /etc/apt/keyrings
    $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_success "Docker installed successfully"
fi

# Start and enable Docker service
print_info "Starting Docker service..."
$SUDO systemctl start docker
$SUDO systemctl enable docker
print_success "Docker service started and enabled"

# Add current user to docker group (if not root)
if [[ $EUID -ne 0 ]]; then
    print_info "Adding current user to docker group..."
    $SUDO usermod -aG docker $USER
    print_success "User added to docker group (logout and login to apply)"
fi

# Verify Docker installation
print_info "Verifying Docker installation..."
$SUDO docker run hello-world > /dev/null 2>&1
print_success "Docker is working correctly"

# Install Python
print_info "Checking if Python 3 is installed..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    print_info "Python is already installed: $PYTHON_VERSION"
    
    # Check if it's Python 3.11 or higher
    PYTHON_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
    if [ "$PYTHON_MINOR" -lt 11 ]; then
        print_info "Python version is older than 3.11, installing Python 3.11..."
        INSTALL_PYTHON=true
    fi
else
    print_info "Python 3 not found, installing Python 3.11..."
    INSTALL_PYTHON=true
fi

if [ "$INSTALL_PYTHON" = true ]; then
    print_info "Installing Python 3.11 and dependencies..."
    
    # Add deadsnakes PPA for latest Python versions
    $SUDO add-apt-repository ppa:deadsnakes/ppa -y
    $SUDO apt-get update -y
    
    # Install Python 3.11
    $SUDO apt-get install -y \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        python3-pip \
        build-essential
    
    # Set Python 3.11 as default python3 (optional)
    $SUDO update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
    
    print_success "Python 3.11 installed successfully"
else
    # Ensure pip and venv are installed
    print_info "Ensuring pip and venv are installed..."
    $SUDO apt-get install -y python3-pip python3-venv
    print_success "Python dependencies verified"
fi

# Upgrade pip
print_info "Upgrading pip..."
python3 -m pip install --upgrade pip --user
print_success "pip upgraded"

# Verify Python installation
print_info "Verifying Python installation..."
PYTHON_VERSION=$(python3 --version)
PIP_VERSION=$(python3 -m pip --version)
print_success "Python verified: $PYTHON_VERSION"
print_success "pip verified: $PIP_VERSION"

# Create deployment directories
print_info "Creating deployment directories..."
mkdir -p ~/deployments/{staging,production}
mkdir -p ~/deployments/logs
mkdir -p ~/deployments/backups
print_success "Deployment directories created"

# Configure Docker daemon for better performance
print_info "Configuring Docker daemon..."
$SUDO mkdir -p /etc/docker
cat <<EOF | $SUDO tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF
$SUDO systemctl restart docker
print_success "Docker daemon configured"

# Configure firewall (UFW)
print_info "Configuring firewall..."
if command -v ufw &> /dev/null; then
    # Allow SSH
    $SUDO ufw allow 22/tcp
    
    # Allow HTTP/HTTPS
    $SUDO ufw allow 80/tcp
    $SUDO ufw allow 443/tcp
    
    # Allow application ports (staging and production)
    $SUDO ufw allow 8000/tcp comment 'Production App'
    $SUDO ufw allow 8001/tcp comment 'Staging App'
    
    # Enable firewall (if not already enabled)
    $SUDO ufw --force enable
    print_success "Firewall configured"
else
    print_info "UFW not found, skipping firewall configuration"
fi

# # Create deployment script directory
# print_info "Setting up deployment scripts..."
# mkdir -p ~/deployments/scripts
# print_success "Deployment scripts directory created"

# # Create a simple health check script
# cat > ~/deployments/scripts/health-check.sh <<'EOF'
# #!/bin/bash
# # Health check script for deployed applications

PORT=${1:-8000}
MAX_ATTEMPTS=${2:-10}

for i in $(seq 1 $MAX_ATTEMPTS); do
    echo "Health check attempt $i/$MAX_ATTEMPTS"
    if curl -f http://localhost:$PORT/health > /dev/null 2>&1; then
        echo "✅ Health check passed"
        exit 0
    fi
    sleep 3
done

echo "❌ Health check failed after $MAX_ATTEMPTS attempts"
exit 1
EOF
chmod +x ~/deployments/scripts/health-check.sh
print_success "Health check script created"

# Install Docker Compose (standalone)
print_info "Installing Docker Compose standalone..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
$SUDO curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
$SUDO chmod +x /usr/local/bin/docker-compose
print_success "Docker Compose installed: $DOCKER_COMPOSE_VERSION"

# Clean up Docker system
print_info "Cleaning up Docker system..."
$SUDO docker system prune -f
print_success "Docker system cleaned"

# Display system information
echo ""
echo "=========================================="
echo "🎉 VM Setup Complete!"
echo "=========================================="
echo ""
echo "📋 System Information:"
echo "  - OS: $(lsb_release -d | cut -f2)"
echo "  - Docker: $(docker --version)"
echo "  - Docker Compose: $(docker-compose --version)"
echo "  - Python: $(python3 --version)"
echo "  - pip: $(python3 -m pip --version | cut -d' ' -f1-2)"
echo ""
echo "📁 Deployment Directories:"
echo "  - Staging: ~/deployments/staging"
echo "  - Production: ~/deployments/production"
echo "  - Logs: ~/deployments/logs"
echo "  - Backups: ~/deployments/backups"
echo "  - Scripts: ~/deployments/scripts"
echo ""
echo "🔒 Firewall Status:"
$SUDO ufw status | grep -E "Status|8000|8001|22|80|443" || echo "  Firewall not configured"
echo ""
echo "⚠️  Important Notes:"
echo "  1. If you added your user to the docker group, logout and login for it to take effect"
echo "  2. Configure GitHub Actions secrets with SSH credentials"
echo "  3. Test SSH connectivity from GitHub Actions"
echo "  4. Review firewall rules and adjust as needed"
echo ""
echo "🔑 Next Steps:"
echo "  1. Generate SSH key for GitHub Actions: ssh-keygen -t ed25519 -C 'github-actions'"
echo "  2. Add public key to ~/.ssh/authorized_keys"
echo "  3. Add private key to GitHub Secrets as VM_SSH_KEY"
echo "  4. Set VM_HOST, VM_USER, VM_SSH_PORT in GitHub Secrets"
echo ""
echo "=========================================="
