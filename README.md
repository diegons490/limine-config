<div align="center">

# limine-config

**An interactive Bash tool to configure the [Limine](https://github.com/limine-bootloader/limine) bootloader.**

Edit common boot settings, add multiboot entries, safely manage entries created by the script, and restore the original configuration when needed.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-FCC624.svg?logo=linux&logoColor=black)](https://www.kernel.org/)

![limine-config demo](docs/demo.gif)

</div>

---

## ✨ Features

| | Feature | Description |
|:-:|---------|-------------|
| ⏱️ | **Boot timeout** | Set how many seconds Limine waits before automatically booting the selected entry. |
| 🎯 | **Default entry** | Choose which boot entry Limine should select by default. |
| 🔁 | **Remember last entry** | Make Limine reopen the last entry you booted instead of always using the default entry. |
| 🧭 | **Add multiboot entries** | Runs `limine-scan` and detects entries newly added to `limine.conf`. |
| 🏷️ | **Managed entries** | Newly detected entries are marked so this script can identify them later. |
| 🧹 | **Remove managed entries** | Remove one, several, or all entries created through the script without touching entries that are not managed by it. |
| 📝 | **Manual edit** | Open `limine.conf` with a terminal editor of your choice. |
| 💾 | **Automatic backup** | Creates `limine.conf.bak-limine-config` before making changes. |
| ↩️ | **Restore backup** | Restore `limine.conf` from the backup created by the script. |
| 🔄 | **Reboot prompt** | After a configuration change, the script offers to reboot immediately or continue without rebooting. |

---

## 🖥️ Interactive Menu

When started, `limine-config` presents the following menu:

```text
Limine Configurator
Choose an option:
1) Set boot timeout
2) Set default entry
3) Remember last booted entry
4) Add multiboot entries (limine-scan)
5) Remove entries added by this script
6) Edit limine.conf manually
7) Restore limine.conf from backup
8) Exit
Option:
