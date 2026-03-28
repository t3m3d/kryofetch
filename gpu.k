func gpunames() {
    let raw = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_VideoController).Name\"")
    let result = trim(raw)
    if result == "" { emit "Unknown GPU" }
    emit result
}
