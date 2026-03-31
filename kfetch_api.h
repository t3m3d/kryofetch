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

// exec: run a shell command and return trimmed output
static char _kf_exec_buf[8192];
char* exec(char* cmd) {
    _kf_exec_buf[0] = 0;
    FILE* p = _popen(cmd, "r");
    if (!p) return _kf_exec_buf;
    int pos = 0, c;
    while (pos < (int)sizeof(_kf_exec_buf)-1 && (c=fgetc(p)) != EOF)
        _kf_exec_buf[pos++] = (char)c;
    _kf_exec_buf[pos] = 0;
    _pclose(p);
    while (pos > 0 && (_kf_exec_buf[pos-1]=='\r'||_kf_exec_buf[pos-1]=='\n'||_kf_exec_buf[pos-1]==' '))
        _kf_exec_buf[--pos] = 0;
    return _kf_exec_buf;
}

// kfmem: returns "totalMB,freeMB"
static char _kf_mem_buf[64];
char* kfcls()   { system("cls"); return ""; }
char* kfinit()  { SetConsoleOutputCP(65001); HANDLE h=GetStdHandle(STD_OUTPUT_HANDLE); DWORD m=0; GetConsoleMode(h,&m); SetConsoleMode(h,m|0x0004); return ""; }

char* kfmem() {
    MEMORYSTATUSEX ms;
    ZeroMemory(&ms, sizeof(ms));
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        unsigned long long total = ms.ullTotalPhys / (1024ULL*1024ULL);
        unsigned long long free_ = ms.ullAvailPhys / (1024ULL*1024ULL);
        snprintf(_kf_mem_buf, sizeof(_kf_mem_buf), "%llu,%llu", total, free_);
    } else { strcpy(_kf_mem_buf, "0,0"); }
    return _kf_mem_buf;
}

// kfdisk: newline-separated "[bar]  X: usedGB/totalGB pct%"
static char _kf_disk_buf[4096];
char* kfdisk() {
    _kf_disk_buf[0] = 0;
    DWORD drives = GetLogicalDrives();
    for (char letter = 'A'; letter <= 'Z'; letter++) {
        if (!(drives & (1 << (letter-'A')))) continue;
        char root[4];
        snprintf(root, sizeof(root), "%c:\\", letter);
        ULARGE_INTEGER freeB, totalB, totalFreeB;
        if (!GetDiskFreeSpaceExA(root, &freeB, &totalB, &totalFreeB)) continue;
        unsigned long long totalGB = totalB.QuadPart   / (1024ULL*1024ULL*1024ULL);
        unsigned long long freeGB  = totalFreeB.QuadPart / (1024ULL*1024ULL*1024ULL);
        unsigned long long usedGB  = totalGB - freeGB;
        int pct = (totalGB > 0) ? (int)((double)usedGB/(double)totalGB*100.0) : 0;
        int usedB = pct*20/100, freeB2 = 20-usedB;
        char bar[128] = "";
        for (int i=0;i<usedB; i++) strcat(bar,"\xe2\x96\x92");
        for (int i=0;i<freeB2;i++) strcat(bar,"\xe2\x96\x88");
        char line[512];
        snprintf(line,sizeof(line),"[%s]  %s %lluGB/%lluGB %d%%\n",bar,root,usedGB,totalGB,pct);
        strncat(_kf_disk_buf,line,sizeof(_kf_disk_buf)-strlen(_kf_disk_buf)-1);
    }
    int len=(int)strlen(_kf_disk_buf);
    if (len>0 && _kf_disk_buf[len-1]=='\n') _kf_disk_buf[len-1]=0;
    return _kf_disk_buf;
}

// kfconsize: returns "cols,rows"
static char _kf_con_buf[32];
char* kfconsize() {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (GetConsoleScreenBufferInfo(h, &csbi)) {
        int cols = csbi.srWindow.Right  - csbi.srWindow.Left + 1;
        int rows = csbi.srWindow.Bottom - csbi.srWindow.Top  + 1;
        snprintf(_kf_con_buf, sizeof(_kf_con_buf), "%d,%d", cols, rows);
    } else { strcpy(_kf_con_buf, "0,0"); }
    return _kf_con_buf;
}

// kfvram: newline-separated "totalMB:usedMB" per GPU
typedef struct {
    WCHAR  Description[128];
    UINT   VendorId, DeviceId, SubSysId, Revision;
    SIZE_T DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
    LUID   AdapterLuid;
} KfDxgiAdapterDesc;

