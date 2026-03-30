#pragma once
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <pdh.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

static char _kf_exec_buf[8192];
char* exec(char* cmd) {
    _kf_exec_buf[0] = 0;
    FILE* p = _popen(cmd, "r");
    if (!p) return _kf_exec_buf;
    int pos = 0, c;
    while (pos < (int)sizeof(_kf_exec_buf) - 1 && (c = fgetc(p)) != EOF)
        _kf_exec_buf[pos++] = (char)c;
    _kf_exec_buf[pos] = 0;
    _pclose(p);
    while (pos > 0 && (_kf_exec_buf[pos-1]=='\r'||_kf_exec_buf[pos-1]=='\n'||_kf_exec_buf[pos-1]==' '))
        _kf_exec_buf[--pos] = 0;
    return _kf_exec_buf;
}

char* kfinit() {
    SetConsoleOutputCP(65001);
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode = 0;
    GetConsoleMode(h, &mode);
    SetConsoleMode(h, mode | 0x0004);
    return "";
}

char* kfcls() {
    system("cls");
    return "";
}

static char _kf_mem_buf[64];
char* kfmem() {
    MEMORYSTATUSEX ms;
    ZeroMemory(&ms, sizeof(ms));
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        unsigned long long total = ms.ullTotalPhys / (1024ULL * 1024ULL);
        unsigned long long free_ = ms.ullAvailPhys / (1024ULL * 1024ULL);
        snprintf(_kf_mem_buf, sizeof(_kf_mem_buf), "%llu,%llu", total, free_);
    } else {
        strcpy(_kf_mem_buf, "0,0");
    }
    return _kf_mem_buf;
}

static char _kf_disk_buf[4096];
char* kfdisk() {
    _kf_disk_buf[0] = 0;
    DWORD drives = GetLogicalDrives();
    for (char letter = 'A'; letter <= 'Z'; letter++) {
        if (!(drives & (1 << (letter - 'A')))) continue;
        char root[4];
        snprintf(root, sizeof(root), "%c:\\", letter);
        ULARGE_INTEGER freeB, totalB, totalFreeB;
        if (!GetDiskFreeSpaceExA(root, &freeB, &totalB, &totalFreeB)) {
            char line[128];
            snprintf(line, sizeof(line), "%s (no access)\n", root);
            strncat(_kf_disk_buf, line, sizeof(_kf_disk_buf) - strlen(_kf_disk_buf) - 1);
            continue;
        }
        unsigned long long totalGB = totalB.QuadPart   / (1024ULL*1024ULL*1024ULL);
        unsigned long long freeGB  = totalFreeB.QuadPart / (1024ULL*1024ULL*1024ULL);
        unsigned long long usedGB  = totalGB - freeGB;
        int pct = (totalGB > 0) ? (int)((double)usedGB / (double)totalGB * 100.0) : 0;
        int usedB = pct * 20 / 100, freeB2 = 20 - usedB;
        char bar[128] = "";
        for (int i = 0; i < usedB;  i++) strcat(bar, "\xe2\x96\x92");
        for (int i = 0; i < freeB2; i++) strcat(bar, "\xe2\x96\x88");
        char line[512];
        snprintf(line, sizeof(line), "[%s]  %s %lluGB/%lluGB %d%%\n",
                 bar, root, usedGB, totalGB, pct);
        strncat(_kf_disk_buf, line, sizeof(_kf_disk_buf) - strlen(_kf_disk_buf) - 1);
    }
    int len = (int)strlen(_kf_disk_buf);
    if (len > 0 && _kf_disk_buf[len-1] == '\n') _kf_disk_buf[len-1] = 0;
    return _kf_disk_buf;
}

