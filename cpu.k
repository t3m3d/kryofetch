import "windows.krh"

func cpubrand() {
    let regPath = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"
    let name    = trim(regHklmStr(regPath, "ProcessorNameString"))
    if name == "" { emit "Unknown CPU" }
    emit name
}

func cpucores() {
    let si      = structNew("SYSTEM_INFO")
    GetNativeSystemInfo(si)
    let logical = structGet(si, "SYSTEM_INFO", "dwNumberOfProcessors")
    let hK = LoadLibraryA("kernel32.dll")
    if handleValid(hK) == "0" { emit logical + "," + logical }
    let pGLPI = GetProcAddress(hK, "GetLogicalProcessorInformationEx")
    if handleValid(pGLPI) == "0" { FreeLibrary(hK)  emit logical + "," + logical }
    let sz = bufNew("4")
    bufSetDword(sz, "0")
    callPtr(pGLPI, toHandle("0"), toHandle("0"), sz)
    let bufLen = bufGetDword(sz)
    if toInt(bufLen) == 0 { FreeLibrary(hK)  emit logical + "," + logical }
    let info = bufNew(bufLen)
    let ret  = handleInt(callPtr(pGLPI, toHandle("0"), info, sz))
    FreeLibrary(hK)
    if toInt(ret) == 0 { emit logical + "," + logical }
    let physical = "0"
    let off = "0"
    while toInt(off) < toInt(bufLen) {
        let rel = bufGetDwordAt(info, toInt(off))
        let esz = bufGetDwordAt(info, toInt(off) + 4)
        if rel == "0" { physical = toInt(physical) + 1 + "" }
        if toInt(esz) == 0 { break }
        off = toInt(off) + toInt(esz) + ""
    }
    if toInt(physical) == 0 { physical = logical }
    emit physical + "," + logical
}
