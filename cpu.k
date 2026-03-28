func cpu_name() {
    let raw = exec("wmic cpu get name /value")
    let eq = indexOf(raw, "=")
    if eq < 0 { emit "Unknown CPU" }
    emit substring(raw, eq + 1, len(raw))
}

func cpu_cores() {
    let raw = exec("wmic cpu get NumberOfCores /value")
    let eq = indexOf(raw, "=")
    if eq < 0 { emit "0" }
    emit substring(raw, eq + 1, len(raw))
}

func cpu_threads() {
    let raw = exec("wmic cpu get NumberOfLogicalProcessors /value")
    let eq = indexOf(raw, "=")
    if eq < 0 { emit "0" }
    emit substring(raw, eq + 1, len(raw))
}