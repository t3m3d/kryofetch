// cpu.k — CPU and user/system info via WMIC

func get_cpu_brand() {
    let raw = exec("wmic cpu get name /value")
    let eq = indexOf(raw, "=")
    if eq < 0 { emit "Unknown CPU" }
    emit trim(substring(raw, toInt(eq) + 1, len(raw)))
}

func get_cpu_core_info() {
    let cRaw = exec("wmic cpu get NumberOfCores /value")
    let ceq = indexOf(cRaw, "=")
    let cores = "?"
    if ceq >= 0 { cores = trim(substring(cRaw, toInt(ceq) + 1, len(cRaw))) }

    let tRaw = exec("wmic cpu get NumberOfLogicalProcessors /value")
    let teq = indexOf(tRaw, "=")
    let threads = "?"
    if teq >= 0 { threads = trim(substring(tRaw, toInt(teq) + 1, len(tRaw))) }

    emit cores + "," + threads
}

func get_arch() {
    let raw = exec("echo %PROCESSOR_ARCHITECTURE%")
    emit trim(raw)
}

func get_username() {
    let raw = exec("echo %USERNAME%")
    emit trim(raw)
}

func get_computername() {
    let raw = exec("echo %COMPUTERNAME%")
    emit trim(raw)
}
