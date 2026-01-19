#!/bin/bash

# SSH Key Setup Helper Script
# Run this on your VM to generate and configure SSH keys for GitHub Actions

set -e

echo "=========================================="
echo "🔑 GitHub Actions SSH Key Setup"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Key file path
KEY_FILE="$HOME/.ssh/github_actions_deploy"

# Check if key already exists
if [ -f "$KEY_FILE" ]; then
    print_warning "SSH key already exists at $KEY_FILE"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Using existing key"
        SKIP_GENERATION=true
    fi
fi

# Generate new SSH key
if [ "$SKIP_GENERATION" != true ]; then
    print_info "Generating new SSH key..."
    ssh-keygen -t ed25519 -C "github-actions-deploy" -f "$KEY_FILE" -N ""
    print_success "SSH key generated"
fi

# Set proper permissions
chmod 600 "$KEY_FILE"
chmod 644 "${KEY_FILE}.pub"
print_success "Permissions set correctly"

# Add public key to authorized_keys
print_info "Adding public key to authorized_keys..."
cat "${KEY_FILE}.pub" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
print_success "Public key added to authorized_keys"

# Remove duplicates from authorized_keys
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
print_success "Removed duplicate entries from authorized_keys"

echo ""
echo "=========================================="
echo "✅ SSH Key Setup Complete!"
echo "=========================================="
echo ""

# Display VM information
print_info "VM Information for GitHub Secrets:"
echo ""
echo "1. VM_HOST:"
echo "   $(hostname -I | awk '{print $1}')"
echo ""
echo "2. VM_USER:"
echo "   $(whoami)"
echo ""
echo "3. VM_SSH_PORT:"
echo "   $(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22 (default)")"
echo ""
echo "4. VM_SSH_KEY (copy everything below):"
echo "   ----------------------------------------"
cat "$KEY_FILE"
echo "   ----------------------------------------"
echo ""

# Test SSH connection
print_info "Testing SSH connection..."
VM_IP=$(hostname -I | awk '{print $1}')
VM_USER=$(whoami)

if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "${VM_USER}@${VM_IP}" "echo 'SSH test successful'" 2>/dev/null; then
    print_success "SSH connection test passed"
else
    print_warning "SSH connection test failed (this might be normal if connecting to localhost)"
fi

echo ""
echo "=========================================="
echo "📋 Next Steps:"
echo "=========================================="
echo ""
echo "1. Copy the VM_SSH_KEY value above (including BEGIN and END lines)"
echo ""
echo "2. Go to your GitHub repository:"
echo "   Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "3. Add these secrets:"
echo "   - VM_HOST: $(hostname -I | awk '{print $1}')"
echo "   - VM_USER: $(whoami)"
echo "   - VM_SSH_KEY: [paste the private key from above]"
echo "   - VM_SSH_PORT: $(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")"
echo ""
echo "4. Also add Docker Hub secrets:"
echo "   - DOCKERHUB_USERNAME: [your Docker Hub username]"
echo "   - DOCKERHUB_TOKEN: [your Docker Hub access token]"
echo ""
echo "5. Test the setup by triggering a GitHub Actions workflow"
echo ""
echo "=========================================="
echo ""

# Save information to a file
INFO_FILE="$HOME/github_actions_setup_info.txt"
cat > "$INFO_FILE" <<EOF
GitHub Actions Setup Information
Generated: $(date)

VM_HOST: $(hostname -I | awk '{print $1}')
VM_USER: $(whoami)
VM_SSH_PORT: $(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")

VM_SSH_KEY location: $KEY_FILE

To view the private key again:
cat $KEY_FILE

To test SSH connection:
ssh -i $KEY_FILE $(whoami)@$(hostname -I | awk '{print $1}') "echo 'Test successful'"
EOF

print_success "Setup information saved to: $INFO_FILE"
echo ""
