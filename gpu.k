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

func gpuvram() {
    let v = trim(kfvram())
    if v != "" { emit v }
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
