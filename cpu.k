func cpubrand() {
    let raw = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).Name\"")
    let r = trim(raw)
    if r == "" { emit "Unknown CPU" }
    emit r
}

func cpucores() {
    let cr = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).NumberOfCores\"")
    let tr = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).NumberOfLogicalProcessors\"")
    let cores = trim(cr)
    let threads = trim(tr)
    if cores == "" { cores = "?" }
    if threads == "" { threads = "?" }
    emit cores + "," + threads
}

func sysarch() {
    emit trim(exec("echo %PROCESSOR_ARCHITECTURE%"))
}

func sysuser() {
    emit trim(exec("echo %USERNAME%"))
}

func syshost() {
    emit trim(exec("echo %COMPUTERNAME%"))
}
