# Kiosk Presenter for Raspberry Pi 5

<p align="center"> <img src="https://upload.wikimedia.org/wikipedia/en/thumb/c/cb/Raspberry_Pi_Logo.svg/200px-Raspberry_Pi_Logo.svg.png" width="15%"> </p>

This repository provides a script to set up a minimal digital signage system on Raspberry Pi 5, combined with optional Cloudflared tunneling for secure remote access. The system supports fullscreen image slideshows using `feh`, cloud media synchronization via `rclone`, and HDMI-CEC display control with `cec-utils`.

---

## Features

* **Fullscreen Slideshow**: Automatically displays images in fullscreen using `feh`, with real-time updates.
* **Remote Media Synchronization**: Fetches images from cloud storage providers like Google Drive or Dropbox using `rclone`.
* **HDMI-CEC Display Control**: Automatically turns the display on or off using `cec-utils`.
* **Cloudflared Tunnel Integration**: Optional secure tunnel setup for remote access using Cloudflare Tunnel.
* **Scheduled Power Management**: Display power is managed using cron jobs.
