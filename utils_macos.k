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

func colorpalette() {
    let E   = fromCharCode(27)
    let RST = E + "[0m"
    let pw  = toInt(kfconfigget("palette_width", "3"))
    if pw < 1 { pw = 1 }
    let blk = ""
    let bi  = "0"
    while toInt(bi) < pw { blk = blk + " "  bi = toInt(bi) + 1 + "" }
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

// palette as a row of little Apple logos (), one per ANSI color
func applepalette() {
    let E   = fromCharCode(27)
    let RST = E + "[0m"
    // U+F8FF (Apple logo) as raw UTF-8 bytes — fromCharCode on a single >127
    // codepoint mojibakes, so emit the 3 bytes EF A3 BF directly.
    let AP  = fromCharCode(239) + fromCharCode(163) + fromCharCode(191)
    let pw  = toInt(kfconfigget("palette_width", "3"))
    if pw < 1 { pw = 1 }
    let gap = ""
    let gi  = "0"
    while toInt(gi) < pw { gap = gap + " "  gi = toInt(gi) + 1 + "" }
    let r1  = ""
    let r2  = ""
    let i   = "0"
    while toInt(i) < 8 {
        let c1 = toInt(i) + 30 + ""
        let c2 = toInt(i) + 90 + ""
        r1 = r1 + E + "[" + c1 + ";1m" + AP + gap
        r2 = r2 + E + "[" + c2 + "m" + AP + gap
        i = toInt(i) + 1 + ""
    }
    kp("  " + r1 + RST)
    kp("  " + r2 + RST)
}

// Like nthline but preserves leading whitespace (needed for continuation lines)
func infoline(s, lineIdx) {
    let target = toInt(lineIdx)
    let cur = "0"
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(s, toInt(start), len(s))
        let nlPos = indexOf(rest, "\n")
        if nlPos < 0 {
            if toInt(cur) == target { emit rest }
            done = "1"
        } else {
            if toInt(cur) == target {
                emit substring(rest, 0, toInt(nlPos))
            }
            start = toInt(start) + toInt(nlPos) + 1 + ""
            cur = toInt(cur) + 1 + ""
        }
    }
    emit ""
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

// count installed packages for one manager keyword
func pkgcount(m) {
    if m == "brew"  { emit trim(exec("brew list --formula 2>/dev/null | wc -l | tr -d ' '")) }
    if m == "cask"  { emit trim(exec("brew list --cask 2>/dev/null | wc -l | tr -d ' '")) }
    if m == "port"  { emit trim(exec("port installed 2>/dev/null | grep -c active")) }
    if m == "ports" { emit trim(exec("port installed 2>/dev/null | grep -c active")) }
    if m == "npm"   { emit trim(exec("npm ls -g --depth=0 2>/dev/null | grep -c '@'")) }
    if m == "pip"   { emit trim(exec("pip list 2>/dev/null | tail -n +3 | wc -l | tr -d ' '")) }
    if m == "pip3"  { emit trim(exec("pip3 list 2>/dev/null | tail -n +3 | wc -l | tr -d ' '")) }
    if m == "cargo" { emit trim(exec("ls $HOME/.cargo/bin 2>/dev/null | wc -l | tr -d ' '")) }
    if m == "gem"   { emit trim(exec("gem list 2>/dev/null | wc -l | tr -d ' '")) }
    emit "0"
}

func kfpkgs() {
    // config `pkg_managers = brew ports ...` selects which to count (default
    // brew + ports). Supported: brew cask port npm pip pip3 cargo gem.
    let mgrs = kfconfigget("pkg_managers", "brew ports")
    let result = ""
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(mgrs, toInt(start), len(mgrs))
        let sp = indexOf(rest, " ")
        let tok = ""
        if sp < 0 { tok = rest  done = "1" }
        else {
            tok = substring(rest, 0, toInt(sp))
            start = toInt(start) + toInt(sp) + 1 + ""
        }
        let t = trim(tok)
        if t != "" {
            let c = pkgcount(t)
            if toInt(c) > 0 {
                if result != "" { result = result + ", " }
                result = result + c + " (" + t + ")"
            }
        }
    }
    if result == "" { emit "none" }
    emit result
}
