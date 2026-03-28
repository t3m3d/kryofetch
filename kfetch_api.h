#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* exec — run a shell command and return its trimmed output */
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

/* init — set UTF-8 output + enable ANSI escape processing */
char* kf_init() {
    SetConsoleOutputCP(65001);
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode = 0;
    GetConsoleMode(h, &mode);
    SetConsoleMode(h, mode | 0x0004); /* ENABLE_VIRTUAL_TERMINAL_PROCESSING */
    return "";
}

/* cls — clear the screen */
char* kf_cls() {
    system("cls");
    return "";
}

/* memory — returns "totalMB,freeMB" */
static char _kf_mem_buf[64];
char* kf_get_memory() {
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

/* disk — returns newline-separated disk lines with bars */
static char _kf_disk_buf[4096];
char* kf_get_disk_info() {
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
        for (int i = 0; i < usedB;  i++) strcat(bar, "\xe2\x96\x92"); /* ▒ */
        for (int i = 0; i < freeB2; i++) strcat(bar, "\xe2\x96\x88"); /* █ */
        char line[512];
        snprintf(line, sizeof(line), "%s %lluGB/%lluGB %d%% [%s]\n",
                 root, usedGB, totalGB, pct, bar);
        strncat(_kf_disk_buf, line, sizeof(_kf_disk_buf) - strlen(_kf_disk_buf) - 1);
    }
    int len = (int)strlen(_kf_disk_buf);
    if (len > 0 && _kf_disk_buf[len-1] == '\n') _kf_disk_buf[len-1] = 0;
    return _kf_disk_buf;
}

/* console size — returns "cols,rows" */
static char _kf_con_buf[32];
char* kf_get_console_size() {
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

/* console code page */
static char _kf_cp_buf[16];
char* kf_get_console_cp() {
    snprintf(_kf_cp_buf, sizeof(_kf_cp_buf), "%u", GetConsoleOutputCP());
    return _kf_cp_buf;
}

/* uptime — returns milliseconds as string (capped at INT_MAX for atoi) */
static char _kf_tick_buf[32];
char* kf_get_tick_ms() {
    unsigned long long ms = GetTickCount64();
    if (ms > 2147483647ULL) ms = 2147483647ULL;
    snprintf(_kf_tick_buf, sizeof(_kf_tick_buf), "%llu", ms);
    return _kf_tick_buf;
}