static char _kf_con_buf[32];
char* kfconsize() {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (GetConsoleScreenBufferInfo(h, &csbi)) {
        int cols = csbi.srWindow.Right  - csbi.srWindow.Left + 1;
        int rows = csbi.srWindow.Bottom - csbi.srWindow.Top  + 1;
        snprintf(_kf_con_buf, sizeof(_kf_con_buf), "%d,%d", cols, rows);
    } else {
        strcpy(_kf_con_buf, "0,0");
    }
    return _kf_con_buf;
}

static char _kf_tick_buf[32];
char* kfticks() {
    unsigned long long ms = GetTickCount64();
    if (ms > 2147483647ULL) ms = 2147483647ULL;
    snprintf(_kf_tick_buf, sizeof(_kf_tick_buf), "%llu", ms);
    return _kf_tick_buf;
}

/* kfuptimesec – uptime in whole seconds, safe for krypton int arithmetic */
static char _kf_upsec_buf[32];
char* kfuptimesec() {
    unsigned long long secs = GetTickCount64() / 1000ULL;
    if (secs > 2147483647ULL) secs = 2147483647ULL;
    snprintf(_kf_upsec_buf, sizeof(_kf_upsec_buf), "%llu", secs);
    return _kf_upsec_buf;
}

/* kfosedition – Windows edition ID from registry, e.g. "Professional" */
static char _kf_edition_buf[64];
char* kfosedition() {
    _kf_edition_buf[0] = '\0';
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
            0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        DWORD type = REG_SZ, sz = (DWORD)sizeof(_kf_edition_buf);
        RegQueryValueExA(hKey, "EditionID", NULL, &type,
                         (LPBYTE)_kf_edition_buf, &sz);
        RegCloseKey(hKey);
    }
    return _kf_edition_buf;
}

/*
 * kfvram – GPU VRAM info via DXGI (accurate 64-bit DedicatedVideoMemory,
 * works for NVIDIA/AMD/Intel on all GPU generations including Blackwell).
 * Format per line: "totalMB:0"  (newline-separated, up to 2 GPUs)
 * Falls back to registry scan if DXGI is unavailable.
 */

/* Minimal DXGI adapter desc — matches IDXGIAdapter::GetDesc ABI exactly */
typedef struct {
    WCHAR  Description[128];
    UINT   VendorId, DeviceId, SubSysId, Revision;
    SIZE_T DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
    LUID   AdapterLuid;
} KfDxgiAdapterDesc;

/* kf_pdh_gpu_used_mb – system-wide dedicated VRAM usage via PDH performance
 * counters (same source as Task Manager). Returns MB, or 0 on failure.     */
static unsigned long long kf_pdh_gpu_used_mb(void) {
    PDH_HQUERY   hQuery   = NULL;
    PDH_HCOUNTER hCounter = NULL;
    unsigned long long usedBytes = 0;

    if (PdhOpenQueryA(NULL, 0, &hQuery) != ERROR_SUCCESS) return 0;
    /* "GPU Adapter Memory\Dedicated Usage" – bytes of dedicated VRAM in use */
    if (PdhAddEnglishCounterA(hQuery,
            "\\GPU Adapter Memory(*)\\Dedicated Usage",
            0, &hCounter) != ERROR_SUCCESS) {
        PdhCloseQuery(hQuery); return 0;
    }
    PdhCollectQueryData(hQuery);

    DWORD bufSz = 0, itemCnt = 0;
    PdhGetFormattedCounterArrayA(hCounter, PDH_FMT_LARGE, &bufSz, &itemCnt, NULL);
    if (bufSz > 0) {
        PDH_FMT_COUNTERVALUE_ITEM_A *items =
            (PDH_FMT_COUNTERVALUE_ITEM_A*)malloc(bufSz);
        if (items) {
            if (PdhGetFormattedCounterArrayA(hCounter, PDH_FMT_LARGE,
                    &bufSz, &itemCnt, items) == ERROR_SUCCESS) {
                DWORD j;
                for (j = 0; j < itemCnt; j++) {
                    if (items[j].FmtValue.CStatus == 0 ||
                            items[j].FmtValue.CStatus == 0x00000200L)
                        usedBytes += (unsigned long long)items[j].FmtValue.largeValue;
                }
            }
            free(items);
        }
    }
    PdhCloseQuery(hQuery);
    return usedBytes / (1024ULL * 1024ULL);
}

