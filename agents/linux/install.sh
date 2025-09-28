#!/bin/bash
#
# Ansible Agent Linux Installation Script
#

set -euo pipefail

# Configuration
AGENT_USER="ansible-agent"
AGENT_GROUP="ansible-agent"
INSTALL_DIR="/opt/ansible-agent"
CONFIG_DIR="/etc/ansible-agent"
LOG_DIR="/var/log"
SYSTEMD_DIR="/etc/systemd/system"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    print_status "Detected OS: $OS_ID $OS_VERSION"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl sha256sum coreutils
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y curl coreutils
            ;;
        fedora)
            dnf install -y curl coreutils
            ;;
        *)
            print_warning "Unknown OS, dependencies may need to be installed manually"
            ;;
    esac
}

# Function to create user and directories
create_user_and_dirs() {
    print_status "Creating user and directories..."
    
    # Create system user
    if ! getent passwd "$AGENT_USER" > /dev/null 2>&1; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$AGENT_USER"
        print_status "Created user: $AGENT_USER"
    else
        print_status "User $AGENT_USER already exists"
    fi
    
    # Create directories
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
    
    # Set ownership
    chown root:root "$INSTALL_DIR" "$CONFIG_DIR"
    chmod 755 "$INSTALL_DIR" "$CONFIG_DIR"
}

# Function to install agent script
install_agent() {
    print_status "Installing agent script..."
    
    # Copy agent script
    cp "ansible-agent" "$INSTALL_DIR/"
    chmod 755 "$INSTALL_DIR/ansible-agent"
    chown root:root "$INSTALL_DIR/ansible-agent"
    
    # Copy configuration template if it doesn't exist
    if [[ ! -f "$CONFIG_DIR/config.conf" ]]; then
        cp "config.conf" "$CONFIG_DIR/"
        chmod 640 "$CONFIG_DIR/config.conf"
        chown root:$AGENT_GROUP "$CONFIG_DIR/config.conf"
        print_status "Installed configuration template"
        print_warning "Please edit $CONFIG_DIR/config.conf to configure the agent"
    else
        print_status "Configuration file already exists, not overwriting"
    fi
}

# Function to create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    cat > "$SYSTEMD_DIR/ansible-agent.service" << EOF
[Unit]
Description=Ansible Agent
Documentation=https://github.com/charlespick/ansible-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$AGENT_USER
Group=$AGENT_GROUP
ExecStart=$INSTALL_DIR/ansible-agent daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictAddressFamilies=AF_INET AF_INET6
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    print_status "Created systemd service: ansible-agent.service"
}

# Function to setup log rotation
setup_logrotate() {
    print_status "Setting up log rotation..."
    
    cat > /etc/logrotate.d/ansible-agent << EOF
$LOG_DIR/ansible-agent.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $AGENT_USER $AGENT_GROUP
    postrotate
        systemctl reload ansible-agent >/dev/null 2>&1 || true
    endscript
}
EOF
}

# Function to display post-installation instructions
show_instructions() {
    print_status "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Edit the configuration file: $CONFIG_DIR/config.conf"
    echo "2. Set your relay service URL and other settings"
    echo "3. Enable and start the service:"
    echo "   systemctl enable ansible-agent"
    echo "   systemctl start ansible-agent"
    echo
    echo "Useful commands:"
    echo "  systemctl status ansible-agent  - Check service status"
    echo "  journalctl -u ansible-agent    - View service logs"
    echo "  $INSTALL_DIR/ansible-agent test - Test configuration"
    echo "  $INSTALL_DIR/ansible-agent once - Run once manually"
    echo
}

# Function to uninstall
uninstall() {
    print_status "Uninstalling Ansible Agent..."
    
    # Stop and disable service
    systemctl stop ansible-agent || true
    systemctl disable ansible-agent || true
    
    # Remove files
    rm -f "$SYSTEMD_DIR/ansible-agent.service"
    rm -rf "$INSTALL_DIR"
    rm -f /etc/logrotate.d/ansible-agent
    
    # Remove user
    userdel "$AGENT_USER" || true
    
    # Reload systemd
    systemctl daemon-reload
    
    print_status "Uninstallation completed"
    print_warning "Configuration files in $CONFIG_DIR were not removed"
}

# Main function
main() {
    case "${1:-install}" in
        install)
            check_root
            detect_os
            install_dependencies
            create_user_and_dirs
            install_agent
            create_systemd_service
            setup_logrotate
            show_instructions
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        *)
            echo "Usage: $0 [install|uninstall]"
            echo "  install   - Install the Ansible Agent (default)"
            echo "  uninstall - Remove the Ansible Agent"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi