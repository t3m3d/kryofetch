func gpunames() {
    let raw = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_VideoController).Name\"")
    let result = trim(raw)
    if result == "" { emit "Unknown GPU" }
    emit result
}

func gpuvram() {
    emit trim(kfvram())
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
        let bar = kframbar(ub, tb)
        emit name + "  " + ugb + "." + ut + " GB / " + gb + "." + t + " GB  " + pct + "%  " + bar
    }
    emit name + " (" + gb + "." + t + " GB VRAM)"
}
