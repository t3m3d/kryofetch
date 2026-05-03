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

Two builds ship side by side:

- **`build.bat`** — default. Native PE/COFF via the Krypton compiler's
  Windows backend (`x64.k`). **No gcc required.** Produces `kryofetch.exe`
  alongside a freshly-copied `krypton_rt.dll`.
- **`build_gcc.bat`** — legacy fallback. Krypton → C → gcc.
  Requires [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) and links against
  `setupapi`, `advapi32`, `pdh`, `psapi`, and `m`.

Both expect the [Krypton repo](https://github.com/t3m3d/krypton) cloned
side-by-side as `..\krypton`. The native build pulls `kcc.exe`, the
optimizer host, the `x64` host, and `krypton_rt.dll` from that location
automatically.

## Requirements

- Windows 10 / 11
- The Krypton repo cloned to `..\krypton` (sibling directory)
- For `build_gcc.bat` only: TDM-GCC or another MinGW toolchain with `gcc` on PATH
