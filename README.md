
# **Program Overview and Setup Script Explanation**

## **Program Description**

This program is designed to create a minimal digital signage solution using a Raspberry Pi or Linux-based system. The setup focuses on displaying a fullscreen slideshow of images using `feh`, synchronized from a remote storage service through `rclone`. Additionally, the system utilizes HDMI-CEC commands via `cec-utils` to manage display power states automatically.

### **Core Features**

- **Fullscreen Slideshow**: Display images in fullscreen mode using `feh`, with automatic detection of new images.
- **Remote Media Sync**: Automatically synchronize images from remote storage services (Google Drive, Dropbox, etc.) using `rclone`.
- **HDMI-CEC Power Management**: Automatically power on and off the connected display at scheduled times using `cec-utils`.
- **Automatic Monitoring**: Continuously monitor the media folder for new files and update the slideshow in real time.
- **Power Management Scheduling**: Scheduled on/off times for the display using `cron` jobs.

---

## **Setup Script Explanation (`setup.sh`)**

The `setup.sh` script is responsible for automating the installation and configuration of all required components. It streamlines the setup process to minimize manual intervention.

### **Main Functions of the Script**

1. **Update and Install Required Packages**
   - Updates the system and installs essential tools: `xorg`, `x11-xserver-utils`, `feh`, `rclone`, `cec-utils`, and `inotify-tools`.

2. **Set Up Directory Structure**
   - Creates necessary directories:
     - `~/.config/openbox`: For Openbox configuration (if needed).
     - `~/media/feh`: Directory for storing synchronized images.

3. **Configure Auto-Start of X Session**
   - Modifies `~/.bash_profile` to automatically launch X without a cursor on terminal login.

4. **Configure Rclone**
   - Prompts the user to set up `rclone` manually using the `rclone config` command.

5. **Create and Configure `~/.xinitrc`**
   - Automates the creation of the X session startup file.
   - Disables screen blanking and power management.
   - Turns on the HDMI-connected display using CEC.
   - Synchronizes media using `rclone`.
   - Starts the FEH slideshow.
   - Periodically checks for new images from the server every 5 minutes.

6. **Configure Cron Jobs**
   - Adds scheduled tasks to automatically power the display on and off based on predefined times.

7. **Reboot the System**
   - Automatically reboots the system to apply all configurations.

---

### **How to Run the Setup Script**

1. Download and make the script executable:
   ```bash
   chmod +x setup.sh
   ```

2. Execute the script:
   ```bash
   ./setup.sh
   ```

3. Follow the prompts to configure `rclone`.

---

## **Expected Behavior After Installation**

- The system boots directly into a terminal session.
- X automatically starts in fullscreen mode without a cursor.
- Media files are synchronized from remote storage every 5 minutes.
- The display is automatically powered on or off according to the predefined schedule.
- A fullscreen slideshow runs continuously, updating automatically when new images are detected.

---

## **Troubleshooting Tips**

- **Verify Media Sync**:
  ```bash
  rclone ls remote:path
  ```
- **Manually Test HDMI-CEC Commands**:
  ```bash
  echo "standby 0" | cec-client -s -d 1  # Turn off display
  echo "on 0" | cec-client -s -d 1       # Turn on display
  ```
- **Check Cron Jobs**:
  ```bash
  crontab -l
  ```

---

## 📂 **Log Files**

- Media synchronization logs can be found at:
  ```bash
  ~/feh_sync.log
  ```

This guide ensures a fully automated and efficient setup for digital signage using `feh`, `rclone`, and `cec-utils`.

- Media synchronization logs can be found at:
  ```bash
  ~/feh_sync.log
  ```

This guide ensures a fully automated and efficient setup for digital signage using `feh`, `rclone`, and `cec-utils`.
