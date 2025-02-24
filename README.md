## Installation

### 1 - System update
Please update the linux kernel to the latest version using the following commands:
``` sh
sudo apt-get update
sudo apt-get full-upgrade -y
```

### 2. Install packages
``` sh
sudo apt-get install rclone
sudo apt-get install x11-xserver-utils
sudo apt-get install feh
sudo apt-install cec-utils
```

### 3. Setup z11 server utils
Create a directory for the feh media.
``` sh
mkdir ~/media/feh
```
Add the following rule to the crontave
``` crontab
@reboot feh -recursive -Y -x -q -D 30 -B black -F -Z ~/media/feh
```

### 3. Setup feh
Create a directory for the feh media.
``` sh
mkdir ~/media/feh
```
Add the following rule to the crontave
``` crontab
@reboot feh -recursive -Y -x -q -D 30 -B black -F -Z ~/media/feh
```
