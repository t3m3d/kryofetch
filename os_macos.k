import "utils_macos.k"

func osver() {
    let v = exec("sw_vers -productVersion 2>/dev/null")
    if v == "" { emit "macOS" }
    emit "macOS " + v
}

func uptime() {
    let out = exec("uptime | sed 's/.*up //' | sed 's/, *[0-9]* *user.*//'")
    if out == "" { emit "unknown" }
    emit trim(out)
}

func kfresolution() {
    let res = exec("system_profiler SPDisplaysDataType 2>/dev/null | grep 'Resolution:' | head -1 | sed 's/.*Resolution: //' | sed 's/ @ .*//'")
    if res == "" { emit "unknown" }
    emit trim(res)
}

func kfterminal() {
    let tp = environ("TERM_PROGRAM")
    if tp != "" { emit tp }
    emit ""
}

func kftheme() {
    let style = exec("defaults read -g AppleInterfaceStyle 2>/dev/null")
    if style == "Dark" { emit "Dark" }
    emit "Light"
}

func kfbattery() {
    let pct    = exec("pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1")
    if pct == "" { emit "" }
    let status = exec("pmset -g batt 2>/dev/null | grep -Eo '(charging|discharging|charged)' | head -1")
    if status == "" { emit pct }
    emit pct + " (" + status + ")"
}

func sysuser() {
    let u = environ("USER")
    if u != "" { emit u }
    emit exec("whoami")
}

func syshost() {
    let h = exec("hostname -s 2>/dev/null")
    if h == "" { emit "localhost" }
    emit h
}

func sysarch() {
    let a = exec("uname -m")
    if a == "arm64"  { emit "arm64" }
    if a == "x86_64" { emit "x86_64" }
    if a == "" { emit "unknown" }
    emit a
}
