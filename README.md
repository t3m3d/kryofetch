# kryofetch

A Windows system information fetch tool written in [Krypton](https://github.com/t3m3d/krypton) — a self-hosting language that compiles to machine code.

<img width="1207" height="426" alt="image" src="https://github.com/user-attachments/assets/673da10d-dc15-4ae5-857f-e4bca77eca2a" />

## Features

- **User** — username and hostname
- **OS** — Windows version, edition, build number, and architecture
- **CPU** — processor name with core and thread count
- **RAM** — used / total with percentage and usage bar
- **Disk** — all drives with used / total and usage bars
- **GPU** — name and VRAM size (NVIDIA via NVAPI, AMD/Intel via registry)
- **Shell** — detected shell (PowerShell, cmd, bash, nushell, etc.)
- **Term** — terminal emulator and console size
- **Resolution** — primary display resolution
- **Uptime** — days, hours, and minutes
- **Packages** — installed package count (winget, scoop, choco)
- **Theme** — Windows light/dark mode and accent color
- **Battery** — charge percentage and status (laptops only, hidden on desktops)
- **Color palette** — 16-color ANSI block palette

## Build

Requires [KCC for Windows](https://github.com/t3m3d/krypton).

Or just run `build.bat`.

## Requirements

- Windows 10 / 11
- KCC - Krypton-Lang compiler.
