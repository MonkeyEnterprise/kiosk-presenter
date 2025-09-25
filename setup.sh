#!/bin/bash

# =============================================================================
# Kiosk Media Sync & Display Setup
# -----------------------------------------------------------------------------
# This script installs necessary dependencies for kiosk setup, including Xorg,
# feh, rclone, and CEC utilities. It also logs the process for debugging and 
# auditing purposes.
#
# Usage:
# - Run this script to set up the kiosk environment with required dependencies.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# Ensure the correct path for .bashrc
BASHRC_FILE="$HOME/.bashrc"

# =============================================================================
# Helper Functions
# =============================================================================

# Logging function to timestamp messages
log() {
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$timestamp - $msg"
}

# Check and install a package if it's not installed
install_package_if_missing() {
    local package_name="$1"
    if ! dpkg -l | grep -q "$package_name"; then
        log "Installing $package_name..."
        sudo apt install -y "$package_name"
    else
        log "$package_name is already installed."
    fi
}

# Simple spinner function for long-running tasks
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'
    local i=0
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        i=$(( (i+1) %4 ))
        printf "\r${spinstr:$i:1}"
        sleep $delay
    done
    echo ""
}

# Check if the script is run with sudo privileges
check_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script requires sudo privileges. Please run with sudo."
        exit 1
    fi
}

# =============================================================================
# Install Dependencies
# =============================================================================

install_dependencies() {
    log "Starting installation of dependencies..."

    # Optionally update the system
    log "Updating system..."
    sudo apt update && sudo apt -y full-upgrade

    # List of packages to install
    local packages=("xorg" "x11-xserver-utils" "feh" "rclone" "cec-utils" "jq")

    for package in "${packages[@]}"; do
        install_package_if_missing "$package"
    done

    log "All required dependencies are installed."
}

install_xinitrc() {
    # Get the current directory of the setup.sh script
    local script_dir=$(dirname "$(realpath "$0")")
    
    # Define the source and destination file paths
    local source_file="$script_dir/rpi/.xinitrc"
    local dest_file="$HOME/.xinitrc"

    # Check if the source file exists
    if [ -f "$source_file" ]; then
        # Check if the destination file exists
        if [ -f "$dest_file" ]; then
            read -p "$dest_file already exists. Do you want to overwrite it? (y/n): " choice
            if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
                echo "Skipping .xinitrc installation."
                return 0
            fi
        fi

        # Move the source file to the home directory
        mv "$source_file" "$dest_file"
        echo ".xinitrc has been installed."
    else
        echo "Source file $source_file does not exist."
        return 1
    fi
}

install_bash_profile() {
    # Get the current directory of the setup.sh script
    local script_dir=$(dirname "$(realpath "$0")")
    
    # Define the source and destination file paths
    local source_file="$script_dir/rpi/.bash_profile"
    local dest_file="$HOME/.bash_profile"

    # Check if the source file exists
    if [ -f "$source_file" ]; then
        # Check if the destination file exists
        if [ -f "$dest_file" ]; then
            read -p "$dest_file already exists. Do you want to overwrite it? (y/n): " choice
            if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
                echo "Skipping .bash_profile installation."
                return 0
            fi
        fi

        # Move the source file to the home directory
        mv "$source_file" "$dest_file"
        echo ".bash_profile has been installed."
    else
        echo "Source file $source_file does not exist."
        return 1
    fi
}

# =============================================================================
# Install crontab
# =============================================================================

install_crontab() {
    crontab -l 2>/dev/null | { 
        echo "0 6 * * 1-5 $HOME/core/cec-client.sh \"on 0\""
        echo "0 9 * * 1-5 $HOME/core/cec-client.sh \"standby 0\""
        echo "30 18 * * 3 $HOME/core/cec-client.sh \"on 0\""
        echo "0 20 * * 3 $HOME/core/cec-client.sh \"standby 0\""
        echo "0 9 * * 0 $HOME/core/cec-client.sh \"on 0\""
        echo "30 13 * * 0 $HOME/core/cec-client.sh \"standby 0\""
        echo "0 17 * * 0 $HOME/core/cec-client.sh \"on 0\""
        echo "30 19 * * 0 $HOME/core/cec-client.sh \"standby 0\""
    } | crontab -
    echo "Cron jobs have been successfully installed!"
}

