// gpunames: enumerate GPU names from registry (no WMI/powershell)
func gpunames() {
    let regBase = "SYSTEM\\CurrentControlSet\\Control\\Video"
    let HKLM     = toHandle("2147483650")
    let kread = toHandle("131097")
    let hkBase = handleOut()
    RegOpenKeyExA(HKLM, regBase, toHandle("0"), kread, hkBase)
    let hb = handleGet(hkBase)
    if handleValid(hb) == "0" { emit "Unknown GPU" }
    let result  = ""
    let subBuf  = bufNew("256")
    let subSz   = bufNew("4")
    let idx = "0"
    while toInt(idx) < 16 {
        bufSetDword(subSz, "256")
        let enumRet = RegEnumKeyExA(hb, toHandle(idx), subBuf, subSz, toHandle("0"), toHandle("0"), toHandle("0"), toHandle("0"))
        if toInt(enumRet) != 0 { break }
        let sub = bufStr(subBuf)
        let devPath = regBase + "\\" + sub + "\\0000"
        let gpuName = trim(regHklmStr(devPath, "DriverDesc"))
        if gpuName != "" {
            if result != "" { result = result + "\n" }
            result = result + gpuName
        }
        idx = toInt(idx) + 1 + ""
    }
    RegCloseKey(hb)
    if result == "" { emit "Unknown GPU" }
    emit result
}

// kfvramreg: registry fallback for VRAM when DXGI is unavailable
func kfvramreg() {
    let regBase = "SYSTEM\\CurrentControlSet\\Control\\Video"
    let HKLM    = toHandle("2147483650")
    let kread   = toHandle("131097")
    let hkBase  = handleOut()
    RegOpenKeyExA(HKLM, regBase, toHandle("0"), kread, hkBase)
    let hb = handleGet(hkBase)
    if handleValid(hb) == "0" { emit "" }
    let result = ""
    let cnt    = "0"
    let subBuf = bufNew("256")
    let subSz  = bufNew("4")
    let idx    = "0"
    while toInt(idx) < 16 {
        if toInt(cnt) >= 2 { break }
        bufSetDword(subSz, "256")
        let enumRet = RegEnumKeyExA(hb, toHandle(idx), subBuf, subSz, toHandle("0"), toHandle("0"), toHandle("0"), toHandle("0"))
        if toInt(enumRet) != 0 { break }
        let sub     = bufStr(subBuf)
        let devPath = regBase + "\\" + sub + "\\0000"
        let mem     = regHklmQword(devPath, "HardwareInformation.qwMemorySize")
        if mem == "0" { mem = regHklmDword(devPath, "HardwareInformation.MemorySize") }
        if mem == "0" { mem = regHklmDword(devPath, "HardwareInformation.MemorySizeLegacy") }
        if mem != "0" {
            let mb = div64(mem, "1048576")
            if result != "" { result = result + "\n" }
            result = result + mb + ":0"
            cnt = toInt(cnt) + 1 + ""
        }
        idx = toInt(idx) + 1 + ""
    }
    RegCloseKey(hb)
    emit result
}

// kfpdhgpu: GPU dedicated memory usage in MB via PDH counters
func kfpdhgpu() {
    let hQ  = handleOut()
    let ret = PdhOpenQueryA(toHandle("0"), toHandle("0"), hQ)
    if toInt(ret) != 0 { emit "0" }
    let q   = handleGet(hQ)
    let hC  = handleOut()
    let ret2 = PdhAddEnglishCounterA(q, "\\GPU Adapter Memory(*)\\Dedicated Usage", toHandle("0"), hC)
    if toInt(ret2) != 0 {
        PdhCloseQuery(q)
        emit "0"
    }
    let c = handleGet(hC)
    PdhCollectQueryData(q)
    let szBuf  = bufNew("4")
    let cntBuf = bufNew("4")
    bufSetDword(szBuf, "0")
    bufSetDword(cntBuf, "0")
    // PDH_FMT_LARGE = 0x400 = 1024; first call with null items gets required buffer size
    PdhGetFormattedCounterArrayA(c, toHandle("1024"), szBuf, cntBuf, toHandle("0"))
    let sz  = bufGetDword(szBuf)
    let cnt = bufGetDword(cntBuf)
    if toInt(sz) == 0 {
        PdhCloseQuery(q)
        emit "0"
    }
    let items = bufNew(sz)
    PdhGetFormattedCounterArrayA(c, toHandle("1024"), szBuf, cntBuf, items)
    // PDH_FMT_COUNTERVALUE_ITEM_A layout on 64-bit Windows:
    //   offset  0: szName     (LPSTR,    8 bytes)
    //   offset  8: CStatus    (DWORD,    4 bytes)
    //   offset 12: padding    (          4 bytes)
    //   offset 16: largeValue (LONGLONG, 8 bytes)
    //   sizeof = 24 bytes per item
    let used = "0"
    let i = "0"
    while toInt(i) < toInt(cnt) {
        let off    = toInt(i) * 24
        let status = bufGetDwordAt(items, off + 8)
        let ok = "0"
        if status == "0"   { ok = "1" }
        if status == "512" { ok = "1" }
        if ok == "1" {
            let valMB = div64(bufGetQwordAt(items, off + 16), "1048576")
            used = toInt(used) + toInt(valMB) + ""
        }
        i = toInt(i) + 1 + ""
    }
    PdhCloseQuery(q)
    emit used
}