static char _kf_vram_buf[256];
char* kfvram() {
    _kf_vram_buf[0] = '\0';

    /* ── DXGI path ──
     * IDXGIFactory  vtable slots: [0-2]=IUnknown [3-6]=IDXGIObject
     *                             [7]=EnumAdapters
     * IDXGIAdapter  vtable slots: [7]=EnumOutputs [8]=GetDesc [9]=CheckInterfaceSupport
     * IDXGIAdapter3 vtable slots: [10]=GetDesc1 [11]=GetDesc2
     *                             [12-13]=HW protection [14]=QueryVideoMemoryInfo */
    typedef HRESULT (WINAPI *PFN_CreateDXGIFactory)(const void*, void**);
    static const GUID KF_IID_IDXGIFactory = {
        0x7b7166ec, 0x21c7, 0x44ae,
        {0xb2, 0x1a, 0xc9, 0xae, 0x32, 0x1a, 0xe3, 0x69}
    };

    /* Query system-wide dedicated VRAM usage via PDH (works for all vendors) */
    unsigned long long pdhUsedMB = kf_pdh_gpu_used_mb();

    HMODULE hDxgi = LoadLibraryA("dxgi.dll");
    if (hDxgi) {
        PFN_CreateDXGIFactory pCreate =
            (PFN_CreateDXGIFactory)GetProcAddress(hDxgi, "CreateDXGIFactory");
        if (pCreate) {
            void *pFactory = NULL;
            if (SUCCEEDED(pCreate(&KF_IID_IDXGIFactory, &pFactory)) && pFactory) {
                typedef HRESULT (__stdcall *EnumAdapters_t)(void*, UINT, void**);
                typedef HRESULT (__stdcall *GetDesc_t)(void*, KfDxgiAdapterDesc*);
                typedef ULONG   (__stdcall *Release_t)(void*);

                void **fvt   = *(void***)pFactory;
                EnumAdapters_t pEnum = (EnumAdapters_t)fvt[7];
                Release_t      pFRel = (Release_t)fvt[2];

                int cnt = 0;
                for (UINT i = 0; cnt < 2; i++) {
                    void *pAdapter = NULL;
                    if (FAILED(pEnum(pFactory, i, &pAdapter)) || !pAdapter) break;
                    void **avt = *(void***)pAdapter;
                    GetDesc_t pGetDesc = (GetDesc_t)avt[8];
                    Release_t pARel    = (Release_t)avt[2];

                    KfDxgiAdapterDesc desc;
                    memset(&desc, 0, sizeof(desc));
                    if (SUCCEEDED(pGetDesc(pAdapter, &desc)) &&
                            desc.DedicatedVideoMemory > 0) {
                        unsigned long long totalMB =
                            desc.DedicatedVideoMemory / (1024ULL * 1024ULL);
                        /* Attach PDH usage to first GPU only; clamp to total */
                        unsigned long long usedMB =
                            (cnt == 0 && pdhUsedMB <= totalMB) ? pdhUsedMB : 0;
                        char entry[64];
                        snprintf(entry, sizeof(entry), "%llu:%llu", totalMB, usedMB);
                        if (_kf_vram_buf[0]) strcat(_kf_vram_buf, "\n");
                        strcat(_kf_vram_buf, entry);
                        cnt++;
                    }
                    pARel(pAdapter);
                }
                pFRel(pFactory);
                if (_kf_vram_buf[0]) { FreeLibrary(hDxgi); return _kf_vram_buf; }
            }
        }
        FreeLibrary(hDxgi);
    }

    /* ── Registry fallback ── */
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "SYSTEM\\CurrentControlSet\\Control\\Video",
            0, KEY_READ, &hKey) != ERROR_SUCCESS) return _kf_vram_buf;
    static const char *vkeys[] = {
        "HardwareInformation.qwMemorySize",
        "HardwareInformation.MemorySize",
        "HardwareInformation.MemorySizeLegacy"
    };
    char sub[256]; DWORD subLen = sizeof(sub), ridx = 0, cnt2 = 0;
    while (RegEnumKeyExA(hKey, ridx, sub, &subLen,
            NULL, NULL, NULL, NULL) == ERROR_SUCCESS && cnt2 < 2) {
        char path[512];
        snprintf(path, sizeof(path),
            "SYSTEM\\CurrentControlSet\\Control\\Video\\%s\\0000", sub);
        HKEY hSub;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &hSub) == ERROR_SUCCESS) {
            int k;
            for (k = 0; k < 3; k++) {
                unsigned long long mem = 0;
                DWORD msz = sizeof(mem);
                if (RegQueryValueExA(hSub, vkeys[k], NULL, NULL,
                        (LPBYTE)&mem, &msz) == ERROR_SUCCESS && mem > 0) {
                    unsigned long long totalMB = mem / (1024ULL * 1024ULL);
                    char entry[64];
                    snprintf(entry, sizeof(entry), "%llu:0", totalMB);
                    if (_kf_vram_buf[0]) strcat(_kf_vram_buf, "\n");
                    strcat(_kf_vram_buf, entry);
                    cnt2++; break;
                }
            }
            RegCloseKey(hSub);
        }
        subLen = sizeof(sub); ridx++;
    }
    RegCloseKey(hKey);
    return _kf_vram_buf;
}

