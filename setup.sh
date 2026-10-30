#!/bin/bash

# =============================================================================
# Kiosk Media Sync & Display Setup
# -----------------------------------------------------------------------------
# This script installs necessary dependencies for kiosk setup, including Xorg,
# feh, rclone, and CEC utilities. It also logs the process for debugging and 
# auditing purposes.
#
# Usage:
# - Clone the repository to ~/kiosk-presenter as the kiosk user and run
#   ./setup.sh from there (not with sudo; it calls sudo itself where needed).
# - migrate.sh sources this file to reuse its install functions; the main
#   steps only run when the script is executed directly.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# Ensure the correct path for .bashrc
BASHRC_FILE="$HOME/.bashrc"

# Repository location. dotfiles/xinitrc expects it at ~/kiosk-presenter.
REPO_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
EXPECTED_REPO_DIR="$HOME/kiosk-presenter"

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

# Make sure the script runs as the kiosk user, so the dotfiles, crontab and
# rclone config end up in that user's home instead of root's
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Do not run this script with sudo. Run it as the kiosk user; it asks for sudo when needed."
        exit 1
    fi
}

# Make sure the repository is where dotfiles/xinitrc expects it
check_repo_location() {
    if [ "$REPO_DIR" != "$EXPECTED_REPO_DIR" ]; then
        echo "The repository must be at $EXPECTED_REPO_DIR (it is at $REPO_DIR)."
        echo "Clone it with: git clone https://github.com/MonkeyEnterprise/kiosk-presenter $EXPECTED_REPO_DIR"
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

# Link a dotfile from the repository into the home directory, so a git pull
# also updates it. An existing file that isn't this link is kept as <file>.bak.
link_dotfile() {
    local name="$1"
    local source_file="$REPO_DIR/dotfiles/$name"
    local dest_file="$HOME/.$name"

    if [ ! -f "$source_file" ]; then
        log "Source file $source_file does not exist."
        return 1
    fi

    if [ "$(readlink "$dest_file")" == "$source_file" ]; then
        log "$dest_file is already linked."
        return 0
    fi

    if [ -e "$dest_file" ] || [ -L "$dest_file" ]; then
        mv "$dest_file" "$dest_file.bak"
        log "Existing $dest_file moved to $dest_file.bak"
    fi

    ln -s "$source_file" "$dest_file"
    log "$dest_file now links to $source_file"
}

install_dotfiles() {
    link_dotfile xinitrc
    link_dotfile bash_profile
}

# =============================================================================
# Install crontab
# =============================================================================

# Install the display power schedule. Existing cec_client entries (also the
# old ones pointing to ~/core) are replaced, other cron jobs are kept.
install_crontab() {
    local cec="$REPO_DIR/bin/cec_client.sh"
    crontab -l 2>/dev/null | grep -v 'cec[-_]client\.sh' | {
        cat
        echo "0 6 * * 1-5 $cec \"on 0\""
        echo "0 9 * * 1-5 $cec \"standby 0\""
        echo "30 18 * * 3 $cec \"on 0\""
        echo "0 20 * * 3 $cec \"standby 0\""
        echo "0 9 * * 0 $cec \"on 0\""
        echo "30 13 * * 0 $cec \"standby 0\""
        echo "0 17 * * 0 $cec \"on 0\""
        echo "30 19 * * 0 $cec \"standby 0\""
    } | crontab -
    log "Cron jobs have been successfully installed!"
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

main() {
    check_not_root
    check_repo_location
    install_dependencies
    install_dotfiles
    install_crontab
    cloudflared_setup
    rclone_setup

    echo "Setup Complete!"
}

# Only run when executed directly, not when sourced by migrate.sh
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
