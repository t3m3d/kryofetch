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

    // Edition from registry via powershell
    let ed = trim(exec("powershell -NoProfile -Command \"(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').EditionID\""))
    if ed == "Professional"            { ed = "Pro" }
    if ed == "Core"                    { ed = "Home" }
    if ed == "ProfessionalWorkstation" { ed = "Pro Workstation" }
    if ed == "IoTEnterprise"           { ed = "IoT Enterprise" }
    if ed == "ProfessionalN"           { ed = "Pro N" }
    if ed == "CoreN"                   { ed = "Home N" }
    if ed == "CoreSingleLanguage"      { ed = "Home SL" }

    if ed != "" { emit v + " " + ed + " (build " + build + ")" }
    emit v + " (build " + build + ")"
}

func uptime() {
    let tsec = toInt(kfuptimesec())
    let mins  = tsec / 60
    let hrs   = mins / 60
    let days  = hrs / 24
    let h = hrs - (days * 24)
    let m = mins - (hrs * 60)
    if days > 0 { emit days + " days, " + h + " hrs, " + m + " min" }
    else if hrs > 0 { emit h + " hrs, " + m + " min" }
    else { emit m + " min" }
}

func kfresolution() {
    let raw = trim(exec("powershell -NoProfile -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::PrimaryScreen.Bounds | Select-Object -ExpandProperty Width; [System.Windows.Forms.Screen]::PrimaryScreen.Bounds | Select-Object -ExpandProperty Height\""))
    // output is two lines: width\nheight
    let w = nthline(raw, "0")
    let h = nthline(raw, "1")
    if w == "" { emit "unknown" }
    emit w + "x" + h
}

func kfterminal() {
    let wt = environ("WT_SESSION")
    if wt != "" { emit "Windows Terminal" }
    let ce = environ("ConEmuPID")
    if ce != "" { emit "ConEmu" }
    let al = environ("ALACRITTY_LOG")
    if al != "" { emit "Alacritty" }
    let tp = environ("TERM_PROGRAM")
    if tp != "" { emit tp }
    emit ""
}

func kftheme() {
    let raw = trim(exec("powershell -NoProfile -Command \"$p='HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize'; $l=(Get-ItemProperty $p).AppsUseLightTheme; $a=(Get-ItemProperty $p).AccentColor; $r=$a -band 0xFF; $g=($a -shr 8) -band 0xFF; $b=($a -shr 16) -band 0xFF; if($l){'Light'}else{'Dark'}; '#{0:X2}{1:X2}{2:X2}' -f $r,$g,$b\""))
    let mode  = nthline(raw, "0")
    let color = nthline(raw, "1")
    if mode == "" { emit "" }
    if color != "" { emit mode + " (" + color + ")" }
    emit mode
}

func kfbattery() {
    let raw = trim(exec("powershell -NoProfile -Command \"$b=Get-WmiObject Win32_Battery; if($b){$b.EstimatedChargeRemaining}\""))
    if raw == "" { emit "" }
    let status = trim(exec("powershell -NoProfile -Command \"$b=Get-WmiObject Win32_Battery; if($b){if($b.BatteryStatus -eq 2){'charging'}else{'discharging'}}\""))
    if status != "" { emit raw + "% (" + status + ")" }
    emit raw + "%"
}