/* kfpkgs – count installed packages from winget (registry), scoop, and choco.
 * Returns a string like "142 (winget), 23 (scoop), 8 (choco)"
 * Only includes managers that are actually present on the system.
 */
static int kf_count_regkeys(HKEY root, const char *path) {
    HKEY hKey;
    if (RegOpenKeyExA(root, path, 0, KEY_READ, &hKey) != ERROR_SUCCESS) return 0;
    DWORD count = 0;
    RegQueryInfoKeyA(hKey, NULL, NULL, NULL, &count, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    RegCloseKey(hKey);
    return (int)count;
}

static int kf_count_subdirs(const char *path) {
    char pattern[MAX_PATH];
    snprintf(pattern, sizeof(pattern), "%s\\*", path);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return -1;
    int count = 0;
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
            strcmp(fd.cFileName, ".") && strcmp(fd.cFileName, ".."))
            count++;
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    return count;
}

static char _kf_pkgs_buf[256];
char* kfpkgs() {
    _kf_pkgs_buf[0] = '\0';
    int first = 1;
    char tmp[64];

    /* winget: sum registry uninstall keys across HKLM (64+32-bit) and HKCU */
    int wpkgs =
        kf_count_regkeys(HKEY_LOCAL_MACHINE,
            "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall") +
        kf_count_regkeys(HKEY_LOCAL_MACHINE,
            "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall") +
        kf_count_regkeys(HKEY_CURRENT_USER,
            "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall");
    if (wpkgs > 0) {
        snprintf(tmp, sizeof(tmp), "%d (winget)", wpkgs);
        strcat(_kf_pkgs_buf, tmp);
        first = 0;
    }

    /* scoop: count dirs in %USERPROFILE%\scoop\apps, subtract 1 for scoop itself */
    char scoop_path[MAX_PATH];
    DWORD sz = GetEnvironmentVariableA("USERPROFILE", scoop_path, sizeof(scoop_path));
    if (sz > 0 && sz < sizeof(scoop_path)) {
        strncat(scoop_path, "\\scoop\\apps", sizeof(scoop_path) - strlen(scoop_path) - 1);
        int sc = kf_count_subdirs(scoop_path);
        if (sc > 1) {
            sc--;
            snprintf(tmp, sizeof(tmp), "%s%d (scoop)", first ? "" : ", ", sc);
            strcat(_kf_pkgs_buf, tmp);
            first = 0;
        }
    }

    /* choco: count dirs in %ChocolateyInstall%\lib */
    char choco_path[MAX_PATH];
    sz = GetEnvironmentVariableA("ChocolateyInstall", choco_path, sizeof(choco_path));
    if (sz > 0 && sz < sizeof(choco_path)) {
        strncat(choco_path, "\\lib", sizeof(choco_path) - strlen(choco_path) - 1);
        int cc = kf_count_subdirs(choco_path);
        if (cc > 0) {
            snprintf(tmp, sizeof(tmp), "%s%d (choco)", first ? "" : ", ", cc);
            strcat(_kf_pkgs_buf, tmp);
        }
    }

    return _kf_pkgs_buf;
}

