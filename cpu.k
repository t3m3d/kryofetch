// cpu.k — safe version using WMIC

func get_cpu_name() {
    let name = exec("wmic cpu get name /value")
    // WMIC output looks like: "Name=Intel(R) Core(TM) i7-8700K"
    let eq = indexOf(name, "=")
    if eq < 0 { emit "Unknown CPU" }
    emit substring(name, eq + 1, len(name))
}

func get_cpu_cores() {
    let cores = exec("wmic cpu get NumberOfCores /value")
    let eq = indexOf(cores, "=")
    if eq < 0 { emit "0" }
    emit substring(cores, eq + 1, len(cores))
}

func get_cpu_threads() {
    let thr = exec("wmic cpu get NumberOfLogicalProcessors /value")
    let eq = indexOf(thr, "=")
    if eq < 0 { emit "0" }
    emit substring(thr, eq + 1, len(thr))
}