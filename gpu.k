// gpu.k — safe version using WMIC, no NVAPI/SetupAPI/registry

// -----------------------------
// NVAPI stubs
// -----------------------------
func initNvapi() {
    emit "0"
}

// getVramUsageNvapi(gpuIndex) -> "usedBytes,totalBytes"
func getVramUsageNvapi(gpuIndex) {
    emit "0,0"
}

// -----------------------------
// get_gpus() -> "GPU0\nGPU1"
// -----------------------------
func getGpus() {
    // Use WMIC to get GPU names
    let raw = exec("wmic path win32_videocontroller get name /value")
    // Example:
    // Name=NVIDIA GeForce RTX 4070
    // Name=Intel(R) UHD Graphics 770

    let result = ""
    let start = 0

    while true {
        let idx = indexOfFrom(raw, "Name=", start)
        if idx < 0 { break }

        let end = indexOfFrom(raw, "\n", idx)
        if end < 0 { end = len(raw) }

        let line = substring(raw, idx, end)
        let eq = indexOf(line, "=")
        if eq >= 0 {
            let name = substring(line, eq + 1, len(line))
            if result == "" {
                result = name
            } else {
                result = result + "\n" + name
            }
        }

        start = end + 1
    }

    emit result
}

// -----------------------------
// getVramRegistry(gpuIndex) -> "bytes"
// (we'll fake this via WMIC AdapterRAM)
// -----------------------------
func getVramRegistry(gpuIndex) {
    let raw = exec("wmic path win32_videocontroller get AdapterRAM /value")
    // Example:
    // AdapterRAM=4293918720
    // AdapterRAM=1073741824

    let start = 0
    let idxCount = 0
    let mem = "0"

    while true {
        let idx = indexOfFrom(raw, "AdapterRAM=", start)
        if idx < 0 { break }

        let end = indexOfFrom(raw, "\n", idx)
        if end < 0 { end = len(raw) }

        let line = substring(raw, idx, end)
        let eq = indexOf(line, "=")
        if eq >= 0 {
            let val = substring(line, eq + 1, len(line))
            if idxCount == gpuIndex {
                mem = val
                break
            }
            idxCount = idxCount + 1
        }

        start = end + 1
    }

    emit mem
}