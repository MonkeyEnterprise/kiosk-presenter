# Test image for test/run.sh: Debian 12 (base of Raspberry Pi OS Bookworm)
# with a virtual X server, feh, rclone and crontab.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb x11-xserver-utils feh rclone procps cron ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -d /home/kiosk -s /bin/bash kiosk
USER kiosk
WORKDIR /home/kiosk
