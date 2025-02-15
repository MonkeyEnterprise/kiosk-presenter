#!/bin/bash

# Functie om Rclone, X11 en Feh te installeren
install_software() {
    echo "Installing Rclone, X11, and Feh..."
    sudo apt update
    sudo apt install -y rclone x11-xserver-utils feh
    echo "Installation complete."
}

# Functie om Feh in te stellen voor diavoorstelling
setup_feh() {
    read -p "Enter the directory for the slideshow: " slideshow_dir
    read -p "Enter the slideshow interval in seconds: " interval
    
    echo "Setting up Feh..."
    echo "feh --fullscreen --slideshow-delay $interval --reload 60 $slideshow_dir" > ~/start_feh.sh
    chmod +x ~/start_feh.sh
    
    # Autostart Feh bij X11 startup
    echo "@~/start_feh.sh" > ~/.xinitrc
    
    echo "Feh setup complete. Start with 'startx'."
}

# Menu weergeven
echo "Select an option:"
echo "1) Install Rclone, X11, and Feh"
echo "2) Setup Feh slideshow"
echo "3) Exit"
read -p "Enter your choice: " choice

case $choice in
    1) install_software ;;
    2) setup_feh ;;
    3) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid option, exiting..."; exit 1 ;;
esac
