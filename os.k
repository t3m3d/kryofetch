func osver() {
    let raw   = exec("powershell -NoProfile -Command \"(Get-WmiObject Win32_OperatingSystem).BuildNumber\"")
    let build = trim(raw)
    if build == "" { build = "0" }
    let b = toInt(build)
    let v = "Windows"
    if      b >= 26100 { v = "Windows 11" }
    else if b >= 22621 { v = "Windows 11" }
    else if b >= 22000 { v = "Windows 11" }
    else if b >= 19041 { v = "Windows 10" }
    else               { v = "Windows (legacy)" }

    let ed = trim(kfosedition())
    if ed == "Professional"            { ed = "Pro" }
    if ed == "Core"                    { ed = "Home" }
    if ed == "ProfessionalWorkstation" { ed = "Pro Workstation" }
    if ed == "IoTEnterprise"           { ed = "IoT Enterprise" }
    if ed == "ProfessionalN"           { ed = "Pro N" }
    if ed == "CoreN"                   { ed = "Home N" }
    if ed == "CoreSingleLanguage"      { ed = "Home SL" }

    if ed != "" {
        emit v + " " + ed + " (build " + build + ")"
    }
    emit v + " (build " + build + ")"
}

func uptime() {
    let tsec = toInt(kfuptimesec())
    let mins  = tsec / 60
    let hrs   = mins / 60
    let days  = hrs / 24
    let h = hrs - (days * 24)
    let m = mins - (hrs * 60)
    if days > 0 {
        emit days + " days, " + h + " hrs, " + m + " min"
    } else if hrs > 0 {
        emit h + " hrs, " + m + " min"
    } else {
        emit m + " min"
    }
}