static unsigned long long kf_pdh_gpu_used_mb(void) {
    PDH_HQUERY hQ=NULL; PDH_HCOUNTER hC=NULL; unsigned long long used=0;
    if (PdhOpenQueryA(NULL,0,&hQ)!=ERROR_SUCCESS) return 0;
    if (PdhAddEnglishCounterA(hQ,"\\GPU Adapter Memory(*)\\Dedicated Usage",0,&hC)!=ERROR_SUCCESS) { PdhCloseQuery(hQ); return 0; }
    PdhCollectQueryData(hQ);
    DWORD sz=0,cnt=0;
    PdhGetFormattedCounterArrayA(hC,PDH_FMT_LARGE,&sz,&cnt,NULL);
    if (sz>0) {
        PDH_FMT_COUNTERVALUE_ITEM_A *items=(PDH_FMT_COUNTERVALUE_ITEM_A*)malloc(sz);
        if (items) {
            if (PdhGetFormattedCounterArrayA(hC,PDH_FMT_LARGE,&sz,&cnt,items)==ERROR_SUCCESS)
                for (DWORD j=0;j<cnt;j++)
                    if (items[j].FmtValue.CStatus==0||items[j].FmtValue.CStatus==0x200L)
                        used+=(unsigned long long)items[j].FmtValue.largeValue;
            free(items);
        }
    }
    PdhCloseQuery(hQ);
    return used/(1024ULL*1024ULL);
}

static char _kf_vram_buf[256];
char* kfvram() {
    _kf_vram_buf[0]='\0';
    typedef HRESULT (WINAPI *PFN_CreateDXGIFactory)(const void*,void**);
    static const GUID KF_IID = {0x7b7166ec,0x21c7,0x44ae,{0xb2,0x1a,0xc9,0xae,0x32,0x1a,0xe3,0x69}};
    unsigned long long pdhUsed=kf_pdh_gpu_used_mb();
    HMODULE hD=LoadLibraryA("dxgi.dll");
    if (hD) {
        PFN_CreateDXGIFactory pC=(PFN_CreateDXGIFactory)GetProcAddress(hD,"CreateDXGIFactory");
        if (pC) {
            void *pF=NULL;
            if (SUCCEEDED(pC(&KF_IID,&pF))&&pF) {
                typedef HRESULT(__stdcall*EnumA_t)(void*,UINT,void**);
                typedef HRESULT(__stdcall*GetD_t)(void*,KfDxgiAdapterDesc*);
                typedef ULONG  (__stdcall*Rel_t)(void*);
                void **fv=*(void***)pF;
                EnumA_t pE=(EnumA_t)fv[7]; Rel_t pFR=(Rel_t)fv[2];
                int cnt=0;
                for (UINT i=0;cnt<2;i++) {
                    void *pA=NULL;
                    if (FAILED(pE(pF,i,&pA))||!pA) break;
                    void **av=*(void***)pA;
                    GetD_t pG=(GetD_t)av[8]; Rel_t pAR=(Rel_t)av[2];
                    KfDxgiAdapterDesc desc; memset(&desc,0,sizeof(desc));
                    if (SUCCEEDED(pG(pA,&desc))&&desc.DedicatedVideoMemory>0) {
                        unsigned long long tMB=desc.DedicatedVideoMemory/(1024ULL*1024ULL);
                        unsigned long long uMB=(cnt==0&&pdhUsed<=tMB)?pdhUsed:0;
                        char e[64]; snprintf(e,sizeof(e),"%llu:%llu",tMB,uMB);
                        if (_kf_vram_buf[0]) strcat(_kf_vram_buf,"\n");
                        strcat(_kf_vram_buf,e); cnt++;
                    }
                    pAR(pA);
                }
                pFR(pF);
                if (_kf_vram_buf[0]) { FreeLibrary(hD); return _kf_vram_buf; }
            }
        }
        FreeLibrary(hD);
    }
    // Registry fallback
    HKEY hK;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,"SYSTEM\\CurrentControlSet\\Control\\Video",0,KEY_READ,&hK)!=ERROR_SUCCESS) return _kf_vram_buf;
    static const char *vk[]={"HardwareInformation.qwMemorySize","HardwareInformation.MemorySize","HardwareInformation.MemorySizeLegacy"};
    char sub[256]; DWORD sl=sizeof(sub),ri=0,cnt2=0;
    while (RegEnumKeyExA(hK,ri,sub,&sl,NULL,NULL,NULL,NULL)==ERROR_SUCCESS&&cnt2<2) {
        char path[512]; snprintf(path,sizeof(path),"SYSTEM\\CurrentControlSet\\Control\\Video\\%s\\0000",sub);
        HKEY hS;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,path,0,KEY_READ,&hS)==ERROR_SUCCESS) {
            for (int k=0;k<3;k++) {
                unsigned long long mem=0; DWORD msz=sizeof(mem);
                if (RegQueryValueExA(hS,vk[k],NULL,NULL,(LPBYTE)&mem,&msz)==ERROR_SUCCESS&&mem>0) {
                    char e[64]; snprintf(e,sizeof(e),"%llu:0",mem/(1024ULL*1024ULL));
                    if (_kf_vram_buf[0]) strcat(_kf_vram_buf,"\n");
                    strcat(_kf_vram_buf,e); cnt2++; break;
                }
            }
            RegCloseKey(hS);
        }
        sl=sizeof(sub); ri++;
    }
    RegCloseKey(hK);
    return _kf_vram_buf;
}