// kfdxgivram: enumerate GPU total VRAM via DXGI COM vtable (pure Krypton)
func kfdxgivram() {
    // IID_IDXGIFactory: {7b7166ec-21c7-44ae-b21a-c9ae321ae369}
    // Stored as 4 LE DWORDs: Data1, Data2|Data3, Data4[0-3], Data4[4-7]
    let guid = bufNew("16")
    bufSetDwordAt(guid, "0",  "2071029484")   // 0x7B7166EC
    bufSetDwordAt(guid, "4",  "1152262599")   // 0x44AE21C7
    bufSetDwordAt(guid, "8",  "4006156978")   // 0xAEC91AB2
    bufSetDwordAt(guid, "12", "1776491058")   // 0x69E31A32

    let hD = LoadLibraryA("dxgi.dll")
    if handleValid(hD) == "0" { emit "" }

    let pC = GetProcAddress(hD, "CreateDXGIFactory")
    if handleValid(pC) == "0" {
        FreeLibrary(hD)
        emit ""
    }

    let pFOut = handleOut()
    let hr1   = callPtr(pC, guid, pFOut)
    let pF    = handleGet(pFOut)
    if toInt(handleInt(hr1)) < 0 {
        FreeLibrary(hD)
        emit ""
    }
    if handleValid(pF) == "0" {
        FreeLibrary(hD)
        emit ""
    }

    // vtable slot 7 = EnumAdapters, slot 2 = Release
    let fv  = ptrDeref(pF)
    let pE  = ptrIndex(fv, "7")
    let pFR = ptrIndex(fv, "2")

    let result = ""
    let cnt    = "0"
    let i      = "0"
    while toInt(cnt) < 2 {
        let pAOut = handleOut()
        let hr2   = callPtr(pE, pF, toHandle(i), pAOut)
        if toInt(handleInt(hr2)) < 0 { break }
        let pA = handleGet(pAOut)
        if handleValid(pA) == "0" { break }

        // vtable slot 8 = GetDesc, slot 2 = Release
        let av  = ptrDeref(pA)
        let pG  = ptrIndex(av, "8")
        let pAR = ptrIndex(av, "2")

        // DXGI_ADAPTER_DESC layout (64-bit):
        //   offset   0: Description WCHAR[128] (256 bytes)
        //   offset 256: VendorId/DeviceId/SubSysId/Revision (16 bytes)
        //   offset 272: DedicatedVideoMemory SIZE_T (8 bytes)
        let desc = bufNew("304")
        callPtr(pG, pA, desc)
        let vram = bufGetQwordAt(desc, "272")
        if vram != "0" {
            let mb = div64(vram, "1048576")
            if result != "" { result = result + "\n" }
            result = result + mb
            cnt = toInt(cnt) + 1 + ""
        }
        callPtr(pAR, pA)
        i = toInt(i) + 1 + ""
    }
    callPtr(pFR, pF)
    FreeLibrary(hD)
    emit result
}

func gpuvram() {
    let v = trim(kfdxgivram())
    if v == "" { emit kfvramreg() }
    let used   = kfpdhgpu()
    let n      = linecount(v)
    let result = ""
    let i = "0"
    while toInt(i) < toInt(n) {
        let line  = nthline(v, i)
        let entry = line + ":0"
        if i == "0" { entry = line + ":" + used }
        if result != "" { result = result + "\n" }
        result = result + entry
        i = toInt(i) + 1 + ""
    }
    if result != "" { emit result }
    emit kfvramreg()
}

// fmtgpu: formats GPU name + VRAM stats like disk lines (used/total pct% [bar])
func fmtgpu(name, vramLine) {
    if name == "" { emit "" }
    if vramLine == "" { emit name }
    let tb = firstpart(vramLine, ":")
    let ub = afterpart(vramLine, ":")
    if toInt(tb) == 0 { emit name }
    let n   = toInt(tb)
    let gb  = n / 1024
    let t   = n * 10 / 1024 - gb * 10
    if toInt(ub) > 0 {
        let un  = toInt(ub)
        let ugb = un / 1024
        let ut  = un * 10 / 1024 - ugb * 10
        let pct = un * 100 / n
        let bar = rambar(ub, tb)
        emit bar + "  " + name + "  " + ugb + "." + ut + " GB / " + gb + "." + t + " GB  " + pct + "%"
    }
    emit name + " (" + gb + "." + t + " GB VRAM)"
}
