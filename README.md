<<<<<<< HEAD
# KryptonFetch

A Windows system information fetch tool written in [Krypton](https://github.com/KryptonBytes/krypton) — a self-hosting language that compiles to C.

<img width="968" height="387" alt="image" src="https://github.com/user-attachments/assets/3e9aab43-f3ad-4744-8c51-a019d65a4884" />
=======
# kryofetch
A terminal fetch program something like neofetch, fastfetch, but going to be a new one and is written in krypton-lang.
Lots of work still to be done.
<img width="1002" height="450" alt="image" src="https://github.com/user-attachments/assets/f34a439b-cdbb-420e-bc79-052dc3cd429d" />


>>>>>>> 42c7e572be07e273cc99c770f72786e109506bd4

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
gcc out.c -o kryofetch.exe -lm -w -lsetupapi -ladvapi32
```

Or just run `build.bat`.

## Requirements

- Windows 10 / 11
- GCC (MinGW / winlibs)

## Language

Written in [Krypton](https://github.com/KryptonBytes/krypton) — a self-hosting language that compiles to C via `kcc`. The bundled `kcc.exe` is all you need to recompile from source. Native Win32 helpers live in `kfetch_api.h` and are included inline at compile time.