/* kfshell – detect current shell by walking up the process tree */
static char _kf_shell_buf[64];
char* kfshell() {
    _kf_shell_buf[0] = '\0';
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return _kf_shell_buf;
    PROCESSENTRY32 pe;
    pe.dwSize = sizeof(pe);
    DWORD myPid = GetCurrentProcessId(), parentPid = 0;
    if (Process32First(hSnap, &pe)) {
        do {
            if (pe.th32ProcessID == myPid) { parentPid = pe.th32ParentProcessID; break; }
        } while (Process32Next(hSnap, &pe));
    }
    if (parentPid) {
        pe.dwSize = sizeof(pe);
        if (Process32First(hSnap, &pe)) {
            do {
                if (pe.th32ProcessID == parentPid) {
                    char *n = pe.szExeFile;
                    if      (_stricmp(n, "pwsh.exe")       == 0) strcpy(_kf_shell_buf, "PowerShell");
                    else if (_stricmp(n, "powershell.exe") == 0) strcpy(_kf_shell_buf, "Windows PowerShell");
                    else if (_stricmp(n, "cmd.exe")        == 0) strcpy(_kf_shell_buf, "cmd");
                    else if (_stricmp(n, "bash.exe")       == 0) strcpy(_kf_shell_buf, "bash");
                    else if (_stricmp(n, "zsh.exe")        == 0) strcpy(_kf_shell_buf, "zsh");
                    else if (_stricmp(n, "fish.exe")       == 0) strcpy(_kf_shell_buf, "fish");
                    else if (_stricmp(n, "nu.exe")         == 0) strcpy(_kf_shell_buf, "nushell");
                    else if (_stricmp(n, "sh.exe")         == 0) strcpy(_kf_shell_buf, "sh");
                    else {
                        strncpy(_kf_shell_buf, n, sizeof(_kf_shell_buf) - 1);
                        char *dot = strrchr(_kf_shell_buf, '.');
                        if (dot && _stricmp(dot, ".exe") == 0) *dot = '\0';
                    }
                    break;
                }
            } while (Process32Next(hSnap, &pe));
        }
    }
    CloseHandle(hSnap);
    return _kf_shell_buf;
}

/* kfterminal – detect terminal emulator from environment variables */
static char _kf_terminal_buf[64];
char* kfterminal() {
    _kf_terminal_buf[0] = '\0';
    char tmp[128];
    if (GetEnvironmentVariableA("WT_SESSION",       tmp, sizeof(tmp)) > 0) { strcpy(_kf_terminal_buf, "Windows Terminal"); return _kf_terminal_buf; }
    if (GetEnvironmentVariableA("ConEmuPID",        tmp, sizeof(tmp)) > 0) { strcpy(_kf_terminal_buf, "ConEmu");           return _kf_terminal_buf; }
    if (GetEnvironmentVariableA("ALACRITTY_SOCKET", tmp, sizeof(tmp)) > 0 ||
        GetEnvironmentVariableA("ALACRITTY_LOG",    tmp, sizeof(tmp)) > 0) { strcpy(_kf_terminal_buf, "Alacritty");        return _kf_terminal_buf; }
    if (GetEnvironmentVariableA("TERM_PROGRAM", _kf_terminal_buf, sizeof(_kf_terminal_buf)) > 0) return _kf_terminal_buf;
    return _kf_terminal_buf;
}

