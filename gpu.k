func gpunames() {
    let raw = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_VideoController).Name\"")
    let result = trim(raw)
    if result == "" { emit "Unknown GPU" }
    emit result
}

func gpuvram() {
    emit trim(kfvram())
}

// fmtgpu: combines GPU name with VRAM size from a "totalMB:usedMB" line
func fmtgpu(name, vramLine) {
    if name == "" { emit "" }
    if vramLine == "" { emit name }
    let tb = firstpart(vramLine, ":")
    if toInt(tb) == 0 { emit name }
    let n  = toInt(tb)
    let gb = n / 1024
    let t  = n * 10 / 1024 - gb * 10
    emit name + " (" + gb + "." + t + " GB VRAM)"
}