# =============================================================================
# Cloudflared Setup
# =============================================================================

cloudflared_setup() {
    # Detect system architecture
    local arch=$(uname -m)
    case "$arch" in
        aarch64|arm64) asset="cloudflared-linux-arm64" ;;
        x86_64) asset="cloudflared-linux-amd64" ;;
        *) echo "Unsupported architecture: $arch. Only ARM64 and AMD64 architectures are supported."; return 1 ;;
    esac

    # Fetch the latest release URL from GitHub
    local url=$(wget -qO- https://api.github.com/repos/cloudflare/cloudflared/releases/latest | \
                grep browser_download_url | grep "$asset\"" | cut -d '"' -f 4)
    if [ -z "$url" ]; then
        echo "Could not find the download link for cloudflared ($asset)."
        return 1
    fi

    # Download and install cloudflared
    echo "Downloading cloudflared..."
    wget -O cloudflared "$url" &
    spinner $!
    
    sudo mv cloudflared /usr/local/bin/
    sudo chmod +x /usr/local/bin/cloudflared

    # Verify cloudflared installation
    if ! cloudflared --version > /dev/null 2>&1; then
        echo "cloudflared installation failed."
        return 1
    fi
    echo "cloudflared installed successfully."

    # Login to cloudflared
    if ! cloudflared tunnel login; then
        echo "cloudflared login failed."
        return 1
    fi
    echo "cloudflared login successful."

    # Create and configure tunnel
    create_and_configure_tunnel
}

create_and_configure_tunnel() {
    read -p "Enter a name for your tunnel: " tunnel_name
    cloudflared tunnel create "$tunnel_name"

    local tunnel_id=$(cloudflared tunnel list --output json | jq -r ".[] | select(.name==\"$tunnel_name\") | .id")
    if [ -z "$tunnel_id" ] || [ "$tunnel_id" == "null" ]; then
        echo "Failed to retrieve tunnel ID for $tunnel_name"
        return 1
    fi
    echo "cloudflared tunnel '$tunnel_name' created successfully with ID: $tunnel_id."

    read -p "Enter the domain name you want to use for the tunnel (e.g., example.com): " domain_name
    if ! cloudflared tunnel route dns "$tunnel_id" "$tunnel_name.$domain_name"; then
        echo "cloudflared tunnel routing failed."
        return 1
    fi
    echo "cloudflared tunnel '$tunnel_name' routed successfully to '$tunnel_name.$domain_name'."

    configure_cloudflared "$tunnel_id" "$tunnel_name" "$domain_name"
}

configure_cloudflared() {
    local tunnel_id="$1"
    local tunnel_name="$2"
    local domain_name="$3"

    local config_dir="/etc/cloudflared"
    sudo mkdir -p "$config_dir"
    local config_file="$config_dir/config.yml"
    local credentials_file="$config_dir/${tunnel_id}.json"

    if [ -f "$HOME/.cloudflared/${tunnel_id}.json" ]; then
        sudo cp "$HOME/.cloudflared/${tunnel_id}.json" "$credentials_file"
    else
        echo "Credentials file not found in $HOME/.cloudflared/"
        return 1
    fi

    if [ -f /etc/cloudflared/config.yml ]; then
        echo "Removing old /etc/cloudflared/config.yml..."
        sudo rm /etc/cloudflared/config.yml
    fi

    cat <<EOF | sudo tee "$config_file" > /dev/null
tunnel: $tunnel_id
credentials-file: $credentials_file
ingress:
  - hostname: $tunnel_name.$domain_name
    service: http://localhost:8080
  - service: http_status:404
EOF

    sudo cloudflared tunnel run "$tunnel_name"
}

# =============================================================================
# Rclone Setup
# =============================================================================

