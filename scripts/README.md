# Scripts Directory

This directory contains scripts for VM setup and deployment.

## 📁 Scripts Overview

### 🙋 Manual Scripts (You Run These)

#### 1. `vm-setup.sh`
**Purpose:** One-time VM setup - installs Docker, Python, configures firewall

**When to run:** Once, during initial VM setup

**How to run:**
```bash
# Copy to VM
scp scripts/vm-setup.sh user@vm-ip:~/

# SSH into VM and run
ssh user@vm-ip
chmod +x vm-setup.sh
./vm-setup.sh
```

**What it does:**
- ✅ Installs Docker and Docker Compose
- ✅ Installs Python 3.11 and pip
- ✅ Configures firewall (ports 22, 8000, 8001)
- ✅ Creates deployment directories
- ✅ Sets up Docker daemon

---

#### 2. `setup-github-ssh.sh`
**Purpose:** Generate SSH keys for GitHub Actions

**When to run:** Once, after running `vm-setup.sh`

**How to run:**
```bash
# On your VM
bash ~/deployments/scripts/setup-github-ssh.sh
```

**What it does:**
- ✅ Generates SSH key pair
- ✅ Adds public key to authorized_keys
- ✅ Displays all values needed for GitHub Secrets
- ✅ Saves info to a file for reference

**Output:** Copy the displayed values and add them to GitHub Secrets

---

#### 3. `deploy.sh` (Optional)
**Purpose:** Manual deployment script

**When to run:** Only if you want to deploy manually (not recommended, use GitHub Actions instead)

**How to run:**
```bash
# On your VM
./deploy.sh staging latest
./deploy.sh production latest
```

---

#### 4. `health-check.sh` (Optional)
**Purpose:** Test if application is responding

**When to run:** For manual testing/debugging

**How to run:**
```bash
# On your VM
./health-check.sh 8000  # Check production
./health-check.sh 8001  # Check staging
```

---

### 🤖 Automated Scripts (GitHub Actions Runs These)

#### 5. `vm-deploy.sh`
**Purpose:** Main deployment script executed by GitHub Actions

**When it runs:** Automatically on every deployment (triggered by GitHub Actions)

**How it runs:** GitHub Actions copies this to your VM and executes via SSH

**What it does:**
- ✅ Pulls Docker image from Docker Hub
- ✅ Creates backup of current container
- ✅ Stops old container
- ✅ Starts new container
- ✅ Runs health checks
- ✅ Runs smoke tests
- ✅ Auto-rollback on failure
- ✅ Logs everything

**You DON'T run this manually** - GitHub Actions handles it!

---

## 🚀 Quick Start Guide

### First Time Setup (Do Once):

```bash
# Step 1: Copy vm-setup.sh to your VM
scp scripts/vm-setup.sh user@vm-ip:~/

# Step 2: SSH into VM
ssh user@vm-ip

# Step 3: Run setup
chmod +x vm-setup.sh
./vm-setup.sh

# Step 4: Generate SSH keys
bash ~/deployments/scripts/setup-github-ssh.sh

# Step 5: Copy the output and add to GitHub Secrets
# Go to: GitHub repo → Settings → Secrets and variables → Actions
# Add: VM_HOST, VM_USER, VM_SSH_KEY, VM_SSH_PORT, DOCKERHUB_USERNAME, DOCKERHUB_TOKEN
```

### After Setup (Automatic):

```bash
# Just push your code
git add .
git commit -m "your changes"
git push origin main

# GitHub Actions will automatically:
# 1. Run CI pipeline
# 2. Copy vm-deploy.sh to VM
# 3. Deploy to staging
# 4. Deploy to production
```

---

## 📊 Script Usage Matrix

| Script | Run By | Frequency | Required |
|--------|--------|-----------|----------|
| `vm-setup.sh` | You (manual) | Once | ✅ Yes |
| `setup-github-ssh.sh` | You (manual) | Once | ✅ Yes |
| `vm-deploy.sh` | GitHub Actions (auto) | Every deployment | ✅ Yes |
| `deploy.sh` | You (manual) | As needed | ❌ Optional |
| `health-check.sh` | You (manual) | As needed | ❌ Optional |

---

## 🔍 Troubleshooting

### Check if setup was successful:
```bash
# On your VM
docker --version          # Should show Docker version
python3 --version         # Should show Python 3.11+
ls -la ~/deployments/     # Should show deployment directories
```

### Check if SSH keys are set up:
```bash
# On your VM
ls -la ~/.ssh/github_actions_deploy*  # Should show key files
cat ~/github_actions_setup_info.txt   # Shows all setup info
```

### Test deployment manually:
```bash
# On your VM
bash ~/deployments/scripts/vm-deploy.sh staging yourusername/devops-fastapi latest 8001
```

---

## 📝 Notes

- **vm-setup.sh** and **setup-github-ssh.sh** are run ONCE during setup
- **vm-deploy.sh** is run AUTOMATICALLY by GitHub Actions on every deployment
- **deploy.sh** and **health-check.sh** are optional utilities for manual testing
- All scripts are executable (`chmod +x` is applied automatically)
- Logs are stored in `~/deployments/logs/` on your VM

---

## 🆘 Need Help?

- See [SIMPLE_SETUP.md](../SIMPLE_SETUP.md) for step-by-step guide
- See [docs/VM_SETUP.md](../docs/VM_SETUP.md) for detailed documentation
- See [docs/GITHUB_SECRETS_SETUP.md](../docs/GITHUB_SECRETS_SETUP.md) for secrets configuration