/* kfresolution – primary display resolution */
static char _kf_res_buf[32];
char* kfresolution() {
    int w = GetSystemMetrics(SM_CXSCREEN);
    int h = GetSystemMetrics(SM_CYSCREEN);
    snprintf(_kf_res_buf, sizeof(_kf_res_buf), "%dx%d", w, h);
    return _kf_res_buf;
}

/* kftheme – Windows light/dark mode and accent color hex */
static char _kf_theme_buf[48];
char* kftheme() {
    _kf_theme_buf[0] = '\0';
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_CURRENT_USER,
            "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
            0, KEY_READ, &hKey) != ERROR_SUCCESS) return _kf_theme_buf;
    DWORD light = 1, accent = 0, sz = sizeof(DWORD), type = REG_DWORD;
    RegQueryValueExA(hKey, "AppsUseLightTheme", NULL, &type, (LPBYTE)&light,  &sz);
    sz = sizeof(DWORD);
    RegQueryValueExA(hKey, "AccentColor",       NULL, &type, (LPBYTE)&accent, &sz);
    RegCloseKey(hKey);
    /* AccentColor in registry is AABBGGRR → convert to RRGGBB */
    int r = (accent)       & 0xFF;
    int g = (accent >>  8) & 0xFF;
    int b = (accent >> 16) & 0xFF;
    snprintf(_kf_theme_buf, sizeof(_kf_theme_buf), "%s (#%02X%02X%02X)",
             light ? "Light" : "Dark", r, g, b);
    return _kf_theme_buf;
}

/* kfbattery – battery percentage and charge status; returns "" if no battery */
static char _kf_battery_buf[48];
char* kfbattery() {
    _kf_battery_buf[0] = '\0';
    SYSTEM_POWER_STATUS sps;
    if (!GetSystemPowerStatus(&sps))   return _kf_battery_buf;
    if (sps.BatteryFlag == 128)        return _kf_battery_buf; /* no battery */
    if (sps.BatteryLifePercent == 255) return _kf_battery_buf; /* unknown    */
    const char *status = "";
    if (sps.ACLineStatus == 1) {
        if (sps.BatteryFlag & 8) status = " (charging)";
        else                     status = " (plugged in)";
    }
    snprintf(_kf_battery_buf, sizeof(_kf_battery_buf), "%d%%%s",
             sps.BatteryLifePercent, status);
    return _kf_battery_buf;
}

/* kframbar – 20-char visual RAM usage bar, same style as kfdisk()
 * usedMB and totalMB are decimal string representations of megabytes.
 * Returns "[░░░░░████████████████]" style string (UTF-8 block chars).
 */
static char _kf_rambar_buf[128];
char* kframbar(char* usedMB, char* totalMB) {
    unsigned long long used  = (unsigned long long)atoll(usedMB);
    unsigned long long total = (unsigned long long)atoll(totalMB);
    _kf_rambar_buf[0] = '\0';
    if (total == 0) {
        strcpy(_kf_rambar_buf, "[                    ]");
        return _kf_rambar_buf;
    }
    int pct    = (int)(used * 100 / total);
    int filled = pct * 20 / 100;
    int empty  = 20 - filled;
    strcat(_kf_rambar_buf, "[");
    for (int i = 0; i < filled; i++) strcat(_kf_rambar_buf, "\xe2\x96\x92");
    for (int i = 0; i < empty;  i++) strcat(_kf_rambar_buf, "\xe2\x96\x88");
    strcat(_kf_rambar_buf, "]");
    return _kf_rambar_buf;
}
