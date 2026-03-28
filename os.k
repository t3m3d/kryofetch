// os.k — OS version and uptime

func get_os_version() {
    let buildRaw = exec("wmic os get BuildNumber /value")
    let eq1 = indexOf(buildRaw, "=")
    let build = "0"
    if eq1 >= 0 {
        build = trim(substring(buildRaw, toInt(eq1) + 1, len(buildRaw)))
    }

    let b = toInt(build)
    let version = "Windows"
    if      b >= 26100 { version = "Windows 11" }
    else if b >= 22621 { version = "Windows 11" }
    else if b >= 22000 { version = "Windows 11" }
    else if b >= 19041 { version = "Windows 10" }
    else               { version = "Windows (legacy)" }

    emit version + " (build " + build + ")"
}

func get_uptime() {
    let ms = kf_get_tick_ms()
    let totalSec = toInt(ms) / 1000
    let minutes  = totalSec / 60
    let hours    = minutes / 60
    let days     = hours / 24

    let h = hours - (days * 24)
    let m = minutes - (hours * 60)

    if days > 0 {
        emit days + " days, " + h + " hrs, " + m + " mins"
    } else if hours > 0 {
        emit h + " hrs, " + m + " mins"
    } else {
        emit m + " mins"
    }
}
