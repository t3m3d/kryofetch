// os.k — safe version using WMIC + GetTickCount64

func get_os_version() {
    // Get build number
    let buildRaw = exec("wmic os get BuildNumber /value")
    let eq1 = indexOf(buildRaw, "=")
    let build = "0"
    if eq1 >= 0 {
        build = substring(buildRaw, eq1 + 1, len(buildRaw))
    }

    // Get edition
    let editionRaw = exec("wmic os get OperatingSystemSKU /value")
    let eq2 = indexOf(editionRaw, "=")
    let edition = "Windows"
    if eq2 >= 0 {
        edition = substring(editionRaw, eq2 + 1, len(editionRaw))
    }

    // Map build number to Windows version
    let b = toInt(build)
    let version = "Windows"

    if      b >= 26100 { version = "Windows 11" }
    else if b >= 22621 { version = "Windows 11" }
    else if b >= 22000 { version = "Windows 11" }
    else if b >= 19041 { version = "Windows 10" }
    else               { version = "Windows (legacy)" }

    emit version + " " + edition + " (build " + build + ")"
}

func get_uptime() {
    let ms = GetTickCount64()
    let totalSec = ms / 1000
    let minutes  = totalSec / 60
    let hours    = minutes / 60
    let days     = hours / 24

    let h = hours % 24
    let m = minutes % 60

    if days > 0 {
        emit days + " days, " + h + " hrs, " + m + " mins"
    } else if hours > 0 {
        emit h + " hrs, " + m + " mins"
    } else {
        emit m + " mins"
    }
}