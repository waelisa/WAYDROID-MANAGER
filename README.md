# WayDroid Manager

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)

A powerful Bash script to easily manage your WayDroid installation. It automates installing Google Apps, MicroG, Magisk, ARM translation layers, Widevine, and various system tweaks by seamlessly integrating with the popular [waydroid_script](https://github.com/casualsnek/waydroid_script).

More info here too [WayDroid Manager](https://www.wael.name/waydroid-manager/)

This script provides both an interactive menu and a command-line interface, making WayDroid management simple for everyone.

## ✨ Features

*   **One-Command Setup:** Automatically clones and configures the required `waydroid_script`.
*   **Easy App Installation:** Install multiple components at once via an interactive menu or CLI.
*   **Full WayDroid Management:** Start, stop, restart, and check the status of the WayDroid container.
*   **Arch Linux Support:** Dedicated command to install WayDroid and its dependencies on Arch-based systems.
*   **Google Play Certification:** Quickly retrieve your Android ID for device registration.
*   **Colorful Interface:** Clear, color-coded output for easy navigation and status tracking.

## 📋 Prerequisites

*   A Linux distribution (Arch Linux, Ubuntu, Debian, Fedora, etc. are supported).
*   `git`, `python3`, `python3-pip`, and `lzip` installed (the script can install these for you).
*   Root/sudo access.

## 🚀 Quick Start (Using the Script)

You can run the script directly from the internet or download it first.

### Method 1: Direct Execution (One-liner)

This command downloads and runs the script immediately. Perfect for a quick start!

```bash
bash <(curl -s https://github.com/waelisa/WAYDROID-MANAGER/raw/refs/heads/main/waydroid-manager.sh)
```

### Method 2: Download and Run

1.  **Download the script:**
    ```bash
    wget https://github.com/waelisa/WAYDROID-MANAGER/raw/refs/heads/main/waydroid-manager.sh
    ```
    or
    ```bash
    curl -O https://github.com/waelisa/WAYDROID-MANAGER/raw/refs/heads/main/waydroid-manager.sh
    ```

2.  **Make it executable:**
    ```bash
    chmod +x waydroid-manager.sh
    ```

3.  **Run the script (as root):**
    ```bash
    sudo ./waydroid-manager.sh
    ```
    This will launch the interactive menu.

## 📖 Usage Guide

### Interactive Mode

Simply run `sudo ./waydroid-manager.sh` and follow the on-screen menu.

```
════════════════════════════════════════════
  WAYDROID MANAGER
════════════════════════════════════════════

System: arch | x86_64
Waydroid Script: Installed

1) Install WayDroid on Arch Linux
2) Install Apps (via waydroid_script)
3) Remove Apps (via waydroid_script)
4) Get Android ID (Play Store Certification)
5) Apply Hacks
6) Start WayDroid
7) Stop WayDroid
8) Restart WayDroid
9) Show Status
10) Update waydroid_script
11) Help
12) Exit

Select [1-12]:
```

### Command-Line Mode

For advanced users and scripting, you can use commands directly.

**First-time Setup:**
```bash
sudo ./waydroid-manager.sh install-deps
sudo ./waydroid-manager.sh setup
```

**Install WayDroid (Arch Linux):**
```bash
sudo ./waydroid-manager.sh install-arch
```

**Install Components:**
```bash
# Install Google Apps and Magisk
sudo ./waydroid-manager.sh install gapps magisk

# Install ARM translation for Intel CPUs
sudo ./waydroid-manager.sh install libhoudini

# Install a custom CA certificate for MITM
sudo ./waydroid-manager.sh install mitm --ca-cert /path/to/my.crt
```

**Get Certified:**
```bash
sudo ./waydroid-manager.sh certified
```

**Remove a Component:**
```bash
sudo ./waydroid-manager.sh remove nodataperm
```

**Check Service Status:**
```bash
sudo ./waydroid-manager.sh status
```

## 🧩 Available Apps & Hacks

| Command | Description |
| :--- | :--- |
| **gapps** | Google Apps (Open GApps for Android 11, MindTheGapps for Android 13) |
| **microg** | MicroG (open-source Google services framework) |
| **libndk** | ARM translation (recommended for AMD CPUs) |
| **libhoudini** | ARM translation (recommended for Intel CPUs) |
| **magisk** | Magisk Delta for root access |
| **widevine** | Widevine DRM L3 support |
| **smartdock** | Desktop mode launcher |
| **fdroidpriv** | FDroid Privileged Extension |
| **mitm** | Install a custom CA certificate (requires `--ca-cert`) |
| **nodataperm** | Hack: Remove data permissions (Android 11 only) |
| **hidestatusbar** | Hack: Hide the Android status bar (Android 11 only) |

## ⚙️ How It Works

This script is a friendly wrapper around the excellent [waydroid_script](https://github.com/casualsnek/waydroid_script) by [casualsnek](https://github.com/casualsnek). When you run it:

1.  It checks for root privileges.
2.  It ensures system dependencies (`lzip`, `git`, `python`) are installed.
3.  It clones the `waydroid_script` repository into a local `waydroid_script/` folder.
4.  It sets up a Python virtual environment and installs the required Python packages.
5.  All your `install`, `remove`, or `hack` commands are passed directly to the Python script, ensuring compatibility and leveraging its full power.

## 🛠️ Troubleshooting

*   **"waydroid_script not found"**: Run `sudo ./waydroid-manager.sh setup` first.
*   **Binder module errors**: Try running `sudo modprobe binder_linux` or check if you need to reboot after installing `binder_linux-dkms`.
*   **Installation fails**: Ensure you have a stable internet connection, as the script needs to download components. Check the output of the underlying Python script for specific errors.
*   **Google Play Certification**: After getting your ID with `certified`, register it [here](https://www.google.com/android/uncertified). It may take 10-20 minutes to activate.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/waelisa/WAYDROID-MANAGER/issues).

1.  Fork the project.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

*   [casualsnek](https://github.com/casualsnek) for the indispensable [waydroid_script](https://github.com/casualsnek/waydroid_script).
*   The [WayDroid](https://waydro.id/) project.
*   All contributors to the upstream projects like OpenGApps, MicroG, and Magisk.

[Donate link – PayPal](https://www.paypal.me/WaelIsa)


---

**Made with ❤️ for the WayDroid community**
