# kryofetch

A Windows system information fetch tool written in [Krypton](https://github.com/t3m3d/krypton) — a self-hosting language that compiles to C.

<img width="1215" height="463" alt="image" src="https://github.com/user-attachments/assets/9c7bbc03-bf5a-4b15-96cd-e4421c04ff1a" />

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

Requires [GCC for Windows](https://winlibs.com/) (MinGW). `kcc.exe` is bundled — no separate Krypton install needed.

```bat
kcc.exe run.k > out.c
gcc out.c -o kryofetch.exe -lm -w -lsetupapi -ladvapi32 -lpdh
```

Or just run `build.bat`.

## Requirements

- Windows 10 / 11
- GCC (MinGW / winlibs)

## Language

Written in [Krypton](https://github.com/KryptonBytes/krypton) — a self-hosting language that compiles to C via `kcc`. The bundled `kcc.exe` is all you need to recompile from source. Native Win32 helpers live in `kfetch_api.h` and are included inline at compile time.
