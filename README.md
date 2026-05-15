# kryofetch

A cross-platform system information fetch tool written in [Krypton](https://github.com/t3m3d/krypton) — a self-hosting language that compiles to machine code.

**Krypton 2.0 only.**

<img width="1207" height="426" alt="image" src="https://github.com/user-attachments/assets/673da10d-dc15-4ae5-857f-e4bca77eca2a" />

## Features

- **User** — username and hostname
- **OS** — version, edition/build (Windows) or product version (macOS) and architecture
- **CPU** — processor name with physical and logical core count
- **RAM** — used / total with percentage and usage bar
- **Disk** — drives/volumes with used / total and usage bars
- **GPU** — name and VRAM (discrete) or chip name (Apple Silicon)
- **Shell** — detected shell (zsh, bash, PowerShell, cmd, fish, nushell)
- **Term** — terminal emulator and console size
- **Resolution** — primary display resolution
- **Uptime** — days, hours, minutes
- **Packages** — installed package counts
- **Theme** — light/dark mode
- **Battery** — charge percentage and AC status (laptops only)
- **Color palette** — 16-color ANSI block palette

---

## macOS

### Install with Homebrew (recommended)

```bash
brew tap t3m3d/kryofetch
brew install kryofetch
```

Then just run:

```bash
kryofetch
```

### Build from source

Requires the [Krypton compiler](https://github.com/t3m3d/krypton) installed. Download the latest `krypton-2.0-macos-arm64.pkg` from the [Krypton releases page](https://github.com/t3m3d/krypton/releases) and install it, then:

```bash
git clone https://github.com/t3m3d/kryofetch
cd kryofetch
/usr/local/krypton/kcc.sh --gcc run_macos.k -o kryofetch
./kryofetch
```

### macOS requirements

- macOS Sequoia or Tahoe, Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`) — needed once to build the Krypton C bridge

### macOS source files

The macOS implementation lives in the `*_macos.k` files alongside the Windows sources. The Windows build is unaffected.

| File | Purpose |
|------|---------|
| `run_macos.k` | Entry point — imports all macOS modules |
| `os_macos.k` | OS version, uptime, shell, terminal, theme, battery, resolution |
| `cpu_macos.k` | CPU brand and core counts via `sysctl` |
| `mem_macos.k` | RAM total and free via `hw.memsize` + `vm_stat` |
| `disk_macos.k` | Disk usage via `df` (Data volume + external drives) |
| `gpu_macos.k` | GPU name and VRAM via `system_profiler` |
| `utils_macos.k` | Shared string helpers, bar renderer, package count |

---

## Windows

### Run

```
kryofetch.exe              # one-shot render
kryofetch.exe --watch      # live re-render every 1000 ms
kryofetch.exe --watch 500  # custom interval (ms)
```

In `--watch` mode kryofetch calls `gcCollect()` (2.0 mark+sweep) after each render so unreachable allocations are reclaimed and the working set stays bounded.

### Build

```
build.bat
```

Native PE/COFF via the Krypton compiler's Windows backend (`x64.k`). **No gcc, no MinGW, no MSVC.** Produces `kryofetch.exe` alongside a freshly-copied `krypton_rt.dll`.

Expects the [Krypton repo](https://github.com/t3m3d/krypton) cloned side-by-side as `..\krypton`.

### Windows requirements

- Windows 10 / 11
- Krypton 2.0 repo cloned to `..\krypton` (sibling directory)
- `C:\krypton\bin\x64_host_new.exe` in lockstep with `..\krypton\compiler\windows_x86\x64_host.exe`

---

## Notes

The 2.0 ABI break (per-allocation 16-byte GC headers + Win32 marshalling) is incompatible with 1.x runtimes.

`kryofetch` is short-running (one shot, prints, exits) so it doesn't need to call `gcCollect()` explicitly on Windows. The Krypton 2.0 mark-sweep GC machinery is present but stays inert until program exit, when the OS reclaims the slabs all at once.
