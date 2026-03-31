func ansi(s) {
    let esc = fromCharCode(27)
    emit replace(s, "\\x1b", esc)
}

func vislen(s) {
    let total = len(s)
    let vis = "0"
    let i = "0"
    let esc = fromCharCode(27)
    while toInt(i) < toInt(total) {
        let ch = substring(s, toInt(i), toInt(i) + 1)
        if ch == esc {
            i = toInt(i) + 1 + ""
            while toInt(i) < toInt(total) {
                let c2 = substring(s, toInt(i), toInt(i) + 1)
                i = toInt(i) + 1 + ""
                if c2 == "m" { break }
            }
        } else {
            vis = toInt(vis) + 1 + ""
            i = toInt(i) + 1 + ""
        }
    }
    emit vis
}

func padansi(s, w) {
    let vl = toInt(vislen(s))
    let pad = toInt(w) - vl
    let result = s
    let i = "0"
    while toInt(i) < pad {
        result = result + " "
        i = toInt(i) + 1 + ""
    }
    emit result
}

func firstpart(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit s }
    emit substring(s, 0, toInt(pos))
}

func afterpart(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit "" }
    emit substring(s, toInt(pos) + 1, len(s))
}

func linecount(s) {
    if s == "" { emit "0" }
    let t = trim(s)
    if t == "" { emit "0" }
    let n = "1"
    let i = "0"
    while toInt(i) < len(t) {
        let ch = substring(t, toInt(i), toInt(i) + 1)
        if ch == "\n" { n = toInt(n) + 1 + "" }
        i = toInt(i) + 1 + ""
    }
    emit n
}

func nthline(s, lineIdx) {
    let target = toInt(lineIdx)
    let cur = "0"
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(s, toInt(start), len(s))
        let nlPos = indexOf(rest, "\n")
        if nlPos < 0 {
            if toInt(cur) == target { emit trim(rest) }
            done = "1"
        } else {
            if toInt(cur) == target {
                emit trim(substring(rest, 0, toInt(nlPos)))
            }
            start = toInt(start) + toInt(nlPos) + 1 + ""
            cur = toInt(cur) + 1 + ""
        }
    }
    emit ""
}

// rambar: pure Krypton UTF-8 block char bar
func rambar(usedMB, totalMB) {
    let used  = toInt(usedMB)
    let total = toInt(totalMB)
    if total == 0 { emit "[                    ]" }
    let pct    = used * 100 / total
    let filled = pct * 20 / 100
    let empty  = 20 - filled
    let bar    = "["
    let i = 0
    while i < filled { bar = bar + "▒"  i += 1 }
    i = 0
    while i < empty  { bar = bar + "█"  i += 1 }
    emit bar + "]"
}

// colorpalette: prints two rows of 8 ANSI color blocks (normal + bright)
func colorpalette() {
    let E   = fromCharCode(27)
    let RST = E + "[0m"
    let blk = "   "
    let r1  = ""
    let r2  = ""
    let i   = "0"
    while toInt(i) < 8 {
        let c1 = toInt(i) + 40 + ""
        let c2 = toInt(i) + 100 + ""
        r1 = r1 + E + "[" + c1 + "m" + blk
        r2 = r2 + E + "[" + c2 + "m" + blk
        i = toInt(i) + 1 + ""
    }
    kp("  " + r1 + RST)
    kp("  " + r2 + RST)
}

func idxfrom(s, sub, start) {
    let slen = len(s)
    let sublen = len(sub)
    let i = toInt(start)
    while toInt(i) <= toInt(slen) - toInt(sublen) {
        let piece = substring(s, toInt(i), toInt(i) + toInt(sublen))
        if piece == sub { emit i + "" }
        i = toInt(i) + 1 + ""
    }
    emit "-1"
}

func kfshell() {
    // Walk process tree looking for a known shell (up to 3 levels)
    let raw = trim(exec("powershell -NoProfile -Command \"$id=$PID; $shell=''; for($i=0;$i-lt3;$i++){$id=(Get-WmiObject Win32_Process -Filter ('ProcessId='+$id)).ParentProcessId; $n=(Get-Process -Id $id -EA SilentlyContinue).Name; if($n -match 'pwsh|powershell|bash|zsh|fish|nu|cmd'){$shell=$n;break}}; $shell\""))
    let name = trim(raw)
    if name == "pwsh"       { emit "PowerShell" }
    if name == "powershell" { emit "Windows PowerShell" }
    if name == "cmd"        { emit "cmd" }
    if name == "bash"       { emit "bash" }
    if name == "zsh"        { emit "zsh" }
    if name == "fish"       { emit "fish" }
    if name == "nu"         { emit "nushell" }
    if name != ""           { emit name }
    emit ""
}

func kfpkgs() {
    // Count winget packages via registry
    let winget = trim(exec("powershell -NoProfile -Command \"(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue).Count\""))
    // Count scoop apps
    let scoopPath = environ("USERPROFILE") + "\\scoop\\apps"
    let scoop = trim(exec("powershell -NoProfile -Command \"if(Test-Path '" + scoopPath + "'){((Get-ChildItem '" + scoopPath + "' -Directory).Count - 1)}else{0}\""))
    // Count choco packages
    let chocoBase = environ("ChocolateyInstall")
    let choco = ""
    if chocoBase != "" {
        choco = trim(exec("powershell -NoProfile -Command \"if(Test-Path '" + chocoBase + "\\lib'){(Get-ChildItem '" + chocoBase + "\\lib' -Directory).Count}else{0}\""))
    }
    let result = ""
    if toInt(winget) > 0 { result = winget + " (winget)" }
    if toInt(scoop) > 0 {
        if result != "" { result = result + ", " }
        result = result + scoop + " (scoop)"
    }
    if toInt(choco) > 0 {
        if result != "" { result = result + ", " }
        result = result + choco + " (choco)"
    }
    emit result
}

