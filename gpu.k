// gpu.k — safe version using WMIC, no NVAPI/SetupAPI/registry

// -----------------------------
// NVAPI stubs
// -----------------------------
func gpu_nvapi_init() {
    emit "0"
}

func gpu_nvapi_vram(idx) {
    emit "0,0"
}

// -----------------------------
// GPU list
// -----------------------------
func gpu_list() {
    let raw = exec("wmic path win32_videocontroller get name /value")

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
// VRAM via WMIC AdapterRAM
// -----------------------------
func gpu_vram(idx) {
    let raw = exec("wmic path win32_videocontroller get AdapterRAM /value")

    let start = 0
    let count = 0
    let mem = "0"

    while true {
        let pos = indexOfFrom(raw, "AdapterRAM=", start)
        if pos < 0 { break }

        let end = indexOfFrom(raw, "\n", pos)
        if end < 0 { end = len(raw) }

        let line = substring(raw, pos, end)
        let eq = indexOf(line, "=")
        if eq >= 0 {
            let val = substring(line, eq + 1, len(line))
            if count == idx {
                mem = val
                break
            }
            count = count + 1
        }

        start = end + 1
    }

    emit mem
}