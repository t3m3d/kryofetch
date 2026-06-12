import "utils_macos.k"

func driveinfo() {
    // Default: Data volume (shown as "/") + externals >1 GB (skips virtual FSes).
    // `disk_mounts = / /Volumes/Foo` overrides with an explicit mount list.
    let mounts = kfconfigget("disk_mounts", "")
    let raw = ""
    if trim(mounts) == "" {
        raw = trim(exec("df -Pm 2>/dev/null | awk 'NR>1 && /^\\/dev\\// && ($6==\"/System/Volumes/Data\" || ($6~/^\\/Volumes\\// && $2+0>1000)) {print $2, $3, ($6==\"/System/Volumes/Data\" ? \"/\" : $6)}' | head -3"))
    } else {
        raw = trim(exec("df -Pm " + mounts + " 2>/dev/null | awk 'NR>1 {print $2, $3, $6}' | head -3"))
    }
    if raw == "" { emit "" }

    let showbars = kfconfigget("bars", "on")
    // config `disk_format = full|fraction|percent`. Default full.
    let dfmt = kfconfigget("disk_format", "full")
    let result = ""
    let i = "0"
    while toInt(i) < 3 {
        let line = nthline(raw, i)
        if line != "" {
            let totalMB = firstpart(line, " ")
            let rest1   = afterpart(line, " ")
            let usedMB  = firstpart(rest1, " ")
            let mount   = afterpart(rest1, " ")
            if toInt(totalMB) > 0 {
                let totalGB = toInt(totalMB) / 1024
                let usedGB  = toInt(usedMB)  / 1024
                let pct     = toInt(usedMB) * 100 / toInt(totalMB) + ""
                let valpart = usedGB + "GB/" + totalGB + "GB " + pct + "%"
                if dfmt == "fraction" { valpart = usedGB + "GB/" + totalGB + "GB" }
                if dfmt == "percent"  { valpart = pct + "%" }
                let entry   = rambar(usedMB, totalMB) + "  " + mount + " " + valpart
                if showbars == "off" { entry = mount + " " + valpart }
                if result != "" { result = result + "\n" }
                result = result + entry
            }
        }
        i = toInt(i) + 1 + ""
    }
    emit result
}
