// kryofetch — Linux (x86-64 / aarch64) edition. Pure Krypton, native backend.
//
// Sibling to run.k (Windows, Win32 API) and run_macos.k (macOS, sysctl/
// system_profiler). The Linux native backend (compiler/linux_x86/elf.k) does
// not implement exec()/environ() (they no-op), and readFile() can't read the
// /proc & /sys virtual files (their st_size is 0). So this edition uses the
// native `readProc(path)` builtin — inline open+read-loop+close syscalls,
// added to elf.k alongside the socket builtins — to slurp /proc, /sys and
// /etc, then parses the text with the standard string builtins.
//
//   kcc.sh -r run_linux.k          compile + run
//   kcc.sh -r run_linux.k --watch  re-render every second
//
// Self-contained on purpose: the native backend doesn't link nested module
// imports transitively. Built and verified on ParrotOS / Debian. Any field
// that can't be read is simply omitted.

// ── generic string / render helpers (mirrors utils_macos.k) ──────────────
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
            if toInt(cur) == target { emit substring(rest, 0, toInt(nlPos)) }
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

// ── /proc + /etc parsing helpers ─────────────────────────────────────────
// First line of text `s` whose start matches `key` (whole line returned).
func findLine(s, key) {
    let n = toInt(linecount(s))
    let i = 0
    while i < n {
        let ln = getLine(s, i)
        if startsWith(ln, key) { emit ln }
        i = i + 1
    }
    emit ""
}

// Text after the first ':' in `s`, trimmed (for "key: value" /proc lines).
func afterColon(s) {
    let p = indexOf(s, ":")
    if p < 0 { emit trim(s) }
    emit trim(substring(s, toInt(p) + 1, len(s)))
}

// Count lines beginning with `key`.
func countPrefix(s, key) {
    let n = toInt(linecount(s))
    let i = 0
    let c = 0
    while i < n {
        if startsWith(getLine(s, i), key) { c = c + 1 }
        i = i + 1
    }
    emit c + ""
}

// nth `delim`-separated field of `s` (0-based). Avoids split() (broken native).
func nthField(s, delim, n) {
    let cur = s
    let i = 0
    while i < n {
        cur = afterpart(cur, delim)
        i = i + 1
    }
    emit firstpart(cur, delim)
}

// ── system info collectors (Linux, via readProc / readFile) ──────────────
func osver() {
    let r = readFile("/etc/os-release")          // real file: readFile works
    let line = findLine(r, "PRETTY_NAME=")
    if line != "" {
        let v = afterpart(line, "=")
        if startsWith(v, "\"") { v = substring(v, 1, len(v)) }
        if endsWith(v, "\"")   { v = substring(v, 0, len(v) - 1) }
        emit v
    }
    emit "Linux"
}

func syshost() {
    let h = trim(readProc("/proc/sys/kernel/hostname"))
    if h != "" { emit h }
    let h2 = trim(readFile("/etc/hostname"))
    if h2 != "" { emit h2 }
    emit "localhost"
}

func kfkernel() {
    let osr = trim(readProc("/proc/sys/kernel/osrelease"))
    if osr == "" { emit "Linux" }
    emit "Linux " + osr
}

func sysarch() {
    let osr = readProc("/proc/sys/kernel/osrelease")
    if contains(osr, "amd64") { emit "x86_64" }
    if contains(osr, "arm64") { emit "aarch64" }
    if contains(osr, "686")   { emit "x86" }
    emit ""
}

func sysmodel() {
    let m = trim(readProc("/sys/devices/virtual/dmi/id/product_name"))
    if m == "To be filled by O.E.M." { emit "" }
    if m == "System Product Name"    { emit "" }
    emit m
}

func cpubrand() {
    let ci = readProc("/proc/cpuinfo")
    let ln = findLine(ci, "model name")
    if ln != "" { emit afterColon(ln) }
    let hw = findLine(ci, "Hardware")          // some ARM boards
    if hw != "" { emit afterColon(hw) }
    let mp = findLine(ci, "Model")
    if mp != "" { emit afterColon(mp) }
    emit "Unknown CPU"
}

// logical thread count = number of "processor" lines in /proc/cpuinfo.
func cputhreads() {
    let ci = readProc("/proc/cpuinfo")
    let n = countPrefix(ci, "processor")
    if n == "0" { emit "1" }
    emit n
}

