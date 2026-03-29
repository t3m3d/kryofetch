#pragma once
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#include <windows.h>
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
        snprintf(line, sizeof(line), "%s %lluGB/%lluGB %d%% [%s]\n",
                 root, usedGB, totalGB, pct, bar);
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

/* ── NVAPI thin-layer for GPU VRAM ───────────────────────────────────── */
#define KF_NVAPI_OK 0
typedef int          KfNvStatus;
typedef unsigned int KfNvU32;
typedef struct {
    KfNvU32 version;
    KfNvU32 dedicatedVideoMemory;           /* total  VRAM, KB */
    KfNvU32 availableDedicatedVideoMemory;  /* free   VRAM, KB */
    KfNvU32 systemVideoMemory;
    KfNvU32 sharedSystemMemory;
} KfNvMemInfo;
#define KF_NV_MEM_VER (sizeof(KfNvMemInfo) | (1 << 16))

typedef KfNvStatus (__cdecl *KfNvQI_t)(unsigned int);
typedef KfNvStatus (__cdecl *KfNvInit_t)(void);
typedef KfNvStatus (__cdecl *KfNvEnum_t)(void**, KfNvU32*);
typedef KfNvStatus (__cdecl *KfNvMem_t)(void*, KfNvMemInfo*);

static KfNvQI_t   _kfNvQI   = NULL;
static KfNvInit_t _kfNvInit = NULL;
static KfNvEnum_t _kfNvEnum = NULL;
static KfNvMem_t  _kfNvMem  = NULL;
static int        _kfNvState = -1;

static int kf_nv_init(void) {
    if (_kfNvState >= 0) return _kfNvState;
    HMODULE h = LoadLibraryA("nvapi64.dll");
    if (!h) { _kfNvState = 0; return 0; }
    _kfNvQI = (KfNvQI_t)GetProcAddress(h, "nvapi_QueryInterface");
    if (!_kfNvQI) { _kfNvState = 0; return 0; }
    _kfNvInit = (KfNvInit_t)(uintptr_t)_kfNvQI(0x0150E828);
    _kfNvEnum = (KfNvEnum_t)(uintptr_t)_kfNvQI(0xE5AC921F);
    _kfNvMem  = (KfNvMem_t) (uintptr_t)_kfNvQI(0x0703F2E2);
    if (!_kfNvInit || !_kfNvEnum || !_kfNvMem) { _kfNvState = 0; return 0; }
    _kfNvState = (_kfNvInit() == KF_NVAPI_OK) ? 1 : 0;
    return _kfNvState;
}

/*
 * kfvram – GPU VRAM info, one entry per GPU, newline-separated.
 * Format per line: "totalMB:usedMB"  (usedMB=0 means usage unavailable)
 *
 * Tries NVAPI first (NVIDIA only, gives real used/free).
 * Falls back to registry scan (total only, works for AMD/Intel too).
 */
static char _kf_vram_buf[256];
char* kfvram() {
    _kf_vram_buf[0] = '\0';

    /* ── NVAPI path ── */
    if (kf_nv_init()) {
        void    *handles[16] = {0};
        KfNvU32  count = 0;
        if (_kfNvEnum(handles, &count) == KF_NVAPI_OK && count > 0) {
            KfNvU32 i;
            for (i = 0; i < count && i < 2; i++) {
                KfNvMemInfo info;
                memset(&info, 0, sizeof(info));
                info.version = KF_NV_MEM_VER;
                if (_kfNvMem(handles[i], &info) == KF_NVAPI_OK) {
                    unsigned long long tot  = (unsigned long long)info.dedicatedVideoMemory / 1024ULL;
                    unsigned long long free_ = (unsigned long long)info.availableDedicatedVideoMemory / 1024ULL;
                    unsigned long long used = (tot > free_) ? tot - free_ : 0;
                    char entry[64];
                    snprintf(entry, sizeof(entry), "%llu:%llu", tot, used);
                    if (_kf_vram_buf[0] != '\0') strcat(_kf_vram_buf, "\n");
                    strcat(_kf_vram_buf, entry);
                }
            }
            if (_kf_vram_buf[0] != '\0') return _kf_vram_buf;
        }
    }

    /* ── Registry fallback ── */
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
            "SYSTEM\\CurrentControlSet\\Control\\Video",
            0, KEY_READ, &hKey) != ERROR_SUCCESS) return _kf_vram_buf;

    static const char *vkeys[] = {
        "HardwareInformation.MemorySize",
        "HardwareInformation.MemorySizeLegacy",
        "HardwareInformation.qwMemorySize"
    };

    char sub[256]; DWORD subLen = sizeof(sub), ridx = 0, cnt = 0;
    while (RegEnumKeyExA(hKey, ridx, sub, &subLen,
            NULL, NULL, NULL, NULL) == ERROR_SUCCESS && cnt < 2) {
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
                    if (_kf_vram_buf[0] != '\0') strcat(_kf_vram_buf, "\n");
                    strcat(_kf_vram_buf, entry);
                    cnt++; break;
                }
            }
            RegCloseKey(hSub);
        }
        subLen = sizeof(sub); ridx++;
    }
    RegCloseKey(hKey);
    return _kf_vram_buf;
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
