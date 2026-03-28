// utils.k — helper functions for kryofetch

// ansi(s) — replace literal \x1b sequences with real ESC byte
func ansi(s) {
    let esc = fromCharCode(27)
    emit replace(s, "\\x1b", esc)
}

// visible_len(s) — character count ignoring ANSI escape sequences
func visible_len(s) {
    let total = len(s)
    let visible = "0"
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
            visible = toInt(visible) + 1 + ""
            i = toInt(i) + 1 + ""
        }
    }
    emit visible
}

// pad_ansi(s, w) — pad string to visual width w, returns padded string
func pad_ansi(s, w) {
    let vlen = toInt(visible_len(s))
    let pad = toInt(w) - vlen
    let result = s
    let i = "0"
    while toInt(i) < pad {
        result = result + " "
        i = toInt(i) + 1 + ""
    }
    emit result
}

// split_first(s, delim) — part before first occurrence of delim
func split_first(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit s }
    emit substring(s, 0, toInt(pos))
}

// split_second(s, delim) — part after first occurrence of delim
func split_second(s, delim) {
    let pos = indexOf(s, delim)
    if pos < 0 { emit "" }
    emit substring(s, toInt(pos) + 1, len(s))
}

// count_lines(s) — number of lines (newline-separated)
func count_lines(s) {
    if s == "" { emit "0" }
    let t = trim(s)
    if t == "" { emit "0" }
    let count = "1"
    let i = "0"
    while toInt(i) < len(t) {
        let ch = substring(t, toInt(i), toInt(i) + 1)
        if ch == "\n" { count = toInt(count) + 1 + "" }
        i = toInt(i) + 1 + ""
    }
    emit count
}

// line_at(s, lineIdx) — get 0-based line from newline-separated string
func line_at(s, lineIdx) {
    let target = toInt(lineIdx)
    let cur = "0"
    let start = "0"
    let done = "0"
    while done == "0" {
        let remaining = substring(s, toInt(start), len(s))
        let nlPos = indexOf(remaining, "\n")
        if nlPos < 0 {
            if toInt(cur) == target {
                emit trim(remaining)
            }
            done = "1"
        } else {
            if toInt(cur) == target {
                emit trim(substring(remaining, 0, toInt(nlPos)))
            }
            start = toInt(start) + toInt(nlPos) + 1 + ""
            cur = toInt(cur) + 1 + ""
        }
    }
    emit ""
}

// indexOfFrom(s, sub, start) — indexOf starting from position start
func indexOfFrom(s, sub, start) {
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

// make_vram_bar(usedGB, totalGB) — text bar showing VRAM usage
func make_vram_bar(usedGB, totalGB) {
    let total = toInt(totalGB)
    if total <= 0 { emit "[--------------------] 0/0 GB" }
    let used = toInt(usedGB)
    let pct = used * 100 / total
    let blocks = pct / 5
    let bar = ""
    let i = "0"
    while toInt(i) < blocks {
        bar = bar + "#"
        i = toInt(i) + 1 + ""
    }
    while toInt(i) < 20 {
        bar = bar + "-"
        i = toInt(i) + 1 + ""
    }
    emit "[" + bar + "] " + usedGB + "/" + totalGB + " GB"
}