// "totalMB,availMB" from /proc/meminfo (values are in kB).
func raminfo() {
    let mi = readProc("/proc/meminfo")
    let tl = findLine(mi, "MemTotal:")
    let al = findLine(mi, "MemAvailable:")
    if tl == "" { emit "0,0" }
    let tkb = toInt(firstpart(afterColon(tl), " "))
    let akb = toInt(firstpart(afterColon(al), " "))
    emit (tkb / 1024) + "," + (akb / 1024)
}

func swapinfo() {
    let mi = readProc("/proc/meminfo")
    let tl = findLine(mi, "SwapTotal:")
    let fl = findLine(mi, "SwapFree:")
    if tl == "" { emit "Unused" }
    let tkb = toInt(firstpart(afterColon(tl), " "))
    let fkb = toInt(firstpart(afterColon(fl), " "))
    if tkb == 0 { emit "Unused" }
    let ukb = tkb - fkb
    emit (ukb / 1024) + " MB used / " + (tkb / 1024) + " MB total"
}

func uptimestr() {
    let raw = trim(readProc("/proc/uptime"))
    if raw == "" { emit "unknown" }
    let secs = toInt(firstpart(firstpart(raw, " "), "."))
    let d = secs / 86400
    let h = (secs - d * 86400) / 3600
    let m = (secs - d * 86400 - h * 3600) / 60
    if d > 0 { emit d + "d " + h + "h " + m + "m" }
    if h > 0 { emit h + "h " + m + "m" }
    emit m + "m"
}

// Username + login shell WITHOUT environ/exec: real uid from /proc/self/status,
// then resolve it against /etc/passwd (a real, readFile-able file).
func _uid() {
    let st = readProc("/proc/self/status")
    let ul = findLine(st, "Uid:")
    if ul == "" { emit "" }
    // "Uid:\t<real>\t<eff>\t..." — take field 1 split on TAB (trim() leaves tabs).
    emit nthField(ul, "\t", 1)
}

func _passwdLine() {
    let uid = _uid()
    if uid == "" { emit "" }
    let pw = readFile("/etc/passwd")
    let n = toInt(linecount(pw))
    let i = 0
    while i < n {
        let ln = getLine(pw, i)
        if nthField(ln, ":", 2) == uid { emit ln }
        i = i + 1
    }
    emit ""
}

func sysuser() {
    let ln = _passwdLine()
    if ln != "" {
        let u = nthField(ln, ":", 0)
        if u != "" { emit u }
    }
    emit "user"
}

func kfshell() {
    let ln = _passwdLine()
    if ln != "" {
        let sh = nthField(ln, ":", 6)
        if sh != "" {
            // basename of the shell path
            let b = sh
            let p = indexOf(b, "/")
            while p >= 0 {
                b = substring(b, toInt(p) + 1, len(b))
                p = indexOf(b, "/")
            }
            emit b
        }
    }
    emit "unknown"
}

// Terminal + desktop environment via environ() (native builtin).
func kfterm() {
    let t = environ("TERM_PROGRAM")
    if t != "" { emit t }
    let t2 = environ("TERM")
    if t2 != "" { emit t2 }
    emit ""
}

func kfde() {
    let d = environ("XDG_CURRENT_DESKTOP")
    if d != "" { emit d }
    let d2 = environ("DESKTOP_SESSION")
    if d2 != "" { emit d2 }
    emit ""
}

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

// distro id from /etc/os-release (ID=), lowercased by spec. BlackArch is
// Arch-based (ID=arch) so it's matched by NAME/PRETTY_NAME instead.
func distroId() {
    let r = readFile("/etc/os-release")
    let pn = findLine(r, "PRETTY_NAME=")
    if indexOf(pn, "BlackArch") >= 0 { emit "blackarch" }
    let nm = findLine(r, "NAME=")
    if indexOf(nm, "BlackArch") >= 0 { emit "blackarch" }
    let idl = findLine(r, "ID=")
    if idl == "" { emit "linux" }
    let v = afterpart(idl, "=")
    if startsWith(v, "\"") { v = substring(v, 1, len(v)) }
    if endsWith(v, "\"")   { v = substring(v, 0, len(v) - 1) }
    emit v
}