rclone_setup() {
    echo "Select the cloud storage service you want to set up:"
    echo "1. Dropbox"
    echo "2. Google Drive"
    echo "3. OneDrive"
    echo "4. Skip rclone setup"
    
    read -p "Enter your choice (1/2/3/4): " choice
    
    case "$choice" in
        1)
            rclone_setup_dropbox
            ;;
        2)
            rclone_setup_google_drive
            ;;
        3)
            rclone_setup_onedrive
            ;;
        4)
            echo "Skipping rclone setup."
            ;;
        *)
            echo "Invalid choice. Please try again."
            rclone_setup  # Recursively call the function for a valid choice
            ;;
    esac
}

# Setup for Dropbox
rclone_setup_dropbox() {
    echo "Setting up rclone for Dropbox..."
    rclone config create kiosk-dropbox dropbox \
        client_id "" \
        client_secret "" \
        advanced_config "false" \
        auto_config "false" \
        config_is_local "true"

    echo "Dropbox 'kiosk-dropbox' has been set up."

    # List directories
    echo "Listing available directories in Dropbox:"
    rclone lsd kiosk-dropbox:

    # Get directory from user
    echo "Please select a directory from the list above."
    read -p "Enter the directory path: " selected_path
    
    if [ -z "$selected_path" ]; then
        echo "No path selected. Exiting setup."
        return 1
    fi

    # Update ~/.bashrc with the selected path
    echo "export RCLONE_REMOTE_PATH='kiosk-dropbox:$selected_path'" >> "$BASHRC_FILE"
    source "$BASHRC_FILE"
    export RCLONE_REMOTE_PATH="kiosk-dropbox:$selected_path"

    echo "RCLONE_REMOTE_PATH is now set to: kiosk-dropbox:$selected_path"
}

# Setup for Google Drive
rclone_setup_google_drive() {
    echo "Setting up rclone for Google Drive..."
    rclone config create kiosk-gdrive drive \
        client_id "" \
        client_secret "" \
        scope "drive" \
        advanced_config "false" \
        auto_config "false" \
        config_is_local "true"

    echo "Google Drive 'kiosk-gdrive' has been set up."

    # List directories
    echo "Listing available directories in Google Drive:"
    rclone lsd kiosk-gdrive:

    # Get directory from user
    echo "Please select a directory from the list above."
    read -p "Enter the directory path: " selected_path
    
    if [ -z "$selected_path" ]; then
        echo "No path selected. Exiting setup."
        return 1
    fi

    # Update ~/.bashrc with the selected path
    echo "export RCLONE_REMOTE_PATH='kiosk-gdrive:$selected_path'" >> "$BASHRC_FILE"
    source "$BASHRC_FILE"
    export RCLONE_REMOTE_PATH="kiosk-gdrive:$selected_path"

    echo "RCLONE_REMOTE_PATH is now set to: kiosk-gdrive:$selected_path"
}

# Setup for OneDrive
rclone_setup_onedrive() {
    echo "Setting up rclone for OneDrive..."
    rclone config create kiosk-onedrive onedrive \
        client_id "" \
        client_secret "" \
        advanced_config "false" \
        auto_config "false" \
        config_is_local "true"

    echo "OneDrive 'kiosk-onedrive' has been set up."

    # List directories
    echo "Listing available directories in OneDrive:"
    rclone lsd kiosk-onedrive:

    # Get directory from user
    echo "Please select a directory from the list above."
    read -p "Enter the directory path: " selected_path
    
    if [ -z "$selected_path" ]; then
        echo "No path selected. Exiting setup."
        return 1
    fi

    # Update ~/.bashrc with the selected path
    echo "export RCLONE_REMOTE_PATH='kiosk-onedrive:$selected_path'" >> "$BASHRC_FILE"
    source "$BASHRC_FILE"
    export RCLONE_REMOTE_PATH="kiosk-onedrive:$selected_path"

    echo "RCLONE_REMOTE_PATH is now set to: kiosk-onedrive:$selected_path"
}

# =============================================================================
# Main Script Execution
# =============================================================================

check_sudo
install_dependencies
install_xinitrc
install_bash_profile
install_crontab
cloudflared_setup
rclone_setup

echo "Setup Complete!"
