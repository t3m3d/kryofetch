# kryofetch

A Windows system information fetch tool written in [Krypton](https://github.com/t3m3d/krypton) — a self-hosting language that compiles to machine code.

**Krypton 2.0 only.** The 2.0 ABI break (per-allocation 16-byte GC headers + Win32 marshalling) is incompatible with 1.x runtimes. Krypton-side source uses the 2.0 calling convention: `bufNew(8)` + `bufGetQword` for OUT-pointer handles, no `handleInt()` wraps on already-itoa'd Win32 returns, `toHandle("0")` only for NULL pointer args of marshalled calls.

<img width="1207" height="426" alt="image" src="https://github.com/user-attachments/assets/673da10d-dc15-4ae5-857f-e4bca77eca2a" />

## Features

- **User** — username and hostname
- **OS** — Windows version, edition, build number, and architecture
- **CPU** — processor name with logical core count
- **RAM** — used / total with percentage and usage bar
- **Disk** — all drives with used / total and usage bars
- **GPU** — name + VRAM total (from `SYSTEM\CurrentControlSet\Control\Video` registry) and used VRAM bar (from `\GPU Adapter Memory(*)\Dedicated Usage` PDH counter, vendor-agnostic)
- **Shell** — detected shell (PowerShell, cmd, bash, zsh, nushell)
- **Term** — terminal emulator + console size when detectable
- **Resolution** — primary display resolution
- **Uptime** — days, hours, minutes
- **Packages** — installed counts (winget, scoop, choco)
- **Theme** — Windows light/dark mode and accent color
- **Battery** — charge percentage and AC status (laptops only, hidden on desktops)
- **Color palette** — 16-color ANSI block palette

## Build

Two builds ship side by side:

- **`build.bat`** — default. Native PE/COFF via the Krypton compiler's
  Windows backend (`x64.k`). **No gcc required.** Produces `kryofetch.exe`
  alongside a freshly-copied `krypton_rt.dll`. Companion DLLs
  (`ckrypton_gui.dll`, `ckrypton_proc.dll`, `ckrypton_fs.dll`) must
  also sit next to the .exe — copy them from `..\krypton\runtime\`
  if you don't already have them locally.
- **`build_gcc.bat`** — legacy fallback. Krypton → C → gcc.
  Requires [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) and links
  against `setupapi`, `advapi32`, `pdh`, `psapi`, `m`. Doesn't need
  the companion DLLs (everything statically linked into the .exe).

Both expect the [Krypton repo](https://github.com/t3m3d/krypton) cloned
side-by-side as `..\krypton`.

## Requirements

- Windows 10 / 11
- Krypton 2.0 repo cloned to `..\krypton` (sibling directory)
- For native build: `C:\krypton\bin\x64_host_new.exe` must be in lockstep
  with `..\krypton\compiler\windows_x86\x64_host.exe` — `kcc.exe -o` shells
  out to the installed copy. Stale installs cause "should-work" examples
  to AV.
- For `build_gcc.bat` only: TDM-GCC or another MinGW toolchain with `gcc` on PATH

## Notes

`kryofetch` is short-running (one shot, prints, exits) so it doesn't
need to call `gcCollect()` explicitly. The Krypton 2.0 mark-sweep GC
machinery is present but stays inert until program exit, when the OS
reclaims the slabs all at once.

The DXGI VRAM-budget path (1.x) is disabled under 2.0: `LoadLibraryA` +
`GetProcAddress` + COM vtable dispatch is fragile under the new Win32
marshalling table because `HMODULE` flows as raw `char*` through both
calls. Registry covers VRAM totals; PDH covers usage.