// AUTO-GENERATED distro art (from neofetch canonical logos).
func distroArt(id, E) {
    let R = E + "[0m"
    let a = ""
    if id == "arch" {
        a = a + E + "[36;1m" + E + "[36;1m" + "                   -`" + R + "\n"
        a = a + E + "[36;1m" + "                  .o+`" + R + "\n"
        a = a + E + "[36;1m" + "                 `ooo/" + R + "\n"
        a = a + E + "[36;1m" + "                `+oooo:" + R + "\n"
        a = a + E + "[36;1m" + "               `+oooooo:" + R + "\n"
        a = a + E + "[36;1m" + "               -+oooooo+:" + R + "\n"
        a = a + E + "[36;1m" + "             `/:-:++oooo+:" + R + "\n"
        a = a + E + "[36;1m" + "            `/++++/+++++++:" + R + "\n"
        a = a + E + "[36;1m" + "           `/++++++++++++++:" + R + "\n"
        a = a + E + "[36;1m" + "          `/+++o" + E + "[36;1m" + "oooooooo" + E + "[36;1m" + "oooo/`" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "         " + E + "[36;1m" + "./" + E + "[36;1m" + "ooosssso++osssssso" + E + "[36;1m" + "+`" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "        .oossssso-````/ossssss+`" + R + "\n"
        a = a + E + "[36;1m" + "       -osssssso.      :ssssssso." + R + "\n"
        a = a + E + "[36;1m" + "      :osssssss/        osssso+++." + R + "\n"
        a = a + E + "[36;1m" + "     /ossssssss/        +ssssooo/-" + R + "\n"
        a = a + E + "[36;1m" + "   `/ossssso+/:-        -:/+osssso+-" + R + "\n"
        a = a + E + "[36;1m" + "  `+sso+:-`                 `.-/+oso:" + R + "\n"
        a = a + E + "[36;1m" + " `++:.                           `-/+/" + R + "\n"
        a = a + E + "[36;1m" + " .`                                 `/" + R + "\n"
        emit a
    }
    if id == "blackarch" {
        a = a + E + "[31;1m" + E + "[30;1m" + "                   00" + R + "\n"
        a = a + E + "[30;1m" + "                   11" + R + "\n"
        a = a + E + "[30;1m" + "                  ====" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "                  ." + E + "[30;1m" + "//" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "                 `o" + E + "[30;1m" + "//" + E + "[31;1m" + ":" + R + "\n"
        a = a + E + "[31;1m" + "                `+o" + E + "[30;1m" + "//" + E + "[31;1m" + "o:" + R + "\n"
        a = a + E + "[31;1m" + "               `+oo" + E + "[30;1m" + "//" + E + "[31;1m" + "oo:" + R + "\n"
        a = a + E + "[31;1m" + "               -+oo" + E + "[30;1m" + "//" + E + "[31;1m" + "oo+:" + R + "\n"
        a = a + E + "[31;1m" + "             `/:-:+" + E + "[30;1m" + "//" + E + "[31;1m" + "ooo+:" + R + "\n"
        a = a + E + "[31;1m" + "            `/+++++" + E + "[30;1m" + "//" + E + "[31;1m" + "+++++:" + R + "\n"
        a = a + E + "[31;1m" + "           `/++++++" + E + "[30;1m" + "//" + E + "[31;1m" + "++++++:" + R + "\n"
        a = a + E + "[31;1m" + "          `/+++o" + E + "[31;1m" + "ooo" + E + "[30;1m" + "//" + E + "[31;1m" + "ooo" + E + "[31;1m" + "oooo/`" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "         " + E + "[31;1m" + "./" + E + "[31;1m" + "ooosssso" + E + "[30;1m" + "//" + E + "[31;1m" + "osssssso" + E + "[31;1m" + "+`" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "        .oossssso-`" + E + "[30;1m" + "//" + E + "[31;1m" + "`/ossssss+`" + R + "\n"
        a = a + E + "[31;1m" + "       -osssssso.  " + E + "[30;1m" + "//" + E + "[31;1m" + "  :ssssssso." + R + "\n"
        a = a + E + "[31;1m" + "      :osssssss/   " + E + "[30;1m" + "//" + E + "[31;1m" + "   osssso+++." + R + "\n"
        a = a + E + "[31;1m" + "     /ossssssss/   " + E + "[30;1m" + "//" + E + "[31;1m" + "   +ssssooo/-" + R + "\n"
        a = a + E + "[31;1m" + "   `/ossssso+/:-   " + E + "[30;1m" + "//" + E + "[31;1m" + "   -:/+osssso+-" + R + "\n"
        a = a + E + "[31;1m" + "  `+sso+:-`        " + E + "[30;1m" + "//" + E + "[31;1m" + "       `.-/+oso:" + R + "\n"
        a = a + E + "[31;1m" + " `++:.             " + E + "[30;1m" + "//" + E + "[31;1m" + "            `-/+/" + R + "\n"
        a = a + E + "[31;1m" + " .`                " + E + "[30;1m" + "/" + E + "[31;1m" + "                `/" + R + "\n"
        emit a
    }
    if id == "gentoo" {
        a = a + E + "[35;1m" + E + "[35;1m" + "         -/oyddmdhs+:." + R + "\n"
        a = a + E + "[35;1m" + "     -o" + E + "[37;1m" + "dNMMMMMMMMNNmhy+" + E + "[35;1m" + "-`" + R + "\n"
        a = a + E + "[35;1m" + "   -y" + E + "[37;1m" + "NMMMMMMMMMMMNNNmmdhy" + E + "[35;1m" + "+-" + R + "\n"
        a = a + E + "[35;1m" + " `o" + E + "[37;1m" + "mMMMMMMMMMMMMNmdmmmmddhhy" + E + "[35;1m" + "/`" + R + "\n"
        a = a + E + "[35;1m" + " om" + E + "[37;1m" + "MMMMMMMMMMMN" + E + "[35;1m" + "hhyyyo" + E + "[37;1m" + "hmdddhhhd" + E + "[35;1m" + "o`" + R + "\n"
        a = a + E + "[35;1m" + ".y" + E + "[37;1m" + "dMMMMMMMMMMd" + E + "[35;1m" + "hs++so/s" + E + "[37;1m" + "mdddhhhhdm" + E + "[35;1m" + "+`" + R + "\n"
        a = a + E + "[35;1m" + " oy" + E + "[37;1m" + "hdmNMMMMMMMN" + E + "[35;1m" + "dyooy" + E + "[37;1m" + "dmddddhhhhyhN" + E + "[35;1m" + "d." + R + "\n"
        a = a + E + "[35;1m" + "  :o" + E + "[37;1m" + "yhhdNNMMMMMMMNNNmmdddhhhhhyym" + E + "[35;1m" + "Mh" + R + "\n"
        a = a + E + "[35;1m" + "    .:" + E + "[37;1m" + "+sydNMMMMMNNNmmmdddhhhhhhmM" + E + "[35;1m" + "my" + R + "\n"
        a = a + E + "[35;1m" + "       /m" + E + "[37;1m" + "MMMMMMNNNmmmdddhhhhhmMNh" + E + "[35;1m" + "s:" + R + "\n"
        a = a + E + "[35;1m" + "    `o" + E + "[37;1m" + "NMMMMMMMNNNmmmddddhhdmMNhs" + E + "[35;1m" + "+`" + R + "\n"
        a = a + E + "[35;1m" + "  `s" + E + "[37;1m" + "NMMMMMMMMNNNmmmdddddmNMmhs" + E + "[35;1m" + "/." + R + "\n"
        a = a + E + "[35;1m" + " /N" + E + "[37;1m" + "MMMMMMMMNNNNmmmdddmNMNdso" + E + "[35;1m" + ":`" + R + "\n"
        a = a + E + "[35;1m" + "+M" + E + "[37;1m" + "MMMMMMNNNNNmmmmdmNMNdso" + E + "[35;1m" + "/-" + R + "\n"
        a = a + E + "[35;1m" + "yM" + E + "[37;1m" + "MNNNNNNNmmmmmNNMmhs+/" + E + "[35;1m" + "-`" + R + "\n"
        a = a + E + "[35;1m" + "/h" + E + "[37;1m" + "MMNNNNNNNNMNdhs++/" + E + "[35;1m" + "-`" + R + "\n"
        a = a + E + "[35;1m" + "`/" + E + "[37;1m" + "ohdmmddhys+++/:" + E + "[35;1m" + ".`" + R + "\n"
        a = a + E + "[35;1m" + "  `-//////:--." + R + "\n"
        emit a
    }
    if id == "void" {
        a = a + E + "[32;1m" + E + "[32;1m" + "                __.;=====;.__" + R + "\n"
        a = a + E + "[32;1m" + "            _.=+==++=++=+=+===;." + R + "\n"
        a = a + E + "[32;1m" + "             -=+++=+===+=+=+++++=_" + R + "\n"
        a = a + E + "[32;1m" + "        .     -=:``     `--==+=++==." + R + "\n"
        a = a + E + "[32;1m" + "       _vi,    `            --+=++++:" + R + "\n"
        a = a + E + "[32;1m" + "      .uvnvi.       _._       -==+==+." + R + "\n"
        a = a + E + "[32;1m" + "     .vvnvnI`    .;==|==;.     :|=||=|." + R + "\n"
        a = a + E + "[32;1m" + E + "[38;5;8m" + "+QmQQm" + E + "[32;1m" + "pvvnv; " + E + "[38;5;8m" + "_yYsyQQWUUQQQm #QmQ#" + E + "[32;1m" + ":" + E + "[38;5;8m" + "QQQWUV$QQm." + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + " -QQWQW" + E + "[32;1m" + "pvvo" + E + "[38;5;8m" + "wZ?.wQQQE" + E + "[32;1m" + "==<" + E + "[38;5;8m" + "QWWQ/QWQW.QQWW" + E + "[32;1m" + "(: " + E + "[38;5;8m" + "jQWQE" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "  -$QQQQmmU'  jQQQ@" + E + "[32;1m" + "+=<" + E + "[38;5;8m" + "QWQQ)mQQQ.mQQQC" + E + "[32;1m" + "+;" + E + "[38;5;8m" + "jWQQ@'" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "   -$WQ8Y" + E + "[32;1m" + "nI:   " + E + "[38;5;8m" + "QWQQwgQQWV" + E + "[32;1m" + "`" + E + "[38;5;8m" + "mWQQ.jQWQQgyyWW@!" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[32;1m" + "     -1vvnvv.     `~+++`        ++|+++" + R + "\n"
        a = a + E + "[32;1m" + "      +vnvnnv,                 `-|===" + R + "\n"
        a = a + E + "[32;1m" + "       +vnvnvns.           .      :=-" + R + "\n"
        a = a + E + "[32;1m" + "        -Invnvvnsi..___..=sv=.     `" + R + "\n"
        a = a + E + "[32;1m" + "          +Invnvnvnnnnnnnnvvnn;." + R + "\n"
        a = a + E + "[32;1m" + "            ~|Invnvnvvnvvvnnv}+`" + R + "\n"
        a = a + E + "[32;1m" + "               -~|{*l}*|~" + R + "\n"
        emit a
    }
    if id == "parrot" {
        a = a + E + "[36;1m" + E + "[36;1m" + "  `:oho/-`" + R + "\n"
        a = a + E + "[36;1m" + "`mMMMMMMMMMMMNmmdhy-" + R + "\n"
        a = a + E + "[36;1m" + " dMMMMMMMMMMMMMMMMMMs`" + R + "\n"
        a = a + E + "[36;1m" + " +MMsohNMMMMMMMMMMMMMm/" + R + "\n"
        a = a + E + "[36;1m" + " .My   .+dMMMMMMMMMMMMMh." + R + "\n"
        a = a + E + "[36;1m" + "  +       :NMMMMMMMMMMMMNo" + R + "\n"
        a = a + E + "[36;1m" + "           `yMMMMMMMMMMMMMm:" + R + "\n"
        a = a + E + "[36;1m" + "             /NMMMMMMMMMMMMMy`" + R + "\n"
        a = a + E + "[36;1m" + "              .hMMMMMMMMMMMMMN+" + R + "\n"
        a = a + E + "[36;1m" + "                  ``-NMMMMMMMMMd-" + R + "\n"
        a = a + E + "[36;1m" + "                     /MMMMMMMMMMMs`" + R + "\n"
        a = a + E + "[36;1m" + "                      mMMMMMMMsyNMN/" + R + "\n"
        a = a + E + "[36;1m" + "                      +MMMMMMMo  :sNh." + R + "\n"
        a = a + E + "[36;1m" + "                      `NMMMMMMm     -o/" + R + "\n"
        a = a + E + "[36;1m" + "                       oMMMMMMM." + R + "\n"
        a = a + E + "[36;1m" + "                       `NMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "                        +MMd/NMh" + R + "\n"
        a = a + E + "[36;1m" + "                         mMm -mN`" + R + "\n"
        a = a + E + "[36;1m" + "                         /MM  `h:" + R + "\n"
        a = a + E + "[36;1m" + "                          dM`   ." + R + "\n"
        a = a + E + "[36;1m" + "                          :M-" + R + "\n"
        a = a + E + "[36;1m" + "                           d:" + R + "\n"
        a = a + E + "[36;1m" + "                           -+" + R + "\n"
        a = a + E + "[36;1m" + "                            -" + R + "\n"
        emit a
    }
    if id == "exherbo" {
        a = a + E + "[34;1m" + E + "[37;1m" + " ," + R + "\n"
        a = a + E + "[37;1m" + "OXo." + R + "\n"
        a = a + E + "[37;1m" + "NXdX0:    .cok0KXNNXXK0ko:." + R + "\n"
        a = a + E + "[37;1m" + "KX  '0XdKMMK;.xMMMk, .0MMMMMXx;  ..." + R + "\n"
        a = a + E + "[37;1m" + "'NO..xWkMMx   kMMM    cMMMMMX,NMWOxOXd." + R + "\n"
        a = a + E + "[37;1m" + "  cNMk  NK    .oXM.   OMMMMO. 0MMNo  kW." + R + "\n"
        a = a + E + "[37;1m" + "  lMc   o:       .,   .oKNk;   ;NMMWlxW'" + R + "\n"
        a = a + E + "[37;1m" + " ;Mc    ..   .,,'    .0M" + E + "[34;1m" + "g;" + E + "[37;1m" + "WMN'dWMMMMMMO" + R + "\n"
        a = a + E + "[37;1m" + " XX        ,WMMMMW.  cM" + E + "[34;1m" + "cfli" + E + "[37;1m" + "WMKlo.   .kMk" + R + "\n"
        a = a + E + "[37;1m" + ".Mo        .WM" + E + "[34;1m" + "GD" + E + "[37;1m" + "MW.   XM" + E + "[34;1m" + "WO0" + E + "[37;1m" + "MMk        oMl" + R + "\n"
        a = a + E + "[37;1m" + ",M:         ,XMMWx::,''oOK0x;          NM." + R + "\n"
        a = a + E + "[37;1m" + "'Ml      ,kNKOxxxxxkkO0XXKOd:.         oMk" + R + "\n"
        a = a + E + "[37;1m" + " NK    .0Nxc" + E + "[31;1m" + ":::::::::::::::" + E + "[37;1m" + "fkKNk,      .MW" + R + "\n"
        a = a + E + "[37;1m" + " ,Mo  .NXc" + E + "[31;1m" + "::" + E + "[37;1m" + "qXWXb" + E + "[31;1m" + "::::::::::" + E + "[37;1m" + "oo" + E + "[31;1m" + "::" + E + "[37;1m" + "lNK.    .MW" + R + "\n"
        a = a + E + "[37;1m" + "  ;Wo oMd" + E + "[31;1m" + ":::" + E + "[37;1m" + "oNMNP" + E + "[31;1m" + "::::::::" + E + "[37;1m" + "oWMMMx" + E + "[31;1m" + ":" + E + "[37;1m" + "c0M;   lMO" + R + "\n"
        a = a + E + "[37;1m" + "   'NO;W0c" + E + "[31;1m" + ":::::::::::::::" + E + "[37;1m" + "dMMMMO" + E + "[31;1m" + "::" + E + "[37;1m" + "lMk  .WM'" + R + "\n"
        a = a + E + "[37;1m" + "     xWONXdc" + E + "[31;1m" + "::::::::::::::" + E + "[37;1m" + "oOOo" + E + "[31;1m" + "::" + E + "[37;1m" + "lXN. ,WMd" + R + "\n"
        a = a + E + "[37;1m" + "      'KWWNXXK0Okxxo," + E + "[31;1m" + ":::::::" + E + "[37;1m" + ",lkKNo  xMMO" + R + "\n"
        a = a + E + "[37;1m" + "        :XMNxl,';:lodxkOO000Oxc. .oWMMo" + R + "\n"
        a = a + E + "[37;1m" + "          'dXMMXkl;,.        .,o0MMNo'" + R + "\n"
        a = a + E + "[37;1m" + "             ':d0XWMMMMWNNNNMMMNOl'" + R + "\n"
        a = a + E + "[37;1m" + "                   ':okKXWNKkl'" + R + "\n"
        emit a
    }
    if id == "fedora" {
        a = a + E + "[38;5;12m" + E + "[38;5;12m" + "             .',;::::;,'." + R + "\n"
        a = a + E + "[38;5;12m" + "         .';:cccccccccccc:;,." + R + "\n"
        a = a + E + "[38;5;12m" + "      .;cccccccccccccccccccccc;." + R + "\n"
        a = a + E + "[38;5;12m" + "    .:cccccccccccccccccccccccccc:." + R + "\n"
        a = a + E + "[38;5;12m" + "  .;ccccccccccccc;" + E + "[37;1m" + ".:dddl:." + E + "[38;5;12m" + ";ccccccc;." + R + "\n"
        a = a + E + "[38;5;12m" + " .:ccccccccccccc;" + E + "[37;1m" + "OWMKOOXMWd" + E + "[38;5;12m" + ";ccccccc:." + R + "\n"
        a = a + E + "[38;5;12m" + ".:ccccccccccccc;" + E + "[37;1m" + "KMMc" + E + "[38;5;12m" + ";cc;" + E + "[37;1m" + "xMMc" + E + "[38;5;12m" + ";ccccccc:." + R + "\n"
        a = a + E + "[38;5;12m" + ",cccccccccccccc;" + E + "[37;1m" + "MMM." + E + "[38;5;12m" + ";cc;" + E + "[37;1m" + ";WW:" + E + "[38;5;12m" + ";cccccccc," + R + "\n"
        a = a + E + "[38;5;12m" + ":cccccccccccccc;" + E + "[37;1m" + "MMM." + E + "[38;5;12m" + ";cccccccccccccccc:" + R + "\n"
        a = a + E + "[38;5;12m" + ":ccccccc;" + E + "[37;1m" + "oxOOOo" + E + "[38;5;12m" + ";" + E + "[37;1m" + "MMM0OOk." + E + "[38;5;12m" + ";cccccccccccc:" + R + "\n"
        a = a + E + "[38;5;12m" + "cccccc;" + E + "[37;1m" + "0MMKxdd:" + E + "[38;5;12m" + ";" + E + "[37;1m" + "MMMkddc." + E + "[38;5;12m" + ";cccccccccccc;" + R + "\n"
        a = a + E + "[38;5;12m" + "ccccc;" + E + "[37;1m" + "XM0'" + E + "[38;5;12m" + ";cccc;" + E + "[37;1m" + "MMM." + E + "[38;5;12m" + ";cccccccccccccccc'" + R + "\n"
        a = a + E + "[38;5;12m" + "ccccc;" + E + "[37;1m" + "MMo" + E + "[38;5;12m" + ";ccccc;" + E + "[37;1m" + "MMW." + E + "[38;5;12m" + ";ccccccccccccccc;" + R + "\n"
        a = a + E + "[38;5;12m" + "ccccc;" + E + "[37;1m" + "0MNc." + E + "[38;5;12m" + "ccc" + E + "[37;1m" + ".xMMd" + E + "[38;5;12m" + ";ccccccccccccccc;" + R + "\n"
        a = a + E + "[38;5;12m" + "cccccc;" + E + "[37;1m" + "dNMWXXXWM0:" + E + "[38;5;12m" + ";cccccccccccccc:," + R + "\n"
        a = a + E + "[38;5;12m" + "cccccccc;" + E + "[37;1m" + ".:odl:." + E + "[38;5;12m" + ";cccccccccccccc:,." + R + "\n"
        a = a + E + "[38;5;12m" + ":cccccccccccccccccccccccccccc:'." + R + "\n"
        a = a + E + "[38;5;12m" + ".:cccccccccccccccccccccc:;,.." + R + "\n"
        a = a + E + "[38;5;12m" + "  '::cccccccccccccc::;,." + R + "\n"
        emit a
    }
    if id == "chimera" {
        a = a + E + "[36;1m" + "ddddddddddddddc  ,cc:" + R + "\n"
        a = a + E + "[36;1m" + "ddddddddddddddc  ,cc:" + R + "\n"
        a = a + E + "[36;1m" + "ddddddddddddddd  ,cc:" + R + "\n"
        a = a + E + "[36;1m" + "ddddddddddddl:'  ,cc:" + R + "\n"
        a = a + E + "[36;1m" + "dddddddddl'    ..;cc:" + R + "\n"
        a = a + E + "[36;1m" + "dddddddo.   ,:cccccc:" + R + "\n"
        a = a + E + "[36;1m" + "ddddddl   ,ccc:'''''" + R + "\n"
        a = a + E + "[36;1m" + "dddddo.  ;ccc.          ............" + R + "\n"
        a = a + E + "[36;1m" + "        .ccc.           cccccccccccc" + R + "\n"
        a = a + E + "[36;1m" + "......  .ccc.          .ccc'''''''''" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOk.  ;ccc.        .ccc;   ......" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOd   'ccc:,....,:ccc'   coooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOx.   ':cccccccc:'   .looooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOOOd,     `'''`     .coooooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOOOOOOdc,.    ..,coooooooooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOOOOOOOOOO'  .oooooooooooooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOOOOOOOOOO'  .oooooooooooooooo" + R + "\n"
        a = a + E + "[36;1m" + "OOOOOOOOOOOOOOOO'  .oooooooooooooooo" + R + "\n"
        emit a
    }
    // fallback: Tux
    let W = E + "[37;1m"
    let Y = E + "[33;1m"
    a = a + W + "         a8888b." + R + "\n"
    a = a + W + "        d888888b." + R + "\n"
    a = a + W + "        8P\"YP\"Y88" + R + "\n"
    a = a + W + "        8|o||o|88" + R + "\n"
    a = a + W + "        8" + Y + "'    " + W + ".88" + R + "\n"
    a = a + W + "        8" + Y + "`._.'" + W + " Y8." + R + "\n"
    a = a + W + "       d/      `8b." + R + "\n"
    a = a + W + "      dP   .    Y8b." + R + "\n"
    a = a + W + "     d8:'  \"  `::88b." + R + "\n"
    a = a + W + "    d8\"         'Y88b" + R + "\n"
    a = a + W + "   :8P    '      :888" + R + "\n"
    a = a + W + "    8a.   :     _a88P" + R + "\n"
    a = a + Y + "  ._/\"Yaa_ :    .| 88P|" + R + "\n"
    a = a + Y + "  \\    YP\"      `| 8P  `." + R + "\n"
    a = a + Y + "  /     \\._____.d|    .'" + R + "\n"
    a = a + Y + "  `--..__)888888P`._.'" + R + "\n"
    emit a
}

func run() {
    kfcls()

    let E   = fromCharCode(27)
    let GRN = E + "[32;1m"
    let CYN = E + "[36;1m"
    let RST = E + "[0m"
    let YEL = E + "[33;1m"
    let WHT = E + "[37;1m"
    let LW  = "42"

    // Distro-specific ASCII logo (neofetch-derived), chosen by /etc/os-release.
    let art = distroArt(distroId(), E)

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let kern = kfkernel()
    let mdl  = sysmodel()
    let cpu  = cpubrand()
    let tn   = cputhreads()

    let mi   = raminfo()
    let tmb  = firstpart(mi, ",")
    let amb  = afterpart(mi, ",")
    let umb  = toInt(tmb) - toInt(amb) + ""
    let tgb  = toInt(tmb) / 1024 + ""
    let ugb  = toInt(umb) / 1024 + ""
    let rpct = "0"
    if toInt(tmb) > 0 { rpct = toInt(umb) * 100 / toInt(tmb) + "" }
    let rb   = rambar(umb, tmb)
    let swp  = swapinfo()

    let up   = uptimestr()
    let sh   = kfshell()
    let term = kfterm()
    let de   = kfde()

    // Build the packed info column — only non-empty fields are added.
    let IL = ""
    IL = IL + GRN + "User:  " + RST + usr + "@" + host + "\n"
    let osline = os
    if arch != "" { osline = osline + " " + arch }
    IL = IL + GRN + "OS:    " + RST + osline + "\n"
    if mdl != "" { IL = IL + GRN + "Host:  " + RST + mdl + "\n" }
    IL = IL + GRN + "Kernel:" + RST + kern + "\n"
    IL = IL + GRN + "CPU:   " + RST + cpu + " (" + tn + "t)\n"
    IL = IL + GRN + "RAM:   " + RST + rb + "  " + ugb + " GB / " + tgb + " GB  " + rpct + "%\n"
    if swp != "Unused" { IL = IL + GRN + "Swap:  " + RST + swp + "\n" }
    if de != "" { IL = IL + GRN + "DE:    " + RST + de + "\n" }
    IL = IL + GRN + "Shell: " + RST + sh + "\n"
    if term != "" { IL = IL + GRN + "Term:  " + RST + term + "\n" }
    IL = IL + GRN + "Uptime:" + RST + up + "\n"

    let idx = "0"
    let infolen = linecount(IL)
    let artlen  = linecount(art)
    let maxidx  = infolen
    if toInt(artlen) > toInt(maxidx) { maxidx = artlen }   // tall logos (e.g. parrot, fedora) aren't clipped
    while toInt(idx) < toInt(maxidx) {
        let logo = getLine(art, toInt(idx))   // "" past end -> padded to a blank logo column
        kp(padansi(logo, toInt(LW)) + "  " + infoline(IL, idx))
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    kp(CYN + "  KryoFetch" + RST + " by KryptonBytes")
    kp("")
    colorpalette()
    kp("")
    emit
}

just run {
    let watch = "0"
    let intervalSec = "1"
    let argc = argCount()
    let i = "0"
    while toInt(i) < toInt(argc) {
        let a = arg(i)
        if a == "--watch" {
            watch = "1"
            if toInt(i) + 1 < toInt(argc) { intervalSec = arg(toInt(i) + 1 + "") }
        }
        i = toInt(i) + 1 + ""
    }

    if watch == "0" {
        run()
    } else {
        while watch == "1" {
            run()
            gcCollect()
        }
    }
}
