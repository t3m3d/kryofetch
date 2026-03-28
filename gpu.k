// gpu.k — GPU detection via WMIC

func get_gpus() {
    let raw = exec("wmic path win32_videocontroller get name /value")
    let result = ""
    let start = "0"
    let done = "0"
    while done == "0" {
        let pos = indexOfFrom(raw, "Name=", toInt(start))
        if pos < 0 { done = "1" }
        if done == "0" {
            let endpos = indexOfFrom(raw, "\n", toInt(pos))
            if endpos < 0 { endpos = len(raw) + "" }
            let line = substring(raw, toInt(pos), toInt(endpos))
            let eq = indexOf(line, "=")
            if eq >= 0 {
                let name = trim(substring(line, toInt(eq) + 1, len(line)))
                if name != "" {
                    if result == "" {
                        result = name
                    } else {
                        result = result + "\n" + name
                    }
                }
            }
            start = toInt(endpos) + 1 + ""
        }
    }
    if result == "" { emit "Unknown GPU" }
    emit result
}

func get_vram_usage_nvapi(idx) {
    emit "0,0"
}

func get_vram_registry(idx) {
    emit "0"
}
