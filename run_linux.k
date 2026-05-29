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
// ASCII lowercase. (Distro names start with a letter, so the digit-coercion of
// `+` never triggers here — once `out` holds a letter, concats stay textual.)
func lc(s) {
    let out = ""
    let i = 0
    while i < len(s) {
        let ch = substring(s, i, i + 1)
        if ch >= "A" && ch <= "Z" { out = out + fromCharCode(charCode(ch) + 32) }
        else { out = out + ch }
        i = i + 1
    }
    emit out
}

// Lowercased distro name from /etc/os-release NAME (then PRETTY_NAME). This is
// what distroArt() prefix-matches against neofetch's labels. Using NAME means
// BlackArch ("BlackArch Linux") never collides with Arch — it starts with "black".
func distroName() {
    let r = readFile("/etc/os-release")
    let nm = findLine(r, "NAME=")
    if nm == "" { nm = findLine(r, "PRETTY_NAME=") }
    if nm == "" { emit "linux" }
    let v = afterpart(nm, "=")
    if startsWith(v, "\"") { v = substring(v, 1, len(v)) }
    if endsWith(v, "\"")   { v = substring(v, 0, len(v) - 1) }
    emit lc(v)
}

// AUTO-GENERATED from neofetch — every distro logo (split into chunks so the
// compiler/optimizer handles small functions; one giant func was pathological).
func distroArt_0(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "container linux by coreos") || startsWith(dn, "container_linux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                ....." + R + "\n"
        a = a + E + "[34;1m" + "          .';:cccccccc:;'." + R + "\n"
        a = a + E + "[34;1m" + "        ':ccccclc" + E + "[31;1m" + "lllllllll" + E + "[34;1m" + "cc:." + R + "\n"
        a = a + E + "[34;1m" + "     .;cccccccc" + E + "[31;1m" + "lllllllllllllll" + E + "[34;1m" + "c," + R + "\n"
        a = a + E + "[34;1m" + "    ;clllccccc" + E + "[31;1m" + "llllllllllllllllll" + E + "[34;1m" + "c," + R + "\n"
        a = a + E + "[34;1m" + "  .cllclccccc" + E + "[31;1m" + "lllll" + E + "[37;1m" + "lll" + E + "[31;1m" + "llllllllllll" + E + "[34;1m" + "c:" + R + "\n"
        a = a + E + "[34;1m" + "  ccclclcccc" + E + "[31;1m" + "cllll" + E + "[37;1m" + "kWMMNKk" + E + "[31;1m" + "llllllllll" + E + "[34;1m" + "c:" + R + "\n"
        a = a + E + "[34;1m" + " :ccclclcccc" + E + "[31;1m" + "llll" + E + "[37;1m" + "oWMMMMMMWO" + E + "[31;1m" + "lllllllll" + E + "[34;1m" + "c," + R + "\n"
        a = a + E + "[34;1m" + ".ccllllllccc" + E + "[31;1m" + "clll" + E + "[37;1m" + "OMMMMMMMMM0" + E + "[31;1m" + "lllllllll" + E + "[34;1m" + "c" + R + "\n"
        a = a + E + "[34;1m" + ".lllllclcccc" + E + "[31;1m" + "llll" + E + "[37;1m" + "KMMMMMMMMMMo" + E + "[31;1m" + "llllllll" + E + "[34;1m" + "c." + R + "\n"
        a = a + E + "[34;1m" + ".lllllllcccc" + E + "[31;1m" + "clll" + E + "[37;1m" + "KMMMMMMMMN0" + E + "[31;1m" + "lllllllll" + E + "[34;1m" + "c." + R + "\n"
        a = a + E + "[34;1m" + ".cclllllcccc" + E + "[31;1m" + "lllld" + E + "[37;1m" + "xkkxxdo" + E + "[31;1m" + "llllllllllc" + E + "[34;1m" + "lc" + R + "\n"
        a = a + E + "[34;1m" + " :cccllllllcccc" + E + "[31;1m" + "lllccllllcclccc" + E + "[34;1m" + "cccccc;" + R + "\n"
        a = a + E + "[34;1m" + " .ccclllllllcccccccc" + E + "[31;1m" + "lll" + E + "[34;1m" + "ccccclccccccc" + R + "\n"
        a = a + E + "[34;1m" + "  .cllllllllllclcccclccclccllllcllc" + R + "\n"
        a = a + E + "[34;1m" + "    :cllllllllccclcllllllllllllcc;" + R + "\n"
        a = a + E + "[34;1m" + "     .cccccccccccccclcccccccccc:." + R + "\n"
        a = a + E + "[34;1m" + "       .;cccclccccccllllllccc,." + R + "\n"
        a = a + E + "[34;1m" + "          .';ccccclllccc:;.." + R + "\n"
        a = a + E + "[34;1m" + "                ....." + R + "\n"
        emit a
    }
    if startsWith(dn, "open source media center") || startsWith(dn, "osmc") {
        a = a + E + "[34;1m" + E + "[34;1m" + "            -+shdmNNNNmdhs+-" + R + "\n"
        a = a + E + "[34;1m" + "        .+hMNho/:..``..:/ohNMh+." + R + "\n"
        a = a + E + "[34;1m" + "      :hMdo.                .odMh:" + R + "\n"
        a = a + E + "[34;1m" + "    -dMy-                      -yMd-" + R + "\n"
        a = a + E + "[34;1m" + "   sMd-                          -dMs" + R + "\n"
        a = a + E + "[34;1m" + "  hMy       +.            .+       yMh" + R + "\n"
        a = a + E + "[34;1m" + " yMy        dMs.        .sMd        yMy" + R + "\n"
        a = a + E + "[34;1m" + ":Mm         dMNMs`    `sMNMd        `mM:" + R + "\n"
        a = a + E + "[34;1m" + "yM+         dM//mNs``sNm//Md         +My" + R + "\n"
        a = a + E + "[34;1m" + "mM-         dM:  +NNNN+  :Md         -Mm" + R + "\n"
        a = a + E + "[34;1m" + "mM-         dM: `oNN+    :Md         -Mm" + R + "\n"
        a = a + E + "[34;1m" + "yM+         dM/+NNo`     :Md         +My" + R + "\n"
        a = a + E + "[34;1m" + ":Mm`        dMMNs`       :Md        `mM:" + R + "\n"
        a = a + E + "[34;1m" + " yMy        dMs`         -ms        yMy" + R + "\n"
        a = a + E + "[34;1m" + "  hMy       +.                     yMh" + R + "\n"
        a = a + E + "[34;1m" + "   sMd-                          -dMs" + R + "\n"
        a = a + E + "[34;1m" + "    -dMy-                      -yMd-" + R + "\n"
        a = a + E + "[34;1m" + "      :hMdo.                .odMh:" + R + "\n"
        a = a + E + "[34;1m" + "        .+hMNho/:..``..:/ohNMh+." + R + "\n"
        a = a + E + "[34;1m" + "            -+shdmNNNNmdhs+-" + R + "\n"
        emit a
    }
    if startsWith(dn, "opensuse tumbleweed") || startsWith(dn, "opensuse_tumbleweed") {
        a = a + E + "[32;1m" + E + "[37;1m" + "                                     ......" + R + "\n"
        a = a + E + "[37;1m" + "     .,cdxxxoc,.               .:kKMMMNWMMMNk:." + R + "\n"
        a = a + E + "[37;1m" + "    cKMMN0OOOKWMMXo. ;        ;0MWk:.      .:OMMk." + R + "\n"
        a = a + E + "[37;1m" + "  ;WMK;.       .lKMMNM,     :NMK,             .OMW;" + R + "\n"
        a = a + E + "[37;1m" + " cMW;            'WMMMN   ,XMK,                 oMM'" + R + "\n"
        a = a + E + "[37;1m" + ".MMc               ..;l. xMN:                    KM0" + R + "\n"
        a = a + E + "[37;1m" + "'MM.                   'NMO                      oMM" + R + "\n"
        a = a + E + "[37;1m" + ".MM,                 .kMMl                       xMN" + R + "\n"
        a = a + E + "[37;1m" + " KM0               .kMM0. .dl:,..               .WMd" + R + "\n"
        a = a + E + "[37;1m" + " .XM0.           ,OMMK,    OMMMK.              .XMK" + R + "\n"
        a = a + E + "[37;1m" + "   oWMO:.    .;xNMMk,       NNNMKl.          .xWMx" + R + "\n"
        a = a + E + "[37;1m" + "     :ONMMNXMMMKx;          .  ,xNMWKkxllox0NMWk," + R + "\n"
        a = a + E + "[37;1m" + "         .....                    .:dOOXXKOxl," + R + "\n"
        emit a
    }
    if startsWith(dn, "profelis sambabox") || startsWith(dn, "sambabox") {
        a = a + E + "[33;1m" + E + "[33;1m" + R + "\n"
        a = a + E + "[33;1m" + "                    #" + R + "\n"
        a = a + E + "[33;1m" + "               *////#####" + R + "\n"
        a = a + E + "[33;1m" + "           /////////#########(" + R + "\n"
        a = a + E + "[33;1m" + "      .((((((/////    ,####(#(((((" + R + "\n"
        a = a + E + "[33;1m" + "  /#######(((*             (#(((((((((." + R + "\n"
        a = a + E + "[33;1m" + "//((#(#(#,        ((##(        ,((((((//" + R + "\n"
        a = a + E + "[33;1m" + "//////        #(##########(       //////" + R + "\n"
        a = a + E + "[33;1m" + "//////    ((#(#(#(#(##########(/////////" + R + "\n"
        a = a + E + "[33;1m" + "/////(    (((((((#########(##((((((/////" + R + "\n"
        a = a + E + "[33;1m" + "/(((#(                             ((((/" + R + "\n"
        a = a + E + "[33;1m" + "####(#                             ((###" + R + "\n"
        a = a + E + "[33;1m" + "#########(((/////////(((((((((,    (#(#(" + R + "\n"
        a = a + E + "[33;1m" + "########(   /////////(((((((*      #####" + R + "\n"
        a = a + E + "[33;1m" + "####///,        *////(((         (((((((" + R + "\n"
        a = a + E + "[33;1m" + ".///////////                .//(((((((((" + R + "\n"
        a = a + E + "[33;1m" + "     ///////////,       *(/////((((*" + R + "\n"
        a = a + E + "[33;1m" + "         ,/(((((((((##########/." + R + "\n"
        a = a + E + "[33;1m" + "             .((((((#######" + R + "\n"
        a = a + E + "[33;1m" + "                  ((##*" + R + "\n"
        emit a
    }
    if startsWith(dn, "aperio gnu/linux") {
        a = a + E + "[38;5;255m" + E + "[38;5;255m" + R + "\n"
        a = a + E + "[38;5;255m" + " _.._  _ ._.. _" + R + "\n"
        a = a + E + "[38;5;255m" + "(_][_)(/,[  |(_)" + R + "\n"
        a = a + E + "[38;5;255m" + "   |   GNU/Linux" + R + "\n"
        emit a
    }
    if startsWith(dn, "refracted devuan") || startsWith(dn, "refracted_devuan") {
        a = a + E + "[38;5;8m" + E + "[37;1m" + "                             A" + R + "\n"
        a = a + E + "[37;1m" + "                            VW" + R + "\n"
        a = a + E + "[37;1m" + "                           VVW\\\\" + R + "\n"
        a = a + E + "[37;1m" + "                         .yWWW\\\\" + R + "\n"
        a = a + E + "[37;1m" + " ,;,,u,;yy;;v;uyyyyyyy  ,WWWWW^" + R + "\n"
        a = a + E + "[37;1m" + "    *WWWWWWWWWWWWWWWW/  $VWWWWw      ," + R + "\n"
        a = a + E + "[37;1m" + "        ^*%WWWWWWVWWX  $WWWW**    ,yy" + R + "\n"
        a = a + E + "[37;1m" + "        ,    \"**WWW/' **'   ,yy/WWW*`" + R + "\n"
        a = a + E + "[37;1m" + "       &WWWWwy    `*`  <,ywWW%VWWW*" + R + "\n"
        a = a + E + "[37;1m" + "     yWWWWWWWWWW*    .,   \"**WW%W" + R + "\n"
        a = a + E + "[37;1m" + "   ,&WWWWWM*\"`  ,y/  &WWWww   ^*" + R + "\n"
        a = a + E + "[37;1m" + "  XWWX*^   ,yWWWW09 .WWWWWWWWwy," + R + "\n"
        a = a + E + "[37;1m" + " *`        &WWWWWM  WWWWWWWWWWWWWww," + R + "\n"
        a = a + E + "[37;1m" + "           (WWWWW` /#####WWW***********" + R + "\n"
        a = a + E + "[37;1m" + "           ^WWWW" + R + "\n"
        a = a + E + "[37;1m" + "            VWW" + R + "\n"
        a = a + E + "[37;1m" + "            Wh." + R + "\n"
        a = a + E + "[37;1m" + "            V/" + R + "\n"
        emit a
    }
    if startsWith(dn, "puppy") || startsWith(dn, "quirky werewolf") || startsWith(dn, "precise puppy") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           `-/osyyyysosyhhhhhyys+-" + R + "\n"
        a = a + E + "[34;1m" + "  -ohmNNmh+/hMMMMMMMMNNNNd+dMMMMNM+" + R + "\n"
        a = a + E + "[34;1m" + " yMMMMNNmmddo/NMMMNNNNNNNNNo+NNNNNy" + R + "\n"
        a = a + E + "[34;1m" + ".NNNNNNmmmddds:MMNNNNNNNNNNNh:mNNN/" + R + "\n"
        a = a + E + "[34;1m" + "-NNNdyyyhdmmmd`dNNNNNmmmmNNmdd/os/" + R + "\n"
        a = a + E + "[34;1m" + ".Nm+shddyooo+/smNNNNmmmmNh.   :mmd." + R + "\n"
        a = a + E + "[34;1m" + " NNNNy:`   ./hmmmmmmmNNNN:     hNMh" + R + "\n"
        a = a + E + "[34;1m" + " NMN-    -++- +NNNNNNNNNNm+..-sMMMM-" + R + "\n"
        a = a + E + "[34;1m" + ".MMo    oNNNNo hNNNNNNNNmhdNNNMMMMM+" + R + "\n"
        a = a + E + "[34;1m" + ".MMs    /NNNN/ dNmhs+:-`  yMMMMMMMM+" + R + "\n"
        a = a + E + "[34;1m" + " mMM+     .. `sNN+.      hMMMMhhMMM-" + R + "\n"
        a = a + E + "[34;1m" + " +MMMmo:...:sNMMMMMms:` hMMMMm.hMMy" + R + "\n"
        a = a + E + "[34;1m" + "  yMMMMMMMMMMMNdMMMMMM::/+o+//dMMd`" + R + "\n"
        a = a + E + "[34;1m" + "   sMMMMMMMMMMN+:oyyo:sMMMNNMMMNy`" + R + "\n"
        a = a + E + "[34;1m" + "    :mMMMMMMMMMMMmddNMMMMMMMMmh/" + R + "\n"
        a = a + E + "[34;1m" + "      /dMMMMMMMMMMMMMMMMMMNdy/`" + R + "\n"
        a = a + E + "[34;1m" + "        .+hNMMMMMMMMMNmdhs/." + R + "\n"
        a = a + E + "[34;1m" + "            .:/+ooo+/:-." + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu cinnamon") || startsWith(dn, "ubuntu-cinnamon") {
        a = a + E + "[31;1m" + E + "[31;1m" + "            .-/+oooooooo+/-." + R + "\n"
        a = a + E + "[31;1m" + "        `:+oooooooooooooooooo+:`" + R + "\n"
        a = a + E + "[31;1m" + "      -+oooooooooooooooooooooooo+-" + R + "\n"
        a = a + E + "[31;1m" + "    .ooooooooooooooooooo" + E + "[37;1m" + ":ohNd" + E + "[31;1m" + "oooooo." + R + "\n"
        a = a + E + "[31;1m" + "   /oooooooooooo" + E + "[37;1m" + ":/+oo++:/ohNd" + E + "[31;1m" + "ooooooo/" + R + "\n"
        a = a + E + "[31;1m" + "  +oooooooooo" + E + "[37;1m" + ":osNdhyyhdNNh+:+" + E + "[31;1m" + "oooooooo+" + R + "\n"
        a = a + E + "[31;1m" + " /ooooooooo" + E + "[37;1m" + "/dN/" + E + "[31;1m" + "ooooooooo" + E + "[37;1m" + "/sNNo" + E + "[31;1m" + "ooooooooo/" + R + "\n"
        a = a + E + "[31;1m" + ".ooooooooo" + E + "[37;1m" + "oMd:" + E + "[31;1m" + "oooooooooooo" + E + "[37;1m" + ":yMy" + E + "[31;1m" + "ooooooooo." + R + "\n"
        a = a + E + "[31;1m" + "+ooooo" + E + "[37;1m" + ":+o/Md" + E + "[31;1m" + "oooooo" + E + "[37;1m" + ":sm/" + E + "[31;1m" + "oo/ooo" + E + "[37;1m" + "yMo" + E + "[31;1m" + "oooooooo+" + R + "\n"
        a = a + E + "[31;1m" + "ooo" + E + "[37;1m" + ":sdMdosMo" + E + "[31;1m" + "ooooo" + E + "[37;1m" + "oNMd" + E + "[31;1m" + "//" + E + "[37;1m" + "dMd+" + E + "[31;1m" + "o" + E + "[37;1m" + ":so" + E + "[31;1m" + "ooooooooo" + R + "\n"
        a = a + E + "[31;1m" + "oooo" + E + "[37;1m" + "+ymdosMo" + E + "[31;1m" + "ooo" + E + "[37;1m" + "+mMm" + E + "[31;1m" + "+/" + E + "[37;1m" + "hMMMMMh+hs" + E + "[31;1m" + "ooooooooo" + R + "\n"
        a = a + E + "[31;1m" + "+oooooo" + E + "[37;1m" + ":" + E + "[31;1m" + ":" + E + "[37;1m" + "/Nm:" + E + "[31;1m" + "/" + E + "[37;1m" + "hMNo" + E + "[31;1m" + ":y" + E + "[37;1m" + "MMMMMMMMMM+" + E + "[31;1m" + "oooooooo+" + R + "\n"
        a = a + E + "[31;1m" + ".ooooooooo" + E + "[37;1m" + "/NNMNy" + E + "[31;1m" + ":o" + E + "[37;1m" + "NMMMMMMMMMMo" + E + "[31;1m" + "ooooooooo." + R + "\n"
        a = a + E + "[31;1m" + "/oooooooooo" + E + "[37;1m" + ":yh:" + E + "[31;1m" + "+m" + E + "[37;1m" + "MMMMMMMMMMd/" + E + "[31;1m" + "ooooooooo/" + R + "\n"
        a = a + E + "[31;1m" + "  +oooooooooo" + E + "[37;1m" + "+" + E + "[31;1m" + "/h" + E + "[37;1m" + "mMMMMMMNds//o" + E + "[31;1m" + "oooooooo+" + R + "\n"
        a = a + E + "[31;1m" + "   /oooooooooooo" + E + "[37;1m" + "+:////:o/ymMd" + E + "[31;1m" + "ooooooo/" + R + "\n"
        a = a + E + "[31;1m" + "    .oooooooooooooooooooo" + E + "[37;1m" + "/sdh" + E + "[31;1m" + "oooooo." + R + "\n"
        a = a + E + "[31;1m" + "      -+oooooooooooooooooooooooo+-" + R + "\n"
        a = a + E + "[31;1m" + "        `:+oooooooooooooooooo+:`" + R + "\n"
        a = a + E + "[31;1m" + "            .-/+oooooooo+/-." + R + "\n"
        emit a
    }
    if startsWith(dn, "clear linux os") || startsWith(dn, "clear_linux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "          BBB" + R + "\n"
        a = a + E + "[34;1m" + "       BBBBBBBBB" + R + "\n"
        a = a + E + "[34;1m" + "     BBBBBBBBBBBBBBB" + R + "\n"
        a = a + E + "[34;1m" + "   BBBBBBBBBBBBBBBBBBBB" + R + "\n"
        a = a + E + "[34;1m" + "   BBBBBBBBBBB         BBB" + R + "\n"
        a = a + E + "[34;1m" + "  BBBBBBBB" + E + "[33;1m" + "YYYYY" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  BBBBBBBB" + E + "[33;1m" + "YYYYYY" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  BBBBBBBB" + E + "[33;1m" + "YYYYYYY" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  BBBBBBBBB" + E + "[33;1m" + "YYYYY" + E + "[37;1m" + "W" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " GG" + E + "[34;1m" + "BBBBBBBY" + E + "[33;1m" + "YYYY" + E + "[37;1m" + "WWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " GGG" + E + "[34;1m" + "BBBBBBB" + E + "[33;1m" + "YY" + E + "[37;1m" + "WWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " GGGGGG" + E + "[34;1m" + "BBBBBB" + E + "[37;1m" + "WWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " GGGGGGGG" + E + "[34;1m" + "BBBB" + E + "[37;1m" + "WWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "GGGGGGGGGGG" + E + "[34;1m" + "BBB" + E + "[37;1m" + "WWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "GGGGGGGGGGGGG" + E + "[34;1m" + "B" + E + "[37;1m" + "WWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "GGGGGGGG" + E + "[37;1m" + "WWWWWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "GG" + E + "[37;1m" + "WWWWWWWWWWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + " WWWWWWWWWWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + "      WWWWWWWWWW" + R + "\n"
        a = a + E + "[37;1m" + "          WWW" + R + "\n"
        emit a
    }
    if startsWith(dn, "januslinux") || startsWith(dn, "janus") || startsWith(dn, "ataraxia linux") || startsWith(dn, "ataraxia") {
        a = a + E + "[34;1m" + E + "[34;1m" + "               'l:" + R + "\n"
        a = a + E + "[34;1m" + "        loooooo" + R + "\n"
        a = a + E + "[34;1m" + "          loooo coooool" + R + "\n"
        a = a + E + "[34;1m" + " looooooooooooooooooool" + R + "\n"
        a = a + E + "[34;1m" + "  looooooooooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "         lool   cooo" + R + "\n"
        a = a + E + "[34;1m" + "        coooooooloooooooo" + R + "\n"
        a = a + E + "[34;1m" + "     clooooo  ;lood  cloooo" + R + "\n"
        a = a + E + "[34;1m" + "  :loooocooo cloo      loooo" + R + "\n"
        a = a + E + "[34;1m" + " loooo  :ooooool       loooo" + R + "\n"
        a = a + E + "[34;1m" + "looo    cooooo        cooooo" + R + "\n"
        a = a + E + "[34;1m" + "looooooooooooo      ;loooooo " + E + "[35;1m" + "looooooc" + R + "\n"
        a = a + E + "[35;1m" + E + "[34;1m" + "looooooooo loo   cloooooool    " + E + "[35;1m" + "looooc" + R + "\n"
        a = a + E + "[35;1m" + E + "[34;1m" + " cooo       cooooooooooo       " + E + "[35;1m" + "looolooooool" + R + "\n"
        a = a + E + "[35;1m" + E + "[34;1m" + "            cooo:     " + E + "[35;1m" + "coooooooooooooooooool" + R + "\n"
        a = a + E + "[35;1m" + "                       loooooooooooolc:   loooc;" + R + "\n"
        a = a + E + "[35;1m" + "                             cooo:    loooooooooooc" + R + "\n"
        a = a + E + "[35;1m" + "                            ;oool         looooooo:" + R + "\n"
        a = a + E + "[35;1m" + "                           coool          olc," + R + "\n"
        a = a + E + "[35;1m" + "                          looooc   ,," + R + "\n"
        a = a + E + "[35;1m" + "                        coooooc    loc" + R + "\n"
        a = a + E + "[35;1m" + "                       :oooool,    coool:, looool:," + R + "\n"
        a = a + E + "[35;1m" + "                       looool:      ooooooooooooooo:" + R + "\n"
        a = a + E + "[35;1m" + "                       cooolc        .ooooooooooool" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_1(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "linux mint old") || startsWith(dn, "linuxmintold") || startsWith(dn, "mint_old") {
        a = a + E + "[32;1m" + E + "[32;1m" + "MMMMMMMMMMMMMMMMMMMMMMMMMmds+." + R + "\n"
        a = a + E + "[32;1m" + "MMm----::-://////////////oymNMd+`" + R + "\n"
        a = a + E + "[32;1m" + "MMd      " + E + "[37;1m" + "/++                " + E + "[32;1m" + "-sNMd:" + R + "\n"
        a = a + E + "[32;1m" + "MMNso/`  " + E + "[37;1m" + "dMM    `.::-. .-::.` " + E + "[32;1m" + ".hMN:" + R + "\n"
        a = a + E + "[32;1m" + "ddddMMh  " + E + "[37;1m" + "dMM   :hNMNMNhNMNMNh: " + E + "[32;1m" + "`NMm" + R + "\n"
        a = a + E + "[32;1m" + "    NMm  " + E + "[37;1m" + "dMM  .NMN/-+MMM+-/NMN` " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    NMm  " + E + "[37;1m" + "dMM  -MMm  `MMM   dMM. " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    NMm  " + E + "[37;1m" + "dMM  -MMm  `MMM   dMM. " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    NMm  " + E + "[37;1m" + "dMM  .mmd  `mmm   yMM. " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    NMm  " + E + "[37;1m" + "dMM`  ..`   ...   ydm. " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    hMM- " + E + "[37;1m" + "+MMd/-------...-:sdds  " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "    -NMm- " + E + "[37;1m" + ":hNMNNNmdddddddddy/`  " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "     -dMNs-" + E + "[37;1m" + "``-::::-------.``    " + E + "[32;1m" + "dMM" + R + "\n"
        a = a + E + "[32;1m" + "      `/dMNmy+/:-------------:/yMMM" + R + "\n"
        a = a + E + "[32;1m" + "         ./ydNMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[32;1m" + "            .MMMMMMMMMMMMMMMMMMM" + R + "\n"
        emit a
    }
    if startsWith(dn, "aosc os/retro") {
        a = a + E + "[34;1m" + E + "[37;1m" + "          ........." + R + "\n"
        a = a + E + "[37;1m" + "     ..................." + R + "\n"
        a = a + E + "[37;1m" + "   ....................." + E + "[34;1m" + "################" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + " ..............     ...." + E + "[34;1m" + "################" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "..............       ..." + E + "[34;1m" + "################" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + ".............         .." + E + "[34;1m" + "****************" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "............     .     ." + E + "[34;1m" + "****************" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "...........     ...     " + E + "[34;1m" + "................" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "..........     .....     " + E + "[34;1m" + "..............." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + ".........     .......     ..." + R + "\n"
        a = a + E + "[37;1m" + " ." + E + "[31;1m" + "......                   " + E + "[37;1m" + "." + R + "\n"
        a = a + E + "[37;1m" + "  " + E + "[31;1m" + ".....      ....." + E + "[37;1m" + "....    " + E + "[33;1m" + "..........." + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[31;1m" + "....      ......" + E + "[37;1m" + ".       " + E + "[33;1m" + "..........." + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[31;1m" + "...      .......        " + E + "[33;1m" + "..........." + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[31;1m" + "................        " + E + "[33;1m" + "***********" + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[31;1m" + "................        " + E + "[33;1m" + "###########" + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[31;1m" + "****************" + R + "\n"
        a = a + E + "[31;1m" + "  " + E + "[31;1m" + "################" + R + "\n"
        emit a
    }
    if startsWith(dn, "dragonfly_old") {
        a = a + E + "[31;1m" + "     " + E + "[31;1m" + "                   .-." + R + "\n"
        a = a + E + "[31;1m" + "                 " + E + "[33;1m" + " ()" + E + "[31;1m" + "I" + E + "[33;1m" + "()" + R + "\n"
        a = a + E + "[33;1m" + "            " + E + "[31;1m" + " \"==.__:-:__.==\"" + R + "\n"
        a = a + E + "[31;1m" + "            \"==.__/~|~\\__.==\"" + R + "\n"
        a = a + E + "[31;1m" + "            \"==._(  Y  )_.==\"" + R + "\n"
        a = a + E + "[31;1m" + " " + E + "[37;1m" + ".-'~~\"\"~=--...,__" + E + "[31;1m" + "\\/|\\/" + E + "[37;1m" + "__,...--=~\"\"~~'-." + R + "\n"
        a = a + E + "[37;1m" + "(               ..=" + E + "[31;1m" + "\\\\=" + E + "[31;1m" + "/" + E + "[37;1m" + "=..               )" + R + "\n"
        a = a + E + "[37;1m" + " `'-.        ,.-\"`;" + E + "[31;1m" + "/=\\\\" + E + "[37;1m" + ";\"-.,_        .-'`" + R + "\n"
        a = a + E + "[37;1m" + "     `~\"-=-~` .-~` " + E + "[31;1m" + "|=|" + E + "[37;1m" + " `~-. `~-=-\"~`" + R + "\n"
        a = a + E + "[37;1m" + "          .-~`    /" + E + "[31;1m" + "|=|" + E + "[37;1m" + "\\    `~-." + R + "\n"
        a = a + E + "[37;1m" + "       .~`       / " + E + "[31;1m" + "|=|" + E + "[37;1m" + " \\       `~." + R + "\n"
        a = a + E + "[37;1m" + "   .-~`        .'  " + E + "[31;1m" + "|=|" + E + "[37;1m" + "  `.        `~-." + R + "\n"
        a = a + E + "[37;1m" + " (`     _,.-=\"`  " + E + "[31;1m" + "  |=|" + E + "[37;1m" + "    `\"=-.,_     `)" + R + "\n"
        a = a + E + "[37;1m" + "  `~\"~\"`        " + E + "[31;1m" + "   |=|" + E + "[37;1m" + "           `\"~\"~`" + R + "\n"
        a = a + E + "[37;1m" + "                 " + E + "[31;1m" + "  /=\\\\" + R + "\n"
        a = a + E + "[31;1m" + "                   \\\\=/" + R + "\n"
        a = a + E + "[31;1m" + "                    ^" + R + "\n"
        emit a
    }
    if startsWith(dn, "opensuse leap") || startsWith(dn, "opensuse_leap") {
        a = a + E + "[32;1m" + E + "[37;1m" + "                 `-++:`" + R + "\n"
        a = a + E + "[37;1m" + "               ./oooooo/-" + R + "\n"
        a = a + E + "[37;1m" + "            `:oooooooooooo:." + R + "\n"
        a = a + E + "[37;1m" + "          -+oooooooooooooooo+-`" + R + "\n"
        a = a + E + "[37;1m" + "       ./oooooooooooooooooooooo/-" + R + "\n"
        a = a + E + "[37;1m" + "      :oooooooooooooooooooooooooo:" + R + "\n"
        a = a + E + "[37;1m" + "    `  `-+oooooooooooooooooooo/-   `" + R + "\n"
        a = a + E + "[37;1m" + " `:oo/-   .:ooooooooooooooo+:`  `-+oo/." + R + "\n"
        a = a + E + "[37;1m" + "`/oooooo:.   -/oooooooooo/.   ./oooooo/." + R + "\n"
        a = a + E + "[37;1m" + "  `:+ooooo+-`  `:+oooo+-   `:oooooo+:`" + R + "\n"
        a = a + E + "[37;1m" + "     .:oooooo/.   .::`   -+oooooo/." + R + "\n"
        a = a + E + "[37;1m" + "        -/oooooo:.    ./oooooo+-" + R + "\n"
        a = a + E + "[37;1m" + "          `:+ooooo+-:+oooooo:`" + R + "\n"
        a = a + E + "[37;1m" + "             ./oooooooooo/." + R + "\n"
        a = a + E + "[37;1m" + "                -/oooo+:`" + R + "\n"
        a = a + E + "[37;1m" + "                  `:/." + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu budgie") || startsWith(dn, "ubuntu-budgie") {
        a = a + E + "[34;1m" + E + "[37;1m" + "           ./oydmMMMMMMmdyo/." + R + "\n"
        a = a + E + "[37;1m" + "        :smMMMMMMMMMMMhs+:++yhs:" + R + "\n"
        a = a + E + "[37;1m" + "     `omMMMMMMMMMMMN+`        `odo`" + R + "\n"
        a = a + E + "[37;1m" + "    /NMMMMMMMMMMMMN-            `sN/" + R + "\n"
        a = a + E + "[37;1m" + "  `hMMMMmhhmMMMMMMh               sMh`" + R + "\n"
        a = a + E + "[37;1m" + " .mMmo-     /yMMMMm`              `MMm." + R + "\n"
        a = a + E + "[37;1m" + " mN/       yMMMMMMMd-              MMMm" + R + "\n"
        a = a + E + "[37;1m" + "oN-        oMMMMMMMMMms+//+o+:    :MMMMo" + R + "\n"
        a = a + E + "[37;1m" + "m/          +NMMMMMMMMMMMMMMMMm. :NMMMMm" + R + "\n"
        a = a + E + "[37;1m" + "M`           .NMMMMMMMMMMMMMMMNodMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "M-            sMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "mm`           mMMMMMMMMMNdhhdNMMMMMMMMMm" + R + "\n"
        a = a + E + "[37;1m" + "oMm/        .dMMMMMMMMh:      :dMMMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + " mMMNyo/:/sdMMMMMMMMM+          sMMMMMm" + R + "\n"
        a = a + E + "[37;1m" + " .mMMMMMMMMMMMMMMMMMs           `NMMMm." + R + "\n"
        a = a + E + "[37;1m" + "  `hMMMMMMMMMMM.oo+.            `MMMh`" + R + "\n"
        a = a + E + "[37;1m" + "    /NMMMMMMMMMo                sMN/" + R + "\n"
        a = a + E + "[37;1m" + "     `omMMMMMMMMy.            :dmo`" + R + "\n"
        a = a + E + "[37;1m" + "        :smMMMMMMMh+-`   `.:ohs:" + R + "\n"
        a = a + E + "[37;1m" + "           ./oydmMMMMMMdhyo/." + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu studio") || startsWith(dn, "ubuntu-studio") {
        a = a + E + "[36;1m" + E + "[36;1m" + "              ..-::::::-.`" + R + "\n"
        a = a + E + "[36;1m" + "         `.:+++++++++++" + E + "[37;1m" + "ooo" + E + "[36;1m" + "++:.`" + R + "\n"
        a = a + E + "[36;1m" + "       ./+++++++++++++" + E + "[37;1m" + "sMMMNdyo" + E + "[36;1m" + "+/." + R + "\n"
        a = a + E + "[36;1m" + "     .++++++++++++++++" + E + "[37;1m" + "oyhmMMMMms" + E + "[36;1m" + "++." + R + "\n"
        a = a + E + "[36;1m" + "   `/+++++++++" + E + "[37;1m" + "osyhddddhys" + E + "[36;1m" + "+" + E + "[37;1m" + "osdMMMh" + E + "[36;1m" + "++/`" + R + "\n"
        a = a + E + "[36;1m" + "  `+++++++++" + E + "[37;1m" + "ydMMMMNNNMMMMNds" + E + "[36;1m" + "+" + E + "[37;1m" + "oyyo" + E + "[36;1m" + "++++`" + R + "\n"
        a = a + E + "[36;1m" + "  +++++++++" + E + "[37;1m" + "dMMNhso" + E + "[36;1m" + "++++" + E + "[37;1m" + "oydNMMmo" + E + "[36;1m" + "++++++++`" + R + "\n"
        a = a + E + "[36;1m" + " :+" + E + "[37;1m" + "odmy" + E + "[36;1m" + "+++" + E + "[37;1m" + "ooysoohmNMMNmyoohMMNs" + E + "[36;1m" + "+++++++:" + R + "\n"
        a = a + E + "[36;1m" + " ++" + E + "[37;1m" + "dMMm" + E + "[36;1m" + "+" + E + "[37;1m" + "oNMd" + E + "[36;1m" + "++" + E + "[37;1m" + "yMMMmhhmMMNs+yMMNo" + E + "[36;1m" + "+++++++" + R + "\n"
        a = a + E + "[36;1m" + "`++" + E + "[37;1m" + "NMMy" + E + "[36;1m" + "+" + E + "[37;1m" + "hMMd" + E + "[36;1m" + "+" + E + "[37;1m" + "oMMMs" + E + "[36;1m" + "++++" + E + "[37;1m" + "sMMN" + E + "[36;1m" + "++" + E + "[37;1m" + "NMMs" + E + "[36;1m" + "+++++++." + R + "\n"
        a = a + E + "[36;1m" + "`++" + E + "[37;1m" + "NMMy" + E + "[36;1m" + "+" + E + "[37;1m" + "hMMd" + E + "[36;1m" + "+" + E + "[37;1m" + "oMMMo" + E + "[36;1m" + "++++" + E + "[37;1m" + "sMMN" + E + "[36;1m" + "++" + E + "[37;1m" + "mMMs" + E + "[36;1m" + "+++++++." + R + "\n"
        a = a + E + "[36;1m" + " ++" + E + "[37;1m" + "dMMd" + E + "[36;1m" + "+" + E + "[37;1m" + "oNMm" + E + "[36;1m" + "++" + E + "[37;1m" + "yMMNdhhdMMMs" + E + "[36;1m" + "+y" + E + "[37;1m" + "MMNo" + E + "[36;1m" + "+++++++" + R + "\n"
        a = a + E + "[36;1m" + " :+" + E + "[37;1m" + "odmy" + E + "[36;1m" + "++" + E + "[37;1m" + "oo" + E + "[36;1m" + "+" + E + "[37;1m" + "ss" + E + "[36;1m" + "+" + E + "[37;1m" + "ohNMMMMmho" + E + "[36;1m" + "+" + E + "[37;1m" + "yMMMs" + E + "[36;1m" + "+++++++:" + R + "\n"
        a = a + E + "[36;1m" + "  +++++++++" + E + "[37;1m" + "hMMmhs+ooo+oshNMMms" + E + "[36;1m" + "++++++++" + R + "\n"
        a = a + E + "[36;1m" + "  `++++++++" + E + "[37;1m" + "oymMMMMNmmNMMMMmy+oys" + E + "[36;1m" + "+++++`" + R + "\n"
        a = a + E + "[36;1m" + "   `/+++++++++" + E + "[37;1m" + "oyhdmmmmdhso+sdMMMs" + E + "[36;1m" + "++/" + R + "\n"
        a = a + E + "[36;1m" + "     ./+++++++++++++++" + E + "[37;1m" + "oyhdNMMMms" + E + "[36;1m" + "++." + R + "\n"
        a = a + E + "[36;1m" + "       ./+++++++++++++" + E + "[37;1m" + "hMMMNdyo" + E + "[36;1m" + "+/." + R + "\n"
        a = a + E + "[36;1m" + "         `.:+++++++++++" + E + "[37;1m" + "sso" + E + "[36;1m" + "++:." + R + "\n"
        a = a + E + "[36;1m" + "              ..-::::::-.." + R + "\n"
        emit a
    }
    if startsWith(dn, "langitketujuh") {
        a = a + E + "[37;1m" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "      'L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L.   'L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                             L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                             L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L             L7L7L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                'L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                    'L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                             L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L                             L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L.   'L7L" + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L." + R + "\n"
        a = a + E + "[37;1m" + "   L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L" + R + "\n"
        a = a + E + "[37;1m" + E + "[34;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "openmandriva") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                  ``````" + R + "\n"
        a = a + E + "[34;1m" + "            `-:/+++++++//:-.`" + R + "\n"
        a = a + E + "[34;1m" + "         .:+++oooo+/:.``   ``" + R + "\n"
        a = a + E + "[34;1m" + "      `:+ooooooo+:.  `-:/++++++/:.`" + R + "\n"
        a = a + E + "[34;1m" + "     -+oooooooo:` `-++o+/::::://+o+/-" + R + "\n"
        a = a + E + "[34;1m" + "   `/ooooooooo-  -+oo/.`        `-/oo+." + R + "\n"
        a = a + E + "[34;1m" + "  `+ooooooooo.  :os/`              .+so:" + R + "\n"
        a = a + E + "[34;1m" + "  +sssssssss/  :ss/                 `+ss-" + R + "\n"
        a = a + E + "[34;1m" + " :ssssssssss`  sss`                  .sso" + R + "\n"
        a = a + E + "[34;1m" + " ossssssssss  `yyo                    sys" + R + "\n"
        a = a + E + "[34;1m" + "`sssssssssss` `yys                   `yys" + R + "\n"
        a = a + E + "[34;1m" + "`sssssssssss:  +yy/                  +yy:" + R + "\n"
        a = a + E + "[34;1m" + " oyyyyyyyyyys. `oyy/`              `+yy+" + R + "\n"
        a = a + E + "[34;1m" + " :yyyyyyyyyyyo. `+yhs:.         `./shy/" + R + "\n"
        a = a + E + "[34;1m" + "  oyyyyyyyyyyys:` .oyhys+:----/+syhy+. `" + R + "\n"
        a = a + E + "[34;1m" + "  `syyyyyyyyyyyyo-` .:osyhhhhhyys+:``.:`" + R + "\n"
        a = a + E + "[34;1m" + "   `oyyyyyyyyyyyyys+-`` `.----.```./oo." + R + "\n"
        a = a + E + "[34;1m" + "     /yhhhhhhhhhhhhhhyso+//://+osyhy/`" + R + "\n"
        a = a + E + "[34;1m" + "      `/yhhhhhhhhhhhhhhhhhhhhhhhhy/`" + R + "\n"
        a = a + E + "[34;1m" + "        `:oyhhhhhhhhhhhhhhhhhhyo:`" + R + "\n"
        a = a + E + "[34;1m" + "            .:+syhhhhhhhhys+:-`" + R + "\n"
        a = a + E + "[34;1m" + "                 ``....``" + R + "\n"
        emit a
    }
    if startsWith(dn, "postmarketos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                 /\\\\" + R + "\n"
        a = a + E + "[32;1m" + "                /  \\\\" + R + "\n"
        a = a + E + "[32;1m" + "               /    \\\\" + R + "\n"
        a = a + E + "[32;1m" + "              /      \\\\" + R + "\n"
        a = a + E + "[32;1m" + "             /        \\\\" + R + "\n"
        a = a + E + "[32;1m" + "            /          \\\\" + R + "\n"
        a = a + E + "[32;1m" + "            \\\\           \\\\" + R + "\n"
        a = a + E + "[32;1m" + "          /\\\\ \\\\____       \\\\" + R + "\n"
        a = a + E + "[32;1m" + "         /  \\\\____ \\\\       \\\\" + R + "\n"
        a = a + E + "[32;1m" + "        /       /  \\\\       \\\\" + R + "\n"
        a = a + E + "[32;1m" + "       /       /    \\\\    ___\\\\" + R + "\n"
        a = a + E + "[32;1m" + "      /       /      \\\\  / ____" + R + "\n"
        a = a + E + "[32;1m" + "     /       /        \\\\/ /    \\\\" + R + "\n"
        a = a + E + "[32;1m" + "    /       / __________/      \\\\" + R + "\n"
        a = a + E + "[32;1m" + "   /        \\\\ \\\\                 \\\\" + R + "\n"
        a = a + E + "[32;1m" + "  /          \\\\ \\\\                 \\\\" + R + "\n"
        a = a + E + "[32;1m" + " /           / /                  \\\\" + R + "\n"
        a = a + E + "[32;1m" + "/___________/ /____________________\\\\" + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu-gnome") {
        a = a + E + "[34;1m" + E + "[37;1m" + "          ./o." + R + "\n"
        a = a + E + "[37;1m" + "        .oooooooo" + R + "\n"
        a = a + E + "[37;1m" + "      .oooo```soooo" + R + "\n"
        a = a + E + "[37;1m" + "    .oooo`     `soooo" + R + "\n"
        a = a + E + "[37;1m" + "   .ooo`   " + E + "[36;1m" + ".o." + E + "[37;1m" + "   `\\/ooo." + R + "\n"
        a = a + E + "[37;1m" + "   :ooo   " + E + "[36;1m" + ":oooo." + E + "[37;1m" + "   `\\/ooo." + R + "\n"
        a = a + E + "[37;1m" + "    sooo    " + E + "[36;1m" + "`ooooo" + E + "[37;1m" + "    \\/oooo" + R + "\n"
        a = a + E + "[37;1m" + "     \\/ooo    " + E + "[36;1m" + "`soooo" + E + "[37;1m" + "    `ooooo" + R + "\n"
        a = a + E + "[37;1m" + "      `soooo    " + E + "[36;1m" + "`\\/ooo" + E + "[37;1m" + "    `soooo" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "./oo    " + E + "[37;1m" + "`\\/ooo    " + E + "[36;1m" + "`/oooo." + E + "[37;1m" + "   `/ooo" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "`\\/ooo.   " + E + "[37;1m" + "`/oooo.   " + E + "[36;1m" + "`/oooo." + E + "[37;1m" + "   ``" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "  `\\/ooo.    " + E + "[37;1m" + "/oooo     " + E + "[36;1m" + "/ooo`" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "     `ooooo    " + E + "[37;1m" + "``    " + E + "[36;1m" + ".oooo" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "       `soooo.     .oooo`" + R + "\n"
        a = a + E + "[36;1m" + "         `\\/oooooooooo`" + R + "\n"
        a = a + E + "[36;1m" + "            ``\\/oo``" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_2(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "cbl-mariner") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                    ." + R + "\n"
        a = a + E + "[36;1m" + "                  :-  ." + R + "\n"
        a = a + E + "[36;1m" + "                :==. .=:" + R + "\n"
        a = a + E + "[36;1m" + "              :===:  -==:" + R + "\n"
        a = a + E + "[36;1m" + "            :-===:  .====:" + R + "\n"
        a = a + E + "[36;1m" + "          :-====-   -=====:" + R + "\n"
        a = a + E + "[36;1m" + "         -======   :=======:" + R + "\n"
        a = a + E + "[36;1m" + "        -======.  .=========:" + R + "\n"
        a = a + E + "[36;1m" + "       -======:   -==========." + R + "\n"
        a = a + E + "[36;1m" + "      -======-    -===========." + R + "\n"
        a = a + E + "[36;1m" + "     :======-      :===========." + R + "\n"
        a = a + E + "[36;1m" + "    :=======.       .-==========." + R + "\n"
        a = a + E + "[36;1m" + "   :=======:          -==========." + R + "\n"
        a = a + E + "[36;1m" + "  :=======-            :==========." + R + "\n"
        a = a + E + "[36;1m" + " :=======-              .-========-" + R + "\n"
        a = a + E + "[36;1m" + ":--------.                :========-" + R + "\n"
        a = a + E + "[36;1m" + "                    ..:::--=========-" + R + "\n"
        a = a + E + "[36;1m" + "            ..::---================-=-" + R + "\n"
        emit a
    }
    if startsWith(dn, "endeavouros") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                     ./" + E + "[35;1m" + "o" + E + "[34;1m" + "." + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "                   ./" + E + "[35;1m" + "sssso" + E + "[34;1m" + "-" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "                 `:" + E + "[35;1m" + "osssssss+" + E + "[34;1m" + "-" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "               `:+" + E + "[35;1m" + "sssssssssso" + E + "[34;1m" + "/." + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "             `-/o" + E + "[35;1m" + "ssssssssssssso" + E + "[34;1m" + "/." + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "           `-/+" + E + "[35;1m" + "sssssssssssssssso" + E + "[34;1m" + "+:`" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "         `-:/+" + E + "[35;1m" + "sssssssssssssssssso" + E + "[34;1m" + "+/." + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "       `.://o" + E + "[35;1m" + "sssssssssssssssssssso" + E + "[34;1m" + "++-" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "      .://+" + E + "[35;1m" + "ssssssssssssssssssssssso" + E + "[34;1m" + "++:" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "    .:///o" + E + "[35;1m" + "ssssssssssssssssssssssssso" + E + "[34;1m" + "++:" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "  `:////" + E + "[35;1m" + "ssssssssssssssssssssssssssso" + E + "[34;1m" + "+++." + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + "`-////+" + E + "[35;1m" + "ssssssssssssssssssssssssssso" + E + "[34;1m" + "++++-" + R + "\n"
        a = a + E + "[34;1m" + E + "[31;1m" + " `..-+" + E + "[35;1m" + "oosssssssssssssssssssssssso" + E + "[34;1m" + "+++++/`" + R + "\n"
        a = a + E + "[34;1m" + "   ./++++++++++++++++++++++++++++++/:." + R + "\n"
        a = a + E + "[34;1m" + "  `:::::::::::::::::::::::::------``" + R + "\n"
        emit a
    }
    if startsWith(dn, "openindiana") {
        a = a + E + "[34;1m" + E + "[37;1m" + "                         .sy/" + R + "\n"
        a = a + E + "[37;1m" + "                         .yh+" + R + "\n"
        a = a + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "           " + E + "[34;1m" + "-+syyyo+-     " + E + "[37;1m" + " /+." + R + "\n"
        a = a + E + "[37;1m" + "         " + E + "[34;1m" + "+ddo/---/sdh/   " + E + "[37;1m" + " ym-" + R + "\n"
        a = a + E + "[37;1m" + "       " + E + "[34;1m" + "`hm+        `sms" + E + "[37;1m" + "   ym-```````.-." + R + "\n"
        a = a + E + "[37;1m" + "       " + E + "[34;1m" + "sm+           sm/ " + E + "[37;1m" + " ym-         +s" + R + "\n"
        a = a + E + "[37;1m" + "       " + E + "[34;1m" + "hm.           /mo " + E + "[37;1m" + " ym-         /h" + R + "\n"
        a = a + E + "[37;1m" + "       " + E + "[34;1m" + "omo           ym: " + E + "[37;1m" + " ym-       `os`" + R + "\n"
        a = a + E + "[37;1m" + "        " + E + "[34;1m" + "smo`       .ym+ " + E + "[37;1m" + "  ym-     .os-" + R + "\n"
        a = a + E + "[37;1m" + "     ``  " + E + "[34;1m" + ":ymy+///oyms- " + E + "[37;1m" + "   ym-  .+s+." + R + "\n"
        a = a + E + "[37;1m" + "   ..`     " + E + "[34;1m" + "`:+oo+/-`  " + E + "[37;1m" + "    -//oyo-" + R + "\n"
        a = a + E + "[37;1m" + " -:`                   .:oys/." + R + "\n"
        a = a + E + "[37;1m" + "+-               `./oyys/." + R + "\n"
        a = a + E + "[37;1m" + "h+`      `.-:+oyyyo/-`" + R + "\n"
        a = a + E + "[37;1m" + "`/ossssysso+/-.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "pnm linux") || startsWith(dn, "whpnm linux") {
        a = a + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + "               ``.---..` `--`" + R + "\n"
        a = a + E + "[38;5;33m" + "            ``.---........-:." + E + "[38;5;9m" + "-::`" + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + "           " + E + "[38;5;9m" + "./::-" + E + "[38;5;33m" + "........" + E + "[38;5;9m" + "--::.````" + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + "          " + E + "[38;5;9m" + ".:://:::" + E + "[38;5;33m" + "----" + E + "[38;5;9m" + "::::-.." + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + "          .." + E + "[38;5;9m" + "--:::::--::::++-" + E + "[38;5;33m" + ".`" + R + "\n"
        a = a + E + "[38;5;33m" + "  " + E + "[38;5;9m" + "`-:-`" + E + "[38;5;33m" + "   .-ohy+::" + E + "[38;5;9m" + "-:::" + E + "[38;5;33m" + "/sdmdd:." + E + "[38;5;9m" + "   `-:-" + R + "\n"
        a = a + E + "[38;5;9m" + "   .-:::" + E + "[38;5;33m" + "..." + E + "[38;5;15m" + "sNNmds$y" + E + "[38;5;33m" + "o/+" + E + "[38;5;15m" + "sy+NN$m" + E + "[38;5;33m" + "d+.`" + E + "[38;5;9m" + "-:::-." + R + "\n"
        a = a + E + "[38;5;9m" + "     `.-:-" + E + "[38;5;33m" + "./" + E + "[38;5;15m" + "dN" + E + "[38;5;33m" + "()" + E + "[38;5;15m" + "yyooosd" + E + "[38;5;33m" + "()" + E + "[38;5;15m" + "$m" + E + "[38;5;33m" + "dy" + E + "[38;5;9m" + "-.::-.`" + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + "      " + E + "[38;5;9m" + "`." + E + "[38;5;33m" + "-...-" + E + "[38;5;15m" + "+hNdyyyyyydmy" + E + "[38;5;33m" + ":......" + E + "[38;5;9m" + "`" + E + "[38;5;33m" + R + "\n"
        a = a + E + "[38;5;33m" + " ``..--.....-" + E + "[38;5;15m" + "yNNm" + E + "[38;5;202m" + "hssssh" + E + "[38;5;15m" + "mmdo" + E + "[38;5;33m" + ".........```" + R + "\n"
        a = a + E + "[38;5;33m" + "`-:://:....." + E + "[38;5;15m" + "hNNNNN" + E + "[38;5;202m" + "mddm" + E + "[38;5;15m" + "NNNmds" + E + "[38;5;33m" + ".....//::--`" + R + "\n"
        a = a + E + "[38;5;33m" + "  ```.:-..." + E + "[38;5;15m" + "oNNNNNNNNNNNNNNmd/" + E + "[38;5;33m" + "...:-.```" + R + "\n"
        a = a + E + "[38;5;33m" + "      ....." + E + "[38;5;15m" + "hNNNNNNNNNNNNNNmds" + E + "[38;5;33m" + "....`" + R + "\n"
        a = a + E + "[38;5;33m" + "      --..." + E + "[38;5;15m" + "hNNNNNNNNNNNNNNmdo" + E + "[38;5;33m" + "....." + R + "\n"
        a = a + E + "[38;5;33m" + "      .:..." + E + "[38;5;15m" + "/NNNNNNNNNNNNNNdd" + E + "[38;5;33m" + ":....`" + R + "\n"
        a = a + E + "[38;5;33m" + "       `-..." + E + "[38;5;15m" + "+mNNNNNNNNNNNmh" + E + "[38;5;33m" + ":...-." + R + "\n"
        a = a + E + "[38;5;33m" + "     " + E + "[38;5;202m" + ".:+o+/:-" + E + "[38;5;33m" + ":+oo+///++o+/:-" + E + "[38;5;202m" + ":/+ooo/:." + R + "\n"
        a = a + E + "[38;5;202m" + "       " + E + "[38;5;202m" + "+oo/:o-            +oooooso.`" + R + "\n"
        a = a + E + "[38;5;202m" + "       " + E + "[38;5;202m" + ".`   `             `/  .-//-" + R + "\n"
        emit a
    }
    if startsWith(dn, "source mage") || startsWith(dn, "source_mage") {
        a = a + E + "[34;1m" + E + "[37;1m" + "       :ymNMNho." + R + "\n"
        a = a + E + "[37;1m" + ".+sdmNMMMMMMMMMMy`" + R + "\n"
        a = a + E + "[37;1m" + ".-::/yMMMMMMMMMMMm-" + R + "\n"
        a = a + E + "[37;1m" + "      sMMMMMMMMMMMm/" + R + "\n"
        a = a + E + "[37;1m" + "     /NMMMMMMMMMMMMMm:" + R + "\n"
        a = a + E + "[37;1m" + "    .MMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[37;1m" + "    `MMMMMMMMMMMMMMMMMN." + R + "\n"
        a = a + E + "[37;1m" + "     NMMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[37;1m" + "     mMMMMMMMMMMMMMMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + "     hhMMMMMMMMMMMMMMMMMM." + R + "\n"
        a = a + E + "[37;1m" + "     .`/MMMMMMMMMMMMMMMMMs" + R + "\n"
        a = a + E + "[37;1m" + "        :mMMMMMMMMMMMMMMMN`" + R + "\n"
        a = a + E + "[37;1m" + "         `sMMMMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[37;1m" + "           /NMMMMMMMMMMMMMN`" + R + "\n"
        a = a + E + "[37;1m" + "             oMMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[37;1m" + "          ./sd.-hMMMMMMMMmmN`" + R + "\n"
        a = a + E + "[37;1m" + "      ./+oyyyh- `MMMMMMMMMmNh" + R + "\n"
        a = a + E + "[37;1m" + "                 sMMMMMMMMMmmo" + R + "\n"
        a = a + E + "[37;1m" + "                 `NMMMMMMMMMd:" + R + "\n"
        a = a + E + "[37;1m" + "                  -dMMMMMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + "                    -shmNMMms." + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu mate") || startsWith(dn, "ubuntu-mate") {
        a = a + E + "[32;1m" + E + "[32;1m" + "            .:/+oossssoo+/:.`" + R + "\n"
        a = a + E + "[32;1m" + "        `:+ssssssssssssssssss+:`" + R + "\n"
        a = a + E + "[32;1m" + "      -+sssssssssssssss" + E + "[37;1m" + "y" + E + "[32;1m" + "ssssssss+-" + R + "\n"
        a = a + E + "[32;1m" + "    .osssssssssssss" + E + "[37;1m" + "yy" + E + "[32;1m" + "ss" + E + "[37;1m" + "mMmh" + E + "[32;1m" + "ssssssso." + R + "\n"
        a = a + E + "[32;1m" + "   /sssssssss" + E + "[37;1m" + "ydmNNNmmd" + E + "[32;1m" + "s" + E + "[37;1m" + "mMMMMNdy" + E + "[32;1m" + "sssss/" + R + "\n"
        a = a + E + "[32;1m" + " `+ssssssss" + E + "[37;1m" + "hNNdy" + E + "[32;1m" + "sssssss" + E + "[37;1m" + "mMMMMNdy" + E + "[32;1m" + "ssssss+`" + R + "\n"
        a = a + E + "[32;1m" + " +sssssss" + E + "[37;1m" + "yNNh" + E + "[32;1m" + "ss" + E + "[37;1m" + "hmNNNNm" + E + "[32;1m" + "s" + E + "[37;1m" + "mMmh" + E + "[32;1m" + "s" + E + "[37;1m" + "ydy" + E + "[32;1m" + "sssssss+" + R + "\n"
        a = a + E + "[32;1m" + "-sssss" + E + "[37;1m" + "y" + E + "[32;1m" + "ss" + E + "[37;1m" + "Nm" + E + "[32;1m" + "ss" + E + "[37;1m" + "hNNh" + E + "[32;1m" + "ssssss" + E + "[37;1m" + "y" + E + "[32;1m" + "s" + E + "[37;1m" + "hh" + E + "[32;1m" + "ss" + E + "[37;1m" + "mMy" + E + "[32;1m" + "sssssss-" + R + "\n"
        a = a + E + "[32;1m" + "+ssss" + E + "[37;1m" + "yMNdy" + E + "[32;1m" + "ss" + E + "[37;1m" + "hMd" + E + "[32;1m" + "ssssssssss" + E + "[37;1m" + "hMd" + E + "[32;1m" + "ss" + E + "[37;1m" + "NN" + E + "[32;1m" + "sssssss+" + R + "\n"
        a = a + E + "[32;1m" + "sssss" + E + "[37;1m" + "yMMMMMmh" + E + "[32;1m" + "sssssssssssss" + E + "[37;1m" + "NM" + E + "[32;1m" + "ss" + E + "[37;1m" + "dMy" + E + "[32;1m" + "sssssss" + R + "\n"
        a = a + E + "[32;1m" + "sssss" + E + "[37;1m" + "yMMMMMmhy" + E + "[32;1m" + "ssssssssssss" + E + "[37;1m" + "NM" + E + "[32;1m" + "ss" + E + "[37;1m" + "dMy" + E + "[32;1m" + "sssssss" + R + "\n"
        a = a + E + "[32;1m" + "+ssss" + E + "[37;1m" + "yMNdy" + E + "[32;1m" + "ss" + E + "[37;1m" + "hMd" + E + "[32;1m" + "ssssssssss" + E + "[37;1m" + "hMd" + E + "[32;1m" + "ss" + E + "[37;1m" + "NN" + E + "[32;1m" + "sssssss+" + R + "\n"
        a = a + E + "[32;1m" + "-sssss" + E + "[37;1m" + "y" + E + "[32;1m" + "ss" + E + "[37;1m" + "Nm" + E + "[32;1m" + "ss" + E + "[37;1m" + "hNNh" + E + "[32;1m" + "ssssssss" + E + "[37;1m" + "dh" + E + "[32;1m" + "ss" + E + "[37;1m" + "mMy" + E + "[32;1m" + "sssssss-" + R + "\n"
        a = a + E + "[32;1m" + " +sssssss" + E + "[37;1m" + "yNNh" + E + "[32;1m" + "ss" + E + "[37;1m" + "hmNNNNm" + E + "[32;1m" + "s" + E + "[37;1m" + "mNmh" + E + "[32;1m" + "s" + E + "[37;1m" + "ymy" + E + "[32;1m" + "sssssss+" + R + "\n"
        a = a + E + "[32;1m" + "  +ssssssss" + E + "[37;1m" + "hNNdy" + E + "[32;1m" + "sssssss" + E + "[37;1m" + "mMMMMmhy" + E + "[32;1m" + "ssssss+" + R + "\n"
        a = a + E + "[32;1m" + "   /sssssssss" + E + "[37;1m" + "ydmNNNNmd" + E + "[32;1m" + "s" + E + "[37;1m" + "mMMMMNdh" + E + "[32;1m" + "sssss/" + R + "\n"
        a = a + E + "[32;1m" + "    .osssssssssssss" + E + "[37;1m" + "yy" + E + "[32;1m" + "ss" + E + "[37;1m" + "mMmdy" + E + "[32;1m" + "sssssso." + R + "\n"
        a = a + E + "[32;1m" + "      -+sssssssssssssss" + E + "[37;1m" + "y" + E + "[32;1m" + "ssssssss+-" + R + "\n"
        a = a + E + "[32;1m" + "        `:+ssssssssssssssssss+:`" + R + "\n"
        a = a + E + "[32;1m" + "            .:/+oossssoo+/:." + R + "\n"
        a = a + E + "[32;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "archstrike") {
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "                   *   " + R + "\n"
        a = a + E + "[38;5;8m" + "                  **." + R + "\n"
        a = a + E + "[38;5;8m" + "                 ****" + R + "\n"
        a = a + E + "[38;5;8m" + "                ******" + R + "\n"
        a = a + E + "[38;5;8m" + "                *******" + R + "\n"
        a = a + E + "[38;5;8m" + "              ** *******" + R + "\n"
        a = a + E + "[38;5;8m" + "             **** *******" + R + "\n"
        a = a + E + "[38;5;8m" + "            " + E + "[38;5;8m" + "****" + E + "[36;1m" + "_____" + E + "[38;5;8m" + "***" + E + "[36;1m" + "/" + E + "[38;5;8m" + "*" + R + "\n"
        a = a + E + "[38;5;8m" + "           ***" + E + "[36;1m" + "/" + E + "[38;5;8m" + "*******" + E + "[36;1m" + "//" + E + "[38;5;8m" + "***" + R + "\n"
        a = a + E + "[38;5;8m" + "          **" + E + "[36;1m" + "/" + E + "[38;5;8m" + "********" + E + "[36;1m" + "///" + E + "[38;5;8m" + "*" + E + "[36;1m" + "/" + E + "[38;5;8m" + "**" + R + "\n"
        a = a + E + "[38;5;8m" + "         **" + E + "[36;1m" + "/" + E + "[38;5;8m" + "*******" + E + "[36;1m" + "////" + E + "[38;5;8m" + "***" + E + "[36;1m" + "/" + E + "[38;5;8m" + "**" + R + "\n"
        a = a + E + "[38;5;8m" + "        **" + E + "[36;1m" + "/" + E + "[38;5;8m" + "****" + E + "[36;1m" + "//////.," + E + "[38;5;8m" + "****" + E + "[36;1m" + "/" + E + "[38;5;8m" + "**" + R + "\n"
        a = a + E + "[38;5;8m" + "       ***" + E + "[36;1m" + "/" + E + "[38;5;8m" + "*****" + E + "[36;1m" + "/////////" + E + "[38;5;8m" + "**" + E + "[36;1m" + "/" + E + "[38;5;8m" + "***" + R + "\n"
        a = a + E + "[38;5;8m" + "      ****" + E + "[36;1m" + "/" + E + "[38;5;8m" + "****    " + E + "[36;1m" + "/////" + E + "[38;5;8m" + "***" + E + "[36;1m" + "/" + E + "[38;5;8m" + "****" + R + "\n"
        a = a + E + "[38;5;8m" + "     ******" + E + "[36;1m" + "/" + E + "[38;5;8m" + "***  " + E + "[36;1m" + "////   " + E + "[38;5;8m" + "**" + E + "[36;1m" + "/" + E + "[38;5;8m" + "******" + R + "\n"
        a = a + E + "[38;5;8m" + "    ********" + E + "[36;1m" + "/" + E + "[38;5;8m" + "* " + E + "[36;1m" + "///      " + E + "[38;5;8m" + "*" + E + "[36;1m" + "/" + E + "[38;5;8m" + "********" + R + "\n"
        a = a + E + "[38;5;8m" + "  ,******     " + E + "[36;1m" + "// ______ /    " + E + "[38;5;8m" + "******," + R + "\n"
        emit a
    }
    if startsWith(dn, "asteroidos") {
        a = a + E + "[38;5;160m" + E + "[38;5;160m" + "                    ***" + R + "\n"
        a = a + E + "[38;5;160m" + E + "[38;5;160m" + "                   *****" + R + "\n"
        a = a + E + "[38;5;160m" + E + "[38;5;160m" + "                **********" + R + "\n"
        a = a + E + "[38;5;160m" + E + "[38;5;160m" + "              ***************" + R + "\n"
        a = a + E + "[38;5;160m" + E + "[38;5;160m" + "           *///****////****////." + R + "\n"
        a = a + E + "[38;5;160m" + E + "[38;5;208m" + "         (/////// /////// ///////(" + R + "\n"
        a = a + E + "[38;5;208m" + E + "[38;5;208m" + "      /(((((//*     //,     //((((((." + R + "\n"
        a = a + E + "[38;5;208m" + E + "[38;5;208m" + "    (((((((((((     (((        ((((((((" + R + "\n"
        a = a + E + "[38;5;208m" + E + "[38;5;208m" + " *(((((((((((((((((((((((        ((((((((" + R + "\n"
        a = a + E + "[38;5;208m" + E + "[38;5;202m" + "    (((((#(((((((#(((((        ((#(((((" + R + "\n"
        a = a + E + "[38;5;202m" + E + "[38;5;202m" + "     (#(#(#####(#(#,       ####(#(#" + R + "\n"
        a = a + E + "[38;5;202m" + E + "[38;5;202m" + "         #########        ########" + R + "\n"
        a = a + E + "[38;5;202m" + E + "[38;5;202m" + "           /########   ########" + R + "\n"
        a = a + E + "[38;5;202m" + E + "[38;5;214m" + "              #######%#######" + R + "\n"
        a = a + E + "[38;5;214m" + E + "[38;5;214m" + "                (#%%%%%%%#" + R + "\n"
        a = a + E + "[38;5;214m" + E + "[38;5;214m" + "                   %%%%%" + R + "\n"
        a = a + E + "[38;5;214m" + E + "[38;5;214m" + "                    %%%" + R + "\n"
        emit a
    }
    if startsWith(dn, "bunsenlabs") {
        a = a + E + "[37;1m" + E + "[37;1m" + "        `++" + R + "\n"
        a = a + E + "[37;1m" + "      -yMMs" + R + "\n"
        a = a + E + "[37;1m" + "    `yMMMMN`" + R + "\n"
        a = a + E + "[37;1m" + "   -NMMMMMMm." + R + "\n"
        a = a + E + "[37;1m" + "  :MMMMMMMMMN-" + R + "\n"
        a = a + E + "[37;1m" + " .NMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[37;1m" + " yMMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[37;1m" + "`MMMMMMNMMMMMMMN." + R + "\n"
        a = a + E + "[37;1m" + "-MMMMN+ /mMMMMMMy" + R + "\n"
        a = a + E + "[37;1m" + "-MMMm`   `dMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "`MMN.     .NMMMMM." + R + "\n"
        a = a + E + "[37;1m" + " hMy       yMMMMM`" + R + "\n"
        a = a + E + "[37;1m" + " -Mo       +MMMMN" + R + "\n"
        a = a + E + "[37;1m" + "  /o       +MMMMs" + R + "\n"
        a = a + E + "[37;1m" + "           +MMMN`" + R + "\n"
        a = a + E + "[37;1m" + "           hMMM:" + R + "\n"
        a = a + E + "[37;1m" + "          `NMM/" + R + "\n"
        a = a + E + "[37;1m" + "          +MN:" + R + "\n"
        a = a + E + "[37;1m" + "          mh." + R + "\n"
        a = a + E + "[37;1m" + "         -/" + R + "\n"
        emit a
    }
    if startsWith(dn, "elementary") {
        a = a + E + "[34;1m" + E + "[37;1m" + "         eeeeeeeeeeeeeeeee" + R + "\n"
        a = a + E + "[37;1m" + "      eeeeeeeeeeeeeeeeeeeeeee" + R + "\n"
        a = a + E + "[37;1m" + "    eeeee  eeeeeeeeeeee   eeeee" + R + "\n"
        a = a + E + "[37;1m" + "  eeee   eeeee       eee     eeee" + R + "\n"
        a = a + E + "[37;1m" + " eeee   eeee          eee     eeee" + R + "\n"
        a = a + E + "[37;1m" + "eee    eee            eee       eee" + R + "\n"
        a = a + E + "[37;1m" + "eee   eee            eee        eee" + R + "\n"
        a = a + E + "[37;1m" + "ee    eee           eeee       eeee" + R + "\n"
        a = a + E + "[37;1m" + "ee    eee         eeeee      eeeeee" + R + "\n"
        a = a + E + "[37;1m" + "ee    eee       eeeee      eeeee ee" + R + "\n"
        a = a + E + "[37;1m" + "eee   eeee   eeeeee      eeeee  eee" + R + "\n"
        a = a + E + "[37;1m" + "eee    eeeeeeeeee     eeeeee    eee" + R + "\n"
        a = a + E + "[37;1m" + " eeeeeeeeeeeeeeeeeeeeeeee    eeeee" + R + "\n"
        a = a + E + "[37;1m" + "  eeeeeeee eeeeeeeeeeee      eeee" + R + "\n"
        a = a + E + "[37;1m" + "    eeeee                 eeeee" + R + "\n"
        a = a + E + "[37;1m" + "      eeeeeee         eeeeeee" + R + "\n"
        a = a + E + "[37;1m" + "         eeeeeeeeeeeeeeeee" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_3(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "fedora_old") || startsWith(dn, "rfremix") {
        a = a + E + "[34;1m" + E + "[34;1m" + "          /:-------------:\\\\" + R + "\n"
        a = a + E + "[34;1m" + "       :-------------------::" + R + "\n"
        a = a + E + "[34;1m" + "     :-----------" + E + "[37;1m" + "/shhOHbmp" + E + "[34;1m" + "---:\\\\" + R + "\n"
        a = a + E + "[34;1m" + "   /-----------" + E + "[37;1m" + "omMMMNNNMMD  " + E + "[34;1m" + "---:" + R + "\n"
        a = a + E + "[34;1m" + "  :-----------" + E + "[37;1m" + "sMMMMNMNMP" + E + "[34;1m" + ".    ---:" + R + "\n"
        a = a + E + "[34;1m" + " :-----------" + E + "[37;1m" + ":MMMdP" + E + "[34;1m" + "-------    ---\\\\" + R + "\n"
        a = a + E + "[34;1m" + ",------------" + E + "[37;1m" + ":MMMd" + E + "[34;1m" + "--------    ---:" + R + "\n"
        a = a + E + "[34;1m" + ":------------" + E + "[37;1m" + ":MMMd" + E + "[34;1m" + "-------    .---:" + R + "\n"
        a = a + E + "[34;1m" + ":----    " + E + "[37;1m" + "oNMMMMMMMMMNho" + E + "[34;1m" + "     .----:" + R + "\n"
        a = a + E + "[34;1m" + ":--     ." + E + "[37;1m" + "+shhhMMMmhhy++" + E + "[34;1m" + "   .------/" + R + "\n"
        a = a + E + "[34;1m" + ":-    -------" + E + "[37;1m" + ":MMMd" + E + "[34;1m" + "--------------:" + R + "\n"
        a = a + E + "[34;1m" + ":-   --------" + E + "[37;1m" + "/MMMd" + E + "[34;1m" + "-------------;" + R + "\n"
        a = a + E + "[34;1m" + ":-    ------" + E + "[37;1m" + "/hMMMy" + E + "[34;1m" + "------------:" + R + "\n"
        a = a + E + "[34;1m" + ":--" + E + "[37;1m" + " :dMNdhhdNMMNo" + E + "[34;1m" + "------------;" + R + "\n"
        a = a + E + "[34;1m" + ":---" + E + "[37;1m" + ":sdNMMMMNds:" + E + "[34;1m" + "------------:" + R + "\n"
        a = a + E + "[34;1m" + ":------" + E + "[37;1m" + ":://:" + E + "[34;1m" + "-------------::" + R + "\n"
        a = a + E + "[34;1m" + ":---------------------://" + R + "\n"
        emit a
    }
    if startsWith(dn, "frugalware") {
        a = a + E + "[34;1m" + E + "[34;1m" + "          `++/::-.`" + R + "\n"
        a = a + E + "[34;1m" + "         /o+++++++++/::-.`" + R + "\n"
        a = a + E + "[34;1m" + "        `o+++++++++++++++o++/::-.`" + R + "\n"
        a = a + E + "[34;1m" + "        /+++++++++++++++++++++++oo++/:-.``" + R + "\n"
        a = a + E + "[34;1m" + "       .o+ooooooooooooooooooosssssssso++oo++/:-`" + R + "\n"
        a = a + E + "[34;1m" + "       ++osoooooooooooosssssssssssssyyo+++++++o:" + R + "\n"
        a = a + E + "[34;1m" + "      -o+ssoooooooooooosssssssssssssyyo+++++++s`" + R + "\n"
        a = a + E + "[34;1m" + "      o++ssoooooo++++++++++++++sssyyyyo++++++o:" + R + "\n"
        a = a + E + "[34;1m" + "     :o++ssoooooo" + E + "[37;1m" + "/-------------" + E + "[34;1m" + "+syyyyyo+++++oo" + R + "\n"
        a = a + E + "[34;1m" + "    `o+++ssoooooo" + E + "[37;1m" + "/-----" + E + "[34;1m" + "+++++ooosyyyyyyo++++os:" + R + "\n"
        a = a + E + "[34;1m" + "    /o+++ssoooooo" + E + "[37;1m" + "/-----" + E + "[34;1m" + "ooooooosyyyyyyyo+oooss" + R + "\n"
        a = a + E + "[34;1m" + "   .o++++ssooooos" + E + "[37;1m" + "/------------" + E + "[34;1m" + "syyyyyyhsosssy-" + R + "\n"
        a = a + E + "[34;1m" + "   ++++++ssooooss" + E + "[37;1m" + "/-----" + E + "[34;1m" + "+++++ooyyhhhhhdssssso" + R + "\n"
        a = a + E + "[34;1m" + "  -s+++++syssssss" + E + "[37;1m" + "/-----" + E + "[34;1m" + "yyhhhhhhhhhhhddssssy." + R + "\n"
        a = a + E + "[34;1m" + "  sooooooyhyyyyyh" + E + "[37;1m" + "/-----" + E + "[34;1m" + "hhhhhhhhhhhddddyssy+" + R + "\n"
        a = a + E + "[34;1m" + " :yooooooyhyyyhhhyyyyyyhhhhhhhhhhdddddyssy`" + R + "\n"
        a = a + E + "[34;1m" + " yoooooooyhyyhhhhhhhhhhhhhhhhhhhddddddysy/" + R + "\n"
        a = a + E + "[34;1m" + "-ysooooooydhhhhhhhhhhhddddddddddddddddssy" + R + "\n"
        a = a + E + "[34;1m" + " .-:/+osssyyyysyyyyyyyyyyyyyyyyyyyyyyssy:" + R + "\n"
        a = a + E + "[34;1m" + "       ``.-/+oosysssssssssssssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "               ``.:/+osyysssssssssssssh." + R + "\n"
        a = a + E + "[34;1m" + "                        `-:/+osyyssssyo" + R + "\n"
        a = a + E + "[34;1m" + "                                .-:+++`" + R + "\n"
        emit a
    }
    if startsWith(dn, "linux lite") || startsWith(dn, "linux_lite") {
        a = a + E + "[33;1m" + E + "[33;1m" + "          ,xXc" + R + "\n"
        a = a + E + "[33;1m" + "      .l0MMMMMO" + R + "\n"
        a = a + E + "[33;1m" + "   .kNMMMMMWMMMN," + R + "\n"
        a = a + E + "[33;1m" + "   KMMMMMMKMMMMMMo" + R + "\n"
        a = a + E + "[33;1m" + "  'MMMMMMNKMMMMMM:" + R + "\n"
        a = a + E + "[33;1m" + "  kMMMMMMOMMMMMMO" + R + "\n"
        a = a + E + "[33;1m" + " .MMMMMMX0MMMMMW." + R + "\n"
        a = a + E + "[33;1m" + " oMMMMMMxWMMMMM:" + R + "\n"
        a = a + E + "[33;1m" + " WMMMMMNkMMMMMO" + R + "\n"
        a = a + E + "[33;1m" + ":MMMMMMOXMMMMW" + R + "\n"
        a = a + E + "[33;1m" + ".0MMMMMxMMMMM;" + R + "\n"
        a = a + E + "[33;1m" + ":;cKMMWxMMMMO" + R + "\n"
        a = a + E + "[33;1m" + "'MMWMMXOMMMMl" + R + "\n"
        a = a + E + "[33;1m" + " kMMMMKOMMMMMX:" + R + "\n"
        a = a + E + "[33;1m" + " .WMMMMKOWMMM0c" + R + "\n"
        a = a + E + "[33;1m" + "  lMMMMMWO0MNd:'" + R + "\n"
        a = a + E + "[33;1m" + "   oollXMKXoxl;." + R + "\n"
        a = a + E + "[33;1m" + "     ':. .: .'" + R + "\n"
        a = a + E + "[33;1m" + "              .." + R + "\n"
        a = a + E + "[33;1m" + "                ." + R + "\n"
        emit a
    }
    if startsWith(dn, "linux mint") || startsWith(dn, "linuxmint") || startsWith(dn, "mint") {
        a = a + E + "[32;1m" + E + "[37;1m" + "             ...-:::::-..." + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "          .-MMMMMMMMMMMMMMM-." + R + "\n"
        a = a + E + "[37;1m" + "      .-MMMM" + E + "[32;1m" + "`..-:::::::-..`" + E + "[37;1m" + "MMMM-." + R + "\n"
        a = a + E + "[37;1m" + "    .:MMMM" + E + "[32;1m" + ".:MMMMMMMMMMMMMMM:." + E + "[37;1m" + "MMMM:." + R + "\n"
        a = a + E + "[37;1m" + "   -MMM" + E + "[32;1m" + "-M---MMMMMMMMMMMMMMMMMMM." + E + "[37;1m" + "MMM-" + R + "\n"
        a = a + E + "[37;1m" + " `:MMM" + E + "[32;1m" + ":MM`  :MMMM:....::-...-MMMM:" + E + "[37;1m" + "MMM:`" + R + "\n"
        a = a + E + "[37;1m" + " :MMM" + E + "[32;1m" + ":MMM`  :MM:`  ``    ``  `:MMM:" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + ".MMM" + E + "[32;1m" + ".MMMM`  :MM.  -MM.  .MM-  `MMMM." + E + "[37;1m" + "MMM." + R + "\n"
        a = a + E + "[37;1m" + ":MMM" + E + "[32;1m" + ":MMMM`  :MM.  -MM-  .MM:  `MMMM-" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + ":MMM" + E + "[32;1m" + ":MMMM`  :MM.  -MM-  .MM:  `MMMM:" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + ":MMM" + E + "[32;1m" + ":MMMM`  :MM.  -MM-  .MM:  `MMMM-" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + ".MMM" + E + "[32;1m" + ".MMMM`  :MM:--:MM:--:MM:  `MMMM." + E + "[37;1m" + "MMM." + R + "\n"
        a = a + E + "[37;1m" + " :MMM" + E + "[32;1m" + ":MMM-  `-MMMMMMMMMMMM-`  -MMM-" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + "  :MMM" + E + "[32;1m" + ":MMM:`                `:MMM:" + E + "[37;1m" + "MMM:" + R + "\n"
        a = a + E + "[37;1m" + "   .MMM" + E + "[32;1m" + ".MMMM:--------------:MMMM." + E + "[37;1m" + "MMM." + R + "\n"
        a = a + E + "[37;1m" + "     '-MMMM" + E + "[32;1m" + ".-MMMMMMMMMMMMMMM-." + E + "[37;1m" + "MMMM-'" + R + "\n"
        a = a + E + "[37;1m" + "       '.-MMMM" + E + "[32;1m" + "``--:::::--``" + E + "[37;1m" + "MMMM-.'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "            '-MMMMMMMMMMMMM-'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "               ``-:::::-``" + R + "\n"
        emit a
    }
    if startsWith(dn, "live raizo") || startsWith(dn, "live_raizo") {
        a = a + E + "[33;1m" + E + "[33;1m" + "             `......`" + R + "\n"
        a = a + E + "[33;1m" + "        -+shmNMMMMMMNmhs/." + R + "\n"
        a = a + E + "[33;1m" + "     :smMMMMMmmhyyhmmMMMMMmo-" + R + "\n"
        a = a + E + "[33;1m" + "   -hMMMMd+:. `----` .:odMMMMh-" + R + "\n"
        a = a + E + "[33;1m" + " `hMMMN+. .odNMMMMMMNdo. .yMMMMs`" + R + "\n"
        a = a + E + "[33;1m" + " hMMMd. -dMMMMmdhhdNMMMNh` .mMMMh" + R + "\n"
        a = a + E + "[33;1m" + "oMMMm` :MMMNs.:sddy:-sMMMN- `NMMM+" + R + "\n"
        a = a + E + "[33;1m" + "mMMMs  dMMMo sMMMMMMd yMMMd  sMMMm" + R + "\n"
        a = a + E + "[33;1m" + "----`  .---` oNMMMMMh `---.  .----" + R + "\n"
        a = a + E + "[33;1m" + "              .sMMy:" + R + "\n"
        a = a + E + "[33;1m" + "               /MM/" + R + "\n"
        a = a + E + "[33;1m" + "              +dMMms." + R + "\n"
        a = a + E + "[33;1m" + "             hMMMMMMN" + R + "\n"
        a = a + E + "[33;1m" + "            `dMMMMMMm:" + R + "\n"
        a = a + E + "[33;1m" + "      .+ss+sMNysMMoomMd+ss+." + R + "\n"
        a = a + E + "[33;1m" + "     +MMMMMMN` +MM/  hMMMMMNs" + R + "\n"
        a = a + E + "[33;1m" + "     sMMMMMMm-hNMMMd-hMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "      :yddh+`hMMMMMMN :yddy/`" + R + "\n"
        a = a + E + "[33;1m" + "             .hMMMMd:" + R + "\n"
        a = a + E + "[33;1m" + "               `..`" + R + "\n"
        emit a
    }
    if startsWith(dn, "peppermint") {
        a = a + E + "[31;1m" + E + "[31;1m" + "               PPPPPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "           PPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "         PPPP" + E + "[38;5;15m" + "MMMMMMMMMM" + E + "[31;1m" + "PPPPPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "       PPPPPPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPPPPPP" + E + "[38;5;15m" + "MMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "     PPPPPPPPPPPP" + E + "[38;5;15m" + "MMMMMM" + E + "[31;1m" + "PPPPPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "    PPPPPPPPPPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPP" + E + "[38;5;15m" + "M" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MMMMMMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "   PP" + E + "[38;5;15m" + "MMMM" + E + "[31;1m" + "PPPPPPPPPP" + E + "[38;5;15m" + "MMM" + E + "[31;1m" + "PPPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "   P" + E + "[38;5;15m" + "MMMMMMMMMM" + E + "[31;1m" + "PPPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPP" + E + "[38;5;15m" + "MMMMMM" + E + "[31;1m" + "PPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "  P" + E + "[38;5;15m" + "MMMMMMMMMMMM" + E + "[31;1m" + "PPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PP" + E + "[38;5;15m" + "M" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "  P" + E + "[38;5;15m" + "MMMMMMMMMMMMMMMM" + E + "[31;1m" + "PP" + E + "[38;5;15m" + "M" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MMM" + E + "[31;1m" + "PPPPPPPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "  P" + E + "[38;5;15m" + "MMM" + E + "[31;1m" + "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPP" + E + "[38;5;15m" + "MMMMM" + E + "[31;1m" + "P" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "  PPPPPPPPPPPPPPPP" + E + "[38;5;15m" + "MMM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "M" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MMMMMMMMMMMMMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "  PPPPPPPPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPP" + E + "[38;5;15m" + "MMMMMMMMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "   PPPPPPPP" + E + "[38;5;15m" + "MMMMMM" + E + "[31;1m" + "PPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPPP" + E + "[38;5;15m" + "MMMMMMMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "   PPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPPPP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPPPPPPP" + E + "[38;5;15m" + "MMMM" + E + "[31;1m" + "PP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "    PP" + E + "[38;5;15m" + "MMMMMMMMM" + E + "[31;1m" + "P" + E + "[38;5;15m" + "M" + E + "[31;1m" + "PPPP" + E + "[38;5;15m" + "MMMMMM" + E + "[31;1m" + "PPPPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "     PP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPPPPP" + E + "[38;5;15m" + "MMMMMM" + E + "[31;1m" + "PPPPPPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "       PP" + E + "[38;5;15m" + "MMMM" + E + "[31;1m" + "PPPPPPPPP" + E + "[38;5;15m" + "MMMMMMM" + E + "[31;1m" + "PPPPPPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "         PP" + E + "[38;5;15m" + "MM" + E + "[31;1m" + "PPPPPPPP" + E + "[38;5;15m" + "MMMMMMMMMM" + E + "[31;1m" + "PPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "           PPPPPPPPPP" + E + "[38;5;15m" + "MMMMMMMM" + E + "[31;1m" + "PPPP" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "               PPPPPPPPPPPPPP" + R + "\n"
        emit a
    }
    if startsWith(dn, "redhat_old") || startsWith(dn, "rhel_old") {
        a = a + E + "[31;1m" + E + "[31;1m" + "             `.-..........`" + R + "\n"
        a = a + E + "[31;1m" + "            `////////::.`-/." + R + "\n"
        a = a + E + "[31;1m" + "            -: ....-////////." + R + "\n"
        a = a + E + "[31;1m" + "            //:-::///////////`" + R + "\n"
        a = a + E + "[31;1m" + "     `--::: `-://////////////:" + R + "\n"
        a = a + E + "[31;1m" + "     //////-    ``.-:///////// .`" + R + "\n"
        a = a + E + "[31;1m" + "     `://////:-.`    :///////::///:`" + R + "\n"
        a = a + E + "[31;1m" + "       .-/////////:---/////////////:" + R + "\n"
        a = a + E + "[31;1m" + "          .-://////////////////////." + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "         yMN+`.-" + E + "[31;1m" + "::///////////////-`" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "      .-`:NMMNMs`  `..-------..`" + R + "\n"
        a = a + E + "[37;1m" + "       MN+/mMMMMMhoooyysshsss" + R + "\n"
        a = a + E + "[37;1m" + "MMM    MMMMMMMMMMMMMMyyddMMM+" + R + "\n"
        a = a + E + "[37;1m" + " MMMM   MMMMMMMMMMMMMNdyNMMh`     hyhMMM" + R + "\n"
        a = a + E + "[37;1m" + "  MMMMMMMMMMMMMMMMyoNNNMMM+.   MMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "   MMNMMMNNMMMMMNM+ mhsMNyyyyMNMMMMsMM" + R + "\n"
        emit a
    }
    if startsWith(dn, "scientific") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                 =/;;/-" + R + "\n"
        a = a + E + "[34;1m" + "                +:    //" + R + "\n"
        a = a + E + "[34;1m" + "               /;      /;" + R + "\n"
        a = a + E + "[34;1m" + "              -X        H." + R + "\n"
        a = a + E + "[34;1m" + ".//;;;:;;-,   X=        :+   .-;:=;:;#;." + R + "\n"
        a = a + E + "[34;1m" + "M-       ,=;;;#:,      ,:#;;:=,       ,@" + R + "\n"
        a = a + E + "[34;1m" + ":#           :#.=/++++/=.$=           #=" + R + "\n"
        a = a + E + "[34;1m" + " ,#;         #/:+/;,,/++:+/         ;+." + R + "\n"
        a = a + E + "[34;1m" + "   ,+/.    ,;@+,        ,#H;,    ,/+," + R + "\n"
        a = a + E + "[34;1m" + "      ;+;;/= @.  " + E + "[31;1m" + ".H" + E + "[37;1m" + "#" + E + "[31;1m" + "#X   " + E + "[34;1m" + "-X :///+;" + R + "\n"
        a = a + E + "[34;1m" + "      ;+=;;;.@,  " + E + "[37;1m" + ".X" + E + "[31;1m" + "M" + E + "[37;1m" + "@$.  " + E + "[34;1m" + "=X.//;=#/." + R + "\n"
        a = a + E + "[34;1m" + "   ,;:      :@#=        =$H:     .+#-" + R + "\n"
        a = a + E + "[34;1m" + " ,#=         #;-///==///-//         =#," + R + "\n"
        a = a + E + "[34;1m" + ";+           :#-;;;:;;;;-X-           +:" + R + "\n"
        a = a + E + "[34;1m" + "@-      .-;;;;M-        =M/;;;-.      -X" + R + "\n"
        a = a + E + "[34;1m" + " :;;::;;-.    #-        :+    ,-;;-;:==" + R + "\n"
        a = a + E + "[34;1m" + "              ,X        H." + R + "\n"
        a = a + E + "[34;1m" + "               ;/      #=" + R + "\n"
        a = a + E + "[34;1m" + "                //    +;" + R + "\n"
        a = a + E + "[34;1m" + "                 '////'" + R + "\n"
        emit a
    }
    if startsWith(dn, "sharklinux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                              `:shd/" + R + "\n"
        a = a + E + "[34;1m" + "                          `:yNMMMMs" + R + "\n"
        a = a + E + "[34;1m" + "                       `-smMMMMMMN." + R + "\n"
        a = a + E + "[34;1m" + "                     .+dNMMMMMMMMs" + R + "\n"
        a = a + E + "[34;1m" + "                   .smNNMMMMMMMMm`" + R + "\n"
        a = a + E + "[34;1m" + "                 .sNNNNNNNMMMMMM/" + R + "\n"
        a = a + E + "[34;1m" + "               `omNNNNNNNMMMMMMm" + R + "\n"
        a = a + E + "[34;1m" + "              /dNNNNNNNNMMMMMMM+" + R + "\n"
        a = a + E + "[34;1m" + "            .yNNNNNNNNNMMMMMMMN`" + R + "\n"
        a = a + E + "[34;1m" + "           +mNNNNNNNNNMMMMMMMMh" + R + "\n"
        a = a + E + "[34;1m" + "         .hNNNNNNNNNNMMMMMMMMMs" + R + "\n"
        a = a + E + "[34;1m" + "        +mMNNNNNNNNMMMMMMMMMMMs" + R + "\n"
        a = a + E + "[34;1m" + "      .hNMMNNNNMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "    .oNNNNNNNNNNMMMMMMMMMMMMMMMo" + R + "\n"
        a = a + E + "[34;1m" + " `:+syyssoo++++ooooossssssssssso:" + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu_old") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                         ./+o+-" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "                 yyyyy- " + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "              " + E + "[37;1m" + "://+//////" + E + "[31;1m" + "-yyyyyyo" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "          .++ " + E + "[37;1m" + ".:/++++++/-" + E + "[31;1m" + ".+sss/`" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "        .:++o:  " + E + "[37;1m" + "/++++++++/:--:/-" + R + "\n"
        a = a + E + "[37;1m" + E + "[33;1m" + "       o:+o+:++." + E + "[37;1m" + "`..```.-/oo+++++/" + R + "\n"
        a = a + E + "[37;1m" + E + "[33;1m" + "      .:+o:+o/." + E + "[37;1m" + "          `+sssoo+/" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + " .++/+:" + E + "[33;1m" + "+oo+o:`" + E + "[37;1m" + "             /sssooo." + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "/+++//+:" + E + "[33;1m" + "`oo+o" + E + "[37;1m" + "               /::--:." + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "+/+o+++" + E + "[33;1m" + "`o++o" + E + "[31;1m" + "               ++////." + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + " .++.o+" + E + "[33;1m" + "++oo+:`" + E + "[31;1m" + "             /dddhhh." + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "      .+.o+oo:." + E + "[31;1m" + "          `oddhhhh+" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "       +.++o+o`" + E + "[31;1m" + "`-````.:ohdhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "        `:o+++ " + E + "[31;1m" + "`ohhhhhhhhyo++os:" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "          .o:" + E + "[31;1m" + "`.syhhhhhhh/" + E + "[33;1m" + ".oo++o`" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "              /osyyyyyyo" + E + "[33;1m" + "++ooo+++/" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "                  ````` " + E + "[33;1m" + "+oo+++o:" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "                         `oo++." + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_4(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "univention") {
        a = a + E + "[31;1m" + E + "[31;1m" + "         ./osssssssssssssssssssssso+-" + R + "\n"
        a = a + E + "[31;1m" + "       `ohhhhhhhhhhhhhhhhhhhhhhhhhhhhy:" + R + "\n"
        a = a + E + "[31;1m" + "       shhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh-" + R + "\n"
        a = a + E + "[31;1m" + "   `-//" + E + "[37;1m" + "sssss" + E + "[31;1m" + "/hhhhhhhhhhhhhh+" + E + "[37;1m" + "s" + E + "[31;1m" + ".hhhhhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + " .ohhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sss" + E + "[31;1m" + "+hhhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + ".yhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "ssss" + E + "[31;1m" + ":hhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "sssss" + E + "[31;1m" + ".hhhhhhhhhhhhhh." + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhy" + E + "[37;1m" + "ssssss" + E + "[31;1m" + "+yhhhhhhhhhhy/" + E + "[37;1m" + "ssssss" + E + "[31;1m" + "yhhhhh+" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhh:" + E + "[37;1m" + "sssssss" + E + "[31;1m" + ":hhhhhhh+" + E + "[37;1m" + ".ssssssss" + E + "[31;1m" + "yhhhhy." + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhhh+`" + E + "[37;1m" + "ssssssssssssssss" + E + "[31;1m" + "hh" + E + "[37;1m" + "sssss" + E + "[31;1m" + "yhhho`" + R + "\n"
        a = a + E + "[31;1m" + "+hhhhhhhhhs+" + E + "[37;1m" + "ssssssssssss" + E + "[31;1m" + "+hh+" + E + "[37;1m" + "sssss" + E + "[31;1m" + "/:-`" + R + "\n"
        a = a + E + "[31;1m" + "-hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhho" + R + "\n"
        a = a + E + "[31;1m" + " :yhhhhhhhhhhhhhhhhhhhhhhhhhhhh+`" + R + "\n"
        a = a + E + "[31;1m" + "   -+ossssssssssssssssssssss+:`" + R + "\n"
        emit a
    }
    if startsWith(dn, "windows 11") || startsWith(dn, "windows11") {
        a = a + E + "[36;1m" + E + "[36;1m" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        a = a + E + "[36;1m" + "################  ################" + R + "\n"
        emit a
    }
    if startsWith(dn, "windows 10") || startsWith(dn, "windows10") || startsWith(dn, "windows8") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                                ..," + R + "\n"
        a = a + E + "[36;1m" + "                    ....,,:;+ccllll" + R + "\n"
        a = a + E + "[36;1m" + "      ...,,+:;  cllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + ",cclllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "llllllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "`'ccllllllllll  lllllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "       `' \\\\*::  :ccllllllllllllllll" + R + "\n"
        a = a + E + "[36;1m" + "                       ````''*::cll" + R + "\n"
        a = a + E + "[36;1m" + "                                 ``" + R + "\n"
        emit a
    }
    if startsWith(dn, "almalinux") {
        a = a + E + "[31;1m" + E + "[31;1m" + "         'c:." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "        lkkkx, ..       " + E + "[33;1m" + "..   ,cc," + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "        okkkk:ckkx'  " + E + "[33;1m" + ".lxkkx.okkkkd" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "        .:llcokkx'  " + E + "[33;1m" + ":kkkxkko:xkkd," + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "      .xkkkkdood:  " + E + "[33;1m" + ";kx,  .lkxlll;" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "       xkkx.       " + E + "[33;1m" + "xk'     xkkkkk:" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "       'xkx.       " + E + "[33;1m" + "xd      .....,." + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "      .. " + E + "[31;1m" + ":xkl'     " + E + "[33;1m" + ":c      ..''.." + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "    .dkx'  " + E + "[31;1m" + ".:ldl:'. " + E + "[33;1m" + "'  " + E + "[32;1m" + "':lollldkkxo;" + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "  .''lkkko'                     " + E + "[32;1m" + "ckkkx." + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "'xkkkd:kkd.       ..  " + E + "[36;1m" + ";'        " + E + "[32;1m" + ":kkxo." + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + ",xkkkd;kk'      ,d;    " + E + "[36;1m" + "ld.   " + E + "[32;1m" + "':dkd::cc," + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + " .,,.;xkko'.';lxo.      " + E + "[36;1m" + "dx,  " + E + "[32;1m" + ":kkk'xkkkkc" + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "     'dkkkkkxo:.        " + E + "[36;1m" + ";kx  " + E + "[32;1m" + ".kkk:;xkkd." + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "       .....   " + E + "[36;1m" + ".;dk:.   " + E + "[36;1m" + "lkk.  " + E + "[32;1m" + ":;," + R + "\n"
        a = a + E + "[32;1m" + "             " + E + "[36;1m" + ":kkkkkkkdoxkkx" + R + "\n"
        a = a + E + "[36;1m" + "              ,c,,;;;:xkkd." + R + "\n"
        a = a + E + "[36;1m" + "                ;kkkkl..." + R + "\n"
        a = a + E + "[36;1m" + "                ;kkkkl" + R + "\n"
        a = a + E + "[36;1m" + "                 ,od;" + R + "\n"
        emit a
    }
    if startsWith(dn, "instantos") {
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "     'cx0XWWMMWNKOd:'." + R + "\n"
        a = a + E + "[34;1m" + "  .;kNMMMMMMMMMMMMMWNKd'" + R + "\n"
        a = a + E + "[34;1m" + " 'kNMMMMMMWNNNWMMMMMMMMXo." + R + "\n"
        a = a + E + "[34;1m" + ",0MMMMMW0o;'..,:dKWMMMMMWx." + R + "\n"
        a = a + E + "[34;1m" + "OMMMMMXl.        .xNMMMMMNo" + R + "\n"
        a = a + E + "[34;1m" + "WMMMMNl           .kWWMMMMO'" + R + "\n"
        a = a + E + "[34;1m" + "MMMMMX;            oNWMMMMK," + R + "\n"
        a = a + E + "[34;1m" + "NMMMMWo           .OWMMMMMK," + R + "\n"
        a = a + E + "[34;1m" + "kWMMMMNd.        ,kWMMMMMMK," + R + "\n"
        a = a + E + "[34;1m" + "'kWMMMMWXxl:;;:okNMMMMMMMMK," + R + "\n"
        a = a + E + "[34;1m" + " .oXMMMMMMMWWWMMMMMMMMMMMMK," + R + "\n"
        a = a + E + "[34;1m" + "   'oKWMMMMMMMMMMMMMMMMMMMK," + R + "\n"
        a = a + E + "[34;1m" + "     .;lxOKXXXXXXXXXXXXXXXO;......" + R + "\n"
        a = a + E + "[34;1m" + "          ................,d0000000kd:." + R + "\n"
        a = a + E + "[34;1m" + "                          .kMMMMMMMMMW0;" + R + "\n"
        a = a + E + "[34;1m" + "                          .kMMMMMMMMMMMX" + R + "\n"
        a = a + E + "[34;1m" + "                          .xMMMMMMMMMMMW" + R + "\n"
        a = a + E + "[34;1m" + "                           cXMMMMMMMMMM0" + R + "\n"
        a = a + E + "[34;1m" + "                            :0WMMMMMMNx," + R + "\n"
        a = a + E + "[34;1m" + "                             .o0NMWNOc." + R + "\n"
        emit a
    }
    if startsWith(dn, "archcraft") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                   -m:" + R + "\n"
        a = a + E + "[36;1m" + "                  :NMM+      .+" + R + "\n"
        a = a + E + "[36;1m" + "                 +MMMMMo    -NMy" + R + "\n"
        a = a + E + "[36;1m" + "                sMMMMMMMy  -MMMMh`" + R + "\n"
        a = a + E + "[36;1m" + "               yMMMMMMMMMd` oMMMMd`" + R + "\n"
        a = a + E + "[36;1m" + "             `dMMMMMMMMMMMm. /MMMMm-" + R + "\n"
        a = a + E + "[36;1m" + "            .mMMMMMm-dMMMMMN- :NMMMN:" + R + "\n"
        a = a + E + "[36;1m" + "           -NMMMMMd`  yMMMMMN: .mMMMM/" + R + "\n"
        a = a + E + "[36;1m" + "          :NMMMMMy     sMMMMMM+ `dMMMMo" + R + "\n"
        a = a + E + "[36;1m" + "         +MMMMMMs       +MMMMMMs `hMMMMy" + R + "\n"
        a = a + E + "[36;1m" + "        oMMMMMMMds-      :NMMMMMy  sMMMMh`" + R + "\n"
        a = a + E + "[36;1m" + "       yMMMMMNoydMMmo`    -NMMMMMd` +MMMMd." + R + "\n"
        a = a + E + "[36;1m" + "     `dMMMMMN-   `:yNNs`   .mMMMMMm. /MMMMm-" + R + "\n"
        a = a + E + "[36;1m" + "    .mMMMMMm.        :hN/   `dMMMMMN- -NMMMN:" + R + "\n"
        a = a + E + "[36;1m" + "   -NMMMMMd`           -hh`  `yMMMMMN: .mMMMM/" + R + "\n"
        a = a + E + "[36;1m" + "  :NMMMMMy         `s`   :h.   oMMMMMM+ `-----" + R + "\n"
        a = a + E + "[36;1m" + " +MMMMMMo         .dMm.   `o.   +MMMMMMo" + R + "\n"
        a = a + E + "[36;1m" + "sMMMMMM+         .mMMMN:    :`   :NMMMMMy" + R + "\n"
        emit a
    }
    if startsWith(dn, "arcolinux") {
        a = a + E + "[37;1m" + E + "[34;1m" + "                    /-" + R + "\n"
        a = a + E + "[34;1m" + "                   ooo:" + R + "\n"
        a = a + E + "[34;1m" + "                  yoooo/" + R + "\n"
        a = a + E + "[34;1m" + "                 yooooooo" + R + "\n"
        a = a + E + "[34;1m" + "                yooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "               yooooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "             .yooooooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "            .oooooooooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "           .oooooooarcoooooooo" + R + "\n"
        a = a + E + "[34;1m" + "          .ooooooooo-oooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "         .ooooooooo-  oooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "        :ooooooooo.    :ooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "       :ooooooooo.      :ooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "      :oooarcooo         .oooarcooo" + R + "\n"
        a = a + E + "[34;1m" + "     :ooooooooy           .ooooooooo" + R + "\n"
        a = a + E + "[34;1m" + "    :ooooooooo   " + E + "[37;1m" + "/ooooooooooooooooooo" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "   :ooooooooo      " + E + "[37;1m" + ".-ooooooooooooooooo." + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "  ooooooooo-             " + E + "[37;1m" + "-ooooooooooooo." + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + " ooooooooo-                 " + E + "[37;1m" + ".-oooooooooo." + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "ooooooooo.                     " + E + "[37;1m" + "-ooooooooo" + E + "[34;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "archmerge") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                    y:" + R + "\n"
        a = a + E + "[36;1m" + "                  sMN-" + R + "\n"
        a = a + E + "[36;1m" + "                 +MMMm`" + R + "\n"
        a = a + E + "[36;1m" + "                /MMMMMd`" + R + "\n"
        a = a + E + "[36;1m" + "               :NMMMMMMy" + R + "\n"
        a = a + E + "[36;1m" + "              -NMMMMMMMMs" + R + "\n"
        a = a + E + "[36;1m" + "             .NMMMMMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "            .mMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "            oNMMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "          `+:-+NMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "          .sNMNhNMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[36;1m" + "        `hho/sNMMMMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[36;1m" + "       `.`omMMmMMMMMMMMMMMMMMMM+" + R + "\n"
        a = a + E + "[36;1m" + "      .mMNdshMMMMd+::oNMMMMMMMMMo" + R + "\n"
        a = a + E + "[36;1m" + "     .mMMMMMMMMM+     `yMMMMMMMMMs" + R + "\n"
        a = a + E + "[36;1m" + "    .NMMMMMMMMM/        yMMMMMMMMMy" + R + "\n"
        a = a + E + "[36;1m" + "   -NMMMMMMMMMh         `mNMMMMMMMMd`" + R + "\n"
        a = a + E + "[36;1m" + "  /NMMMNds+:.`             `-/oymMMMm." + R + "\n"
        a = a + E + "[36;1m" + " +Mmy/.                          `:smN:" + R + "\n"
        a = a + E + "[36;1m" + "/+.                                  -o." + R + "\n"
        emit a
    }
    if startsWith(dn, "blackarch") {
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
    if startsWith(dn, "bluelight") {
        a = a + E + "[37;1m" + E + "[37;1m" + "              oMMNMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "              oMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "              oMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "              oMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "              -+++++++++++++++++++++++mM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "             ```````````````````````.." + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "           ```````````````````````...." + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "         ```````````````````````......" + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "       ```````````````````````........" + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "     ```````````````````````.........." + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "   ```````````````````````............" + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + ".::::::::::::::::::::::-.............." + E + "[37;1m" + "dM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + " `-+yyyyyyyyyyyyyyyyyyyo............" + E + "[37;1m" + "+mMM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "     -+yyyyyyyyyyyyyyyyo.........." + E + "[37;1m" + "+mMMMM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "        ./syyyyyyyyyyyyo........" + E + "[37;1m" + "+mMMMMMM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "           ./oyyyyyyyyyo......" + E + "[37;1m" + "+mMMMMMMMM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "              omdyyyyyyo...." + E + "[37;1m" + "+mMMMMMMMMMM" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "              " + E + "[37;1m" + "oMMM" + E + "[34;1m" + "mdhyyo.." + E + "[37;1m" + "+mMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "              oNNNNNNm" + E + "[34;1m" + "dso" + E + "[37;1m" + "mMMMMMMMMMMMMMM" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_5(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "calculate") {
        a = a + E + "[37;1m" + E + "[37;1m" + "                              ......" + R + "\n"
        a = a + E + "[37;1m" + "                           ,,+++++++,." + R + "\n"
        a = a + E + "[37;1m" + "                         .,,,....,,," + E + "[33;1m" + "+**+,,." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                       ............," + E + "[33;1m" + "++++,,," + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                      ..............." + R + "\n"
        a = a + E + "[37;1m" + "                    ......,,,........" + R + "\n"
        a = a + E + "[37;1m" + "                  .....+*#####+,,,*+." + R + "\n"
        a = a + E + "[37;1m" + "              .....,*###############,..,,,,,,.." + R + "\n"
        a = a + E + "[37;1m" + "           ......,*#################*..,,,,,..,,,.." + R + "\n"
        a = a + E + "[37;1m" + "         .,,....*####################+***+,,,,...,++," + R + "\n"
        a = a + E + "[37;1m" + "       .,,..,..*#####################*," + R + "\n"
        a = a + E + "[37;1m" + "     ,+,.+*..*#######################." + R + "\n"
        a = a + E + "[37;1m" + "   ,+,,+*+..,########################*" + R + "\n"
        a = a + E + "[37;1m" + ".,++++++.  ..+##**###################+" + R + "\n"
        a = a + E + "[37;1m" + ".....      ..+##***#################*." + R + "\n"
        a = a + E + "[37;1m" + "           .,.*#*****##############*." + R + "\n"
        a = a + E + "[37;1m" + "           ..,,*********#####****+." + R + "\n"
        a = a + E + "[37;1m" + "     " + E + "[33;1m" + ".,++*****+++" + E + "[37;1m" + "*****************" + E + "[33;1m" + "+++++,." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "      " + E + "[33;1m" + ",++++++**+++++" + E + "[37;1m" + "***********" + E + "[33;1m" + "+++++++++," + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "     " + E + "[33;1m" + ".,,,,++++,..  .,,,,,.....,+++,.,," + E + "[37;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "cleanjaro") {
        a = a + E + "[37;1m" + E + "[37;1m" + "███████▌ ████████████████" + R + "\n"
        a = a + E + "[37;1m" + "███████▌ ████████████████" + R + "\n"
        a = a + E + "[37;1m" + "███████▌ ████████████████" + R + "\n"
        a = a + E + "[37;1m" + "███████▌" + R + "\n"
        a = a + E + "[37;1m" + "███████▌" + R + "\n"
        a = a + E + "[37;1m" + "███████▌" + R + "\n"
        a = a + E + "[37;1m" + "███████▌" + R + "\n"
        a = a + E + "[37;1m" + "███████▌" + R + "\n"
        a = a + E + "[37;1m" + "█████████████████████████" + R + "\n"
        a = a + E + "[37;1m" + "█████████████████████████" + R + "\n"
        a = a + E + "[37;1m" + "█████████████████████████" + R + "\n"
        a = a + E + "[37;1m" + "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀" + R + "\n"
        emit a
    }
    if startsWith(dn, "dragonfly") {
        a = a + E + "[31;1m" + E + "[37;1m" + ",--,           " + E + "[31;1m" + "|           " + E + "[37;1m" + ",--," + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "|   `-,       " + E + "[31;1m" + ",^,       " + E + "[37;1m" + ",-'   |" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + " `,    `-,   " + E + "[33;1m" + "(/ \\)   " + E + "[37;1m" + ",-'    ,'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "   `-,    `-," + E + "[31;1m" + "/   \\" + E + "[37;1m" + ",-'    ,-'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "      `------" + E + "[31;1m" + "(   )" + E + "[37;1m" + "------'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "  ,----------" + E + "[31;1m" + "(   )" + E + "[37;1m" + "----------," + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + " |        _,-" + E + "[31;1m" + "(   )" + E + "[37;1m" + "-,_        |" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "  `-,__,-'   " + E + "[31;1m" + "\\   /" + E + "[37;1m" + "   `-,__,-'" + R + "\n"
        a = a + E + "[37;1m" + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              | |" + R + "\n"
        a = a + E + "[31;1m" + "              `|'" + R + "\n"
        emit a
    }
    if startsWith(dn, "eurolinux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                __" + R + "\n"
        a = a + E + "[34;1m" + "         -wwwWWWWWWWWWwww-" + R + "\n"
        a = a + E + "[34;1m" + "        -WWWWWWWWWWWWWWWWWWw-" + R + "\n"
        a = a + E + "[34;1m" + "          \\WWWWWWWWWWWWWWWWWWW-" + R + "\n"
        a = a + E + "[34;1m" + "  _Ww      `WWWWWWWWWWWWWWWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + " -W" + E + "[37;1m" + "E" + E + "[34;1m" + "Www                -WWWWWWWWW-" + R + "\n"
        a = a + E + "[34;1m" + "_WW" + E + "[37;1m" + "U" + E + "[34;1m" + "WWWW-                _WWWWWWWW" + R + "\n"
        a = a + E + "[34;1m" + "_WW" + E + "[37;1m" + "R" + E + "[34;1m" + "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW-" + R + "\n"
        a = a + E + "[34;1m" + "wWW" + E + "[37;1m" + "O" + E + "[34;1m" + "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW" + R + "\n"
        a = a + E + "[34;1m" + "WWW" + E + "[37;1m" + "L" + E + "[34;1m" + "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + "WWW" + E + "[37;1m" + "I" + E + "[34;1m" + "WWWWWWWWWWWWWWWWWWWWWWWWWWWWww-" + R + "\n"
        a = a + E + "[34;1m" + "wWW" + E + "[37;1m" + "N" + E + "[34;1m" + "WWWWw" + R + "\n"
        a = a + E + "[34;1m" + " WW" + E + "[37;1m" + "U" + E + "[34;1m" + "WWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + " wW" + E + "[37;1m" + "X" + E + "[34;1m" + "WWWWWWWWww" + R + "\n"
        a = a + E + "[34;1m" + "   wWWWWWWWWWWWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + "    wWWWWWWWWWWWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + "       WWWWWWWWWWWWWw" + R + "\n"
        a = a + E + "[34;1m" + "           wWWWWWWWw" + R + "\n"
        emit a
    }
    if startsWith(dn, "galliumos") {
        a = a + E + "[34;1m" + E + "[34;1m" + "sooooooooooooooooooooooooooooooooooooo+:" + R + "\n"
        a = a + E + "[34;1m" + "yyooooooooooooooooooooooooooooooooo+/:::" + R + "\n"
        a = a + E + "[34;1m" + "yyysoooooooooooooooooooooooooooo+/::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyoooooooooooooooooooooooo+/:::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyysoooooooooooooooooo++/::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyysoooooooooooooo++/:::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyysoooooo" + E + "[37;1m" + "sydddys" + E + "[34;1m" + "+/:::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyysooo" + E + "[37;1m" + "smMMMMMMMNd" + E + "[34;1m" + "+::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyo" + E + "[37;1m" + "sMMMMMMMMMMMN" + E + "[34;1m" + "/:::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyy" + E + "[37;1m" + "dMMMMMMMMMMMM" + E + "[34;1m" + "o//:::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyy" + E + "[37;1m" + "hMMMMMMMMMMMm" + E + "[34;1m" + "--//::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyy" + E + "[37;1m" + "hmMMMMMMMNy" + E + "[34;1m" + ":..-://::::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyy" + E + "[37;1m" + "yyhhyys+:" + E + "[34;1m" + "......://:::::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyys+:--...........-///:::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyys+:--................://::::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyo+:-.....................-//:::" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyo+:-..........................://:" + R + "\n"
        a = a + E + "[34;1m" + "yyyo+:-..............................-//" + R + "\n"
        a = a + E + "[34;1m" + "o/:-...................................:" + R + "\n"
        emit a
    }
    if startsWith(dn, "gnewsense") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                     ..,,,,.." + R + "\n"
        a = a + E + "[34;1m" + "               .oocchhhhhhhhhhccoo." + R + "\n"
        a = a + E + "[34;1m" + "        .ochhlllllllc hhhhhh ollllllhhco." + R + "\n"
        a = a + E + "[34;1m" + "    ochlllllllllll hhhllllllhhh lllllllllllhco" + R + "\n"
        a = a + E + "[34;1m" + " .cllllllllllllll hlllllo  +hllh llllllllllllllc." + R + "\n"
        a = a + E + "[34;1m" + "ollllllllllhco''  hlllllo  +hllh  ``ochllllllllllo" + R + "\n"
        a = a + E + "[34;1m" + "hllllllllc'       hllllllllllllh       `cllllllllh" + R + "\n"
        a = a + E + "[34;1m" + "ollllllh          +llllllllllll+          hllllllo" + R + "\n"
        a = a + E + "[34;1m" + " `cllllh.           ohllllllho           .hllllc'" + R + "\n"
        a = a + E + "[34;1m" + "    ochllc.            ++++            .cllhco" + R + "\n"
        a = a + E + "[34;1m" + "       `+occooo+.                .+ooocco+'" + R + "\n"
        a = a + E + "[34;1m" + "              `+oo++++      ++++oo+'" + R + "\n"
        emit a
    }
    if startsWith(dn, "gobolinux") {
        a = a + E + "[35;1m" + E + "[35;1m" + "  _____       _" + R + "\n"
        a = a + E + "[35;1m" + " / ____|     | |" + R + "\n"
        a = a + E + "[35;1m" + "| |  __  ___ | |__   ___" + R + "\n"
        a = a + E + "[35;1m" + "| | |_ |/ _ \\| '_ \\ / _ \\" + R + "\n"
        a = a + E + "[35;1m" + "| |__| | (_) | |_) | (_) |" + R + "\n"
        a = a + E + "[35;1m" + " \\_____|\\___/|_.__/ \\___/" + R + "\n"
        emit a
    }
    if startsWith(dn, "grombyang") {
        a = a + E + "[34;1m" + E + "[34;1m" + "            eeeeeeeeeeee" + R + "\n"
        a = a + E + "[34;1m" + "         eeeeeeeeeeeeeeeee" + R + "\n"
        a = a + E + "[34;1m" + "      eeeeeeeeeeeeeeeeeeeeeee" + R + "\n"
        a = a + E + "[34;1m" + "    eeeee       " + E + "[32;1m" + ".o+       " + E + "[34;1m" + "eeee" + R + "\n"
        a = a + E + "[34;1m" + "  eeee         " + E + "[32;1m" + "`ooo/         " + E + "[34;1m" + "eeee" + R + "\n"
        a = a + E + "[34;1m" + " eeee         " + E + "[32;1m" + "`+oooo:         " + E + "[34;1m" + "eeee" + R + "\n"
        a = a + E + "[34;1m" + "eee          " + E + "[32;1m" + "`+oooooo:          " + E + "[34;1m" + "eee" + R + "\n"
        a = a + E + "[34;1m" + "eee          " + E + "[32;1m" + "-+oooooo+:         " + E + "[34;1m" + "eee" + R + "\n"
        a = a + E + "[34;1m" + "ee         " + E + "[32;1m" + "`/:oooooooo+:         " + E + "[34;1m" + "ee" + R + "\n"
        a = a + E + "[34;1m" + "ee        " + E + "[32;1m" + "`/+   +++    +:        " + E + "[34;1m" + "ee" + R + "\n"
        a = a + E + "[34;1m" + "ee              " + E + "[32;1m" + "+o+\\             " + E + "[34;1m" + "ee" + R + "\n"
        a = a + E + "[34;1m" + "eee             " + E + "[32;1m" + "+o+\\            " + E + "[34;1m" + "eee" + R + "\n"
        a = a + E + "[34;1m" + "eee        " + E + "[32;1m" + "//  \\\\ooo/  \\\\\\        " + E + "[34;1m" + "eee" + R + "\n"
        a = a + E + "[34;1m" + " eee      " + E + "[32;1m" + "//++++oooo++++\\\\\\     " + E + "[34;1m" + "eee" + R + "\n"
        a = a + E + "[34;1m" + "  eeee    " + E + "[32;1m" + "::::++oooo+:::::   " + E + "[34;1m" + "eeee" + R + "\n"
        a = a + E + "[34;1m" + "    eeeee   " + E + "[31;1m" + "Grombyang OS " + E + "[34;1m" + "  eeee" + R + "\n"
        a = a + E + "[34;1m" + "      eeeeeeeeeeeeeeeeeeeeeee" + R + "\n"
        a = a + E + "[34;1m" + "         eeeeeeeeeeeeeeeee" + R + "\n"
        emit a
    }
    if startsWith(dn, "hyperbola") {
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "                     WW" + R + "\n"
        a = a + E + "[38;5;8m" + "                     KX              W" + R + "\n"
        a = a + E + "[38;5;8m" + "                    WO0W          NX0O" + R + "\n"
        a = a + E + "[38;5;8m" + "                    NOO0NW  WNXK0OOKW" + R + "\n"
        a = a + E + "[38;5;8m" + "                    W0OOOOOOOOOOOOKN" + R + "\n"
        a = a + E + "[38;5;8m" + "                     N0OOOOOOO0KXW" + R + "\n"
        a = a + E + "[38;5;8m" + "                       WNXXXNW" + R + "\n"
        a = a + E + "[38;5;8m" + "                 NXK00000KN" + R + "\n"
        a = a + E + "[38;5;8m" + "             WNK0OOOOOOOOOO0W" + R + "\n"
        a = a + E + "[38;5;8m" + "           NK0OOOOOOOOOOOOOO0W" + R + "\n"
        a = a + E + "[38;5;8m" + "         X0OOOOOOO00KK00OOOOOK" + R + "\n"
        a = a + E + "[38;5;8m" + "       X0OOOO0KNWW      WX0OO0W" + R + "\n"
        a = a + E + "[38;5;8m" + "     X0OO0XNW              KOOW" + R + "\n"
        a = a + E + "[38;5;8m" + "   N00KNW                   KOW" + R + "\n"
        a = a + E + "[38;5;8m" + " NKXN                       W0W" + R + "\n"
        a = a + E + "[38;5;8m" + "WW                           W" + R + "\n"
        emit a
    }
    if startsWith(dn, "libreelec") {
        a = a + E + "[32;1m" + E + "[32;1m" + "          :+ooo/.      " + E + "[33;1m" + "./ooo+:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "        :+ooooooo/.  " + E + "[33;1m" + "./ooooooo+:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "      :+ooooooooooo:" + E + "[33;1m" + ":ooooooooooo+:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "    :+ooooooooooo+-  " + E + "[33;1m" + "-+ooooooooooo+:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "  :+ooooooooooo+-  " + E + "[37;1m" + "--  " + E + "[33;1m" + "-+ooooooooooo+:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + ".+ooooooooooo+-  " + E + "[37;1m" + ":+oo+:  " + E + "[33;1m" + "-+ooooooooooo+-" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "-+ooooooooo+-  " + E + "[37;1m" + ":+oooooo+:  " + E + "[33;1m" + "-+oooooooooo-" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "  :+ooooo+-  " + E + "[37;1m" + ":+oooooooooo+:  " + E + "[33;1m" + "-+oooooo:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "    :+o+-  " + E + "[37;1m" + ":+oooooooooooooo+:  " + E + "[33;1m" + "-+oo:" + R + "\n"
        a = a + E + "[33;1m" + E + "[38;5;14m" + "     ./   " + E + "[37;1m" + ":oooooooooooooooooo:   " + E + "[38;5;13m" + "/." + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "   ./oo+:  " + E + "[37;1m" + "-+oooooooooooooo+-  " + E + "[38;5;13m" + ":+oo/." + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + " ./oooooo+:  " + E + "[37;1m" + "-+oooooooooo+-  " + E + "[38;5;13m" + ":+oooooo/." + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "-oooooooooo+:  " + E + "[37;1m" + "-+oooooo+-  " + E + "[38;5;13m" + ":+oooooooooo-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + ".+ooooooooooo+:  " + E + "[37;1m" + "-+oo+-  " + E + "[38;5;13m" + ":+ooooooooooo+." + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "  -+ooooooooooo+:  " + E + "[37;1m" + "..  " + E + "[38;5;13m" + ":+ooooooooooo+-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "    -+ooooooooooo+:  " + E + "[38;5;13m" + ":+ooooooooooo+-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "      -+oooooooooo+:" + E + "[38;5;13m" + ":+oooooooooo+-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "        -+oooooo+:    " + E + "[38;5;13m" + ":+oooooo+-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "          -+oo+:        " + E + "[38;5;13m" + ":+oo+-" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;14m" + "            ..            " + E + "[38;5;13m" + ".." + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_6(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "netrunner") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           .:oydmMMMMMMmdyo:`" + R + "\n"
        a = a + E + "[34;1m" + "        -smMMMMMMMMMMMMMMMMMMds-" + R + "\n"
        a = a + E + "[34;1m" + "      +mMMMMMMMMMMMMMMMMMMMMMMMMd+" + R + "\n"
        a = a + E + "[34;1m" + "    /mMMMMMMMMMMMMMMMMMMMMMMMMMMMMm/" + R + "\n"
        a = a + E + "[34;1m" + "  `hMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMy`" + R + "\n"
        a = a + E + "[34;1m" + " .mMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMd`" + R + "\n"
        a = a + E + "[34;1m" + " dMMMMMMMMMMMMMMMMMMMMMMNdhmMMMMMMMMMMh" + R + "\n"
        a = a + E + "[34;1m" + "+MMMMMMMMMMMMMNmhyo+/-.   -MMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[34;1m" + "mMMMMMMMMd+:.`           `mMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "MMMMMMMMMMMdy/.          yMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[34;1m" + "MMMMMMMMMMMMMMMNh+`     +MMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[34;1m" + "mMMMMMMMMMMMMMMMMMs    -NMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "+MMMMMMMMMMMMMMMMMN.  `mMMMMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[34;1m" + " dMMMMMMMMMMMMMMMMMy  hMMMMMMMMMMMMMMMh" + R + "\n"
        a = a + E + "[34;1m" + " `dMMMMMMMMMMMMMMMMM-+MMMMMMMMMMMMMMMd`" + R + "\n"
        a = a + E + "[34;1m" + "  `hMMMMMMMMMMMMMMMMmMMMMMMMMMMMMMMMy" + R + "\n"
        a = a + E + "[34;1m" + "    /mMMMMMMMMMMMMMMMMMMMMMMMMMMMMm:" + R + "\n"
        a = a + E + "[34;1m" + "      +dMMMMMMMMMMMMMMMMMMMMMMMMd/" + R + "\n"
        a = a + E + "[34;1m" + "        -odMMMMMMMMMMMMMMMMMMdo-" + R + "\n"
        a = a + E + "[34;1m" + "           `:+ydmNMMMMNmhy+-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "nixos_old") {
        a = a + E + "[34;1m" + E + "[34;1m" + "          ::::.    " + E + "[36;1m" + "':::::     ::::'" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "          ':::::    " + E + "[36;1m" + "':::::.  ::::'" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "            :::::     " + E + "[36;1m" + "'::::.:::::" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "      .......:::::..... " + E + "[36;1m" + "::::::::" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "     ::::::::::::::::::. " + E + "[36;1m" + "::::::    " + E + "[34;1m" + "::::." + R + "\n"
        a = a + E + "[34;1m" + "    ::::::::::::::::::::: " + E + "[36;1m" + ":::::.  " + E + "[34;1m" + ".::::'" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "           .....           ::::' " + E + "[34;1m" + ":::::'" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "          :::::            '::' " + E + "[34;1m" + ":::::'" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + " ........:::::               ' " + E + "[34;1m" + ":::::::::::." + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + ":::::::::::::                 " + E + "[34;1m" + ":::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + " ::::::::::: " + E + "[34;1m" + "..              " + E + "[34;1m" + ":::::" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "     .::::: " + E + "[34;1m" + ".:::            " + E + "[34;1m" + ":::::" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "    .:::::  " + E + "[34;1m" + ":::::          " + E + "[34;1m" + "'''''    " + E + "[36;1m" + "....." + R + "\n"
        a = a + E + "[36;1m" + "    :::::   " + E + "[34;1m" + "':::::.  " + E + "[36;1m" + "......:::::::::::::'" + R + "\n"
        a = a + E + "[36;1m" + "     :::     " + E + "[34;1m" + "::::::. " + E + "[36;1m" + "':::::::::::::::::'" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "            .:::::::: " + E + "[36;1m" + "'::::::::::" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "           .::::''::::.     " + E + "[36;1m" + "'::::." + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "          .::::'   ::::.     " + E + "[36;1m" + "'::::." + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "         .::::      ::::      " + E + "[36;1m" + "'::::." + R + "\n"
        emit a
    }
    if startsWith(dn, "obrevenge") {
        a = a + E + "[31;1m" + E + "[31;1m" + "   __   __" + R + "\n"
        a = a + E + "[31;1m" + "     _@@@@   @@@g_" + R + "\n"
        a = a + E + "[31;1m" + "   _@@@@@@   @@@@@@" + R + "\n"
        a = a + E + "[31;1m" + "  _@@@@@@M   W@@@@@@_" + R + "\n"
        a = a + E + "[31;1m" + " j@@@@P        ^W@@@@" + R + "\n"
        a = a + E + "[31;1m" + " @@@@L____  _____Q@@@@" + R + "\n"
        a = a + E + "[31;1m" + "Q@@@@@@@@@@j@@@@@@@@@@" + R + "\n"
        a = a + E + "[31;1m" + "@@@@@    T@j@    T@@@@@" + R + "\n"
        a = a + E + "[31;1m" + "@@@@@ ___Q@J@    _@@@@@" + R + "\n"
        a = a + E + "[31;1m" + "@@@@@fMMM@@j@jggg@@@@@@" + R + "\n"
        a = a + E + "[31;1m" + "@@@@@    j@j@^MW@P @@@@" + R + "\n"
        a = a + E + "[31;1m" + "Q@@@@@ggg@@f@   @@@@@@L" + R + "\n"
        a = a + E + "[31;1m" + "^@@@@WWMMP  ^    Q@@@@" + R + "\n"
        a = a + E + "[31;1m" + " @@@@@_         _@@@@l" + R + "\n"
        a = a + E + "[31;1m" + "  W@@@@@g_____g@@@@@P" + R + "\n"
        a = a + E + "[31;1m" + "   @@@@@@@@@@@@@@@@l" + R + "\n"
        a = a + E + "[31;1m" + "    ^W@@@@@@@@@@@P" + R + "\n"
        a = a + E + "[31;1m" + "       ^TMMMMTll" + R + "\n"
        emit a
    }
    if startsWith(dn, "openeuler") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                 `.cc.`" + R + "\n"
        a = a + E + "[34;1m" + "             ``.cccccccc..`" + R + "\n"
        a = a + E + "[34;1m" + "          `.cccccccccccccccc.`" + R + "\n"
        a = a + E + "[34;1m" + "      ``.cccccccccccccccccccccc.``" + R + "\n"
        a = a + E + "[34;1m" + "   `..cccccccccccccccccccccccccccc..`" + R + "\n"
        a = a + E + "[34;1m" + "`.ccccccccccccccc" + E + "[37;1m" + "/++/" + E + "[34;1m" + "ccccccccccccccccc.`" + R + "\n"
        a = a + E + "[34;1m" + ".ccccccccccccccc" + E + "[37;1m" + "mNMMNdo+oso+" + E + "[34;1m" + "ccccccccccc." + R + "\n"
        a = a + E + "[34;1m" + ".cccccccccc" + E + "[37;1m" + "/++odms+//+mMMMMm/:+syso/" + E + "[34;1m" + "cccc" + R + "\n"
        a = a + E + "[34;1m" + ".ccccccccc" + E + "[37;1m" + "yNNMMMs:::/::+o+/:" + E + "[34;1m" + "c" + E + "[37;1m" + "dMMMMMm" + E + "[34;1m" + "cccc" + R + "\n"
        a = a + E + "[34;1m" + ".ccccccc" + E + "[37;1m" + ":+NmdyyhNNmNNNd:" + E + "[34;1m" + "ccccc" + E + "[34;1m" + E + "[37;1m" + ":oyyyo:" + E + "[34;1m" + "cccc" + R + "\n"
        a = a + E + "[34;1m" + ".ccc" + E + "[37;1m" + ":ohdmMs:" + E + "[34;1m" + "cccc" + E + "[37;1m" + "+mNMNmy" + E + "[34;1m" + "ccccccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".cc" + E + "[37;1m" + "/NMMMMMo////:" + E + "[34;1m" + "c" + E + "[37;1m" + ":///:" + E + "[34;1m" + "cccccccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".cc" + E + "[37;1m" + ":syysyNMNNNMNy" + E + "[34;1m" + "ccccccccccccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".cccccccc" + E + "[37;1m" + "+MMMMMNy" + E + "[34;1m" + "c" + E + "[37;1m" + ":/+++/" + E + "[34;1m" + "cccccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".ccccccccc" + E + "[37;1m" + "ohhhs/" + E + "[34;1m" + "c" + E + "[37;1m" + "omMMMMNh" + E + "[34;1m" + "ccccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".ccccccccccccccc" + E + "[37;1m" + ":MMMMMMMM/" + E + "[34;1m" + "cccccccccccccc" + R + "\n"
        a = a + E + "[34;1m" + ".cccccccccccccccc" + E + "[37;1m" + "sNNNNNd+" + E + "[34;1m" + "cccccccccccccc." + R + "\n"
        a = a + E + "[34;1m" + "`..cccccccccccccccc" + E + "[37;1m" + "/+/:" + E + "[34;1m" + "cccccccccccccc..`" + R + "\n"
        a = a + E + "[34;1m" + "   ``.cccccccccccccccccccccccccccc.``" + R + "\n"
        a = a + E + "[34;1m" + "       `.cccccccccccccccccccccc.`" + R + "\n"
        a = a + E + "[34;1m" + "          ``.cccccccccccccc.``" + R + "\n"
        a = a + E + "[34;1m" + "              `.cccccccc.`" + R + "\n"
        a = a + E + "[34;1m" + "                 `....`" + R + "\n"
        emit a
    }
    if startsWith(dn, "openmamba") {
        a = a + E + "[37;1m" + E + "[37;1m" + "                 `````" + R + "\n"
        a = a + E + "[37;1m" + "           .-/+ooooooooo+/:-`" + R + "\n"
        a = a + E + "[37;1m" + "        ./ooooooooooooooooooo+:." + R + "\n"
        a = a + E + "[37;1m" + "      -+oooooooooooooooooooooooo+-" + R + "\n"
        a = a + E + "[37;1m" + "    .+ooooooooo+/:---::/+ooooooooo+." + R + "\n"
        a = a + E + "[37;1m" + "   :oooooooo/-`          `-/oo" + E + "[32;1m" + "s´" + E + "[37;1m" + "oooo." + E + "[32;1m" + "s´" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "  :ooooooo/`                `" + E + "[32;1m" + "sNds" + E + "[37;1m" + "ooo" + E + "[32;1m" + "sNds" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + " -ooooooo-                   " + E + "[32;1m" + ":dmy" + E + "[37;1m" + "ooo" + E + "[32;1m" + ":dmy" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + " +oooooo:                      :oooooo-" + R + "\n"
        a = a + E + "[37;1m" + ".ooooooo                        .://:`" + R + "\n"
        a = a + E + "[37;1m" + ":oooooo+                        ./+o+:`" + R + "\n"
        a = a + E + "[37;1m" + "-ooooooo`                      `oooooo+" + R + "\n"
        a = a + E + "[37;1m" + "`ooooooo:                      /oooooo+" + R + "\n"
        a = a + E + "[37;1m" + " -ooooooo:                    :ooooooo." + R + "\n"
        a = a + E + "[37;1m" + "  :ooooooo+.                .+ooooooo:" + R + "\n"
        a = a + E + "[37;1m" + "   :oooooooo+-`          `-+oooooooo:" + R + "\n"
        a = a + E + "[37;1m" + "    .+ooooooooo+/::::://oooooooooo+." + R + "\n"
        a = a + E + "[37;1m" + "      -+oooooooooooooooooooooooo+-" + R + "\n"
        a = a + E + "[37;1m" + "        .:ooooooooooooooooooo+:." + R + "\n"
        a = a + E + "[37;1m" + "           `-:/ooooooooo+/:.`" + R + "\n"
        a = a + E + "[37;1m" + "                 ``````" + R + "\n"
        emit a
    }
    if startsWith(dn, "openstage") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                 /(/" + R + "\n"
        a = a + E + "[32;1m" + "              .(((((((," + R + "\n"
        a = a + E + "[32;1m" + "             /(((((((((/" + R + "\n"
        a = a + E + "[32;1m" + "           .(((((/,/(((((," + R + "\n"
        a = a + E + "[32;1m" + "          *(((((*   ,(((((/" + R + "\n"
        a = a + E + "[32;1m" + "          (((((*      .*/((" + R + "\n"
        a = a + E + "[32;1m" + "         *((((/  (//(/*" + R + "\n"
        a = a + E + "[32;1m" + "         /((((*  ((((((((((," + R + "\n"
        a = a + E + "[32;1m" + "      .  /((((*  (((((((((((((." + R + "\n"
        a = a + E + "[32;1m" + "     ((. *((((/        ,((((((((" + R + "\n"
        a = a + E + "[32;1m" + "   ,(((/  (((((/     **   ,((((((*" + R + "\n"
        a = a + E + "[32;1m" + "  /(((((. .(((((/   //(((*  *(((((/" + R + "\n"
        a = a + E + "[32;1m" + " .(((((,    ((/   .(((((/.   .(((((," + R + "\n"
        a = a + E + "[32;1m" + " /((((*        ,(((((((/      ,(((((" + R + "\n"
        a = a + E + "[32;1m" + " /(((((((((((((((((((/.  /(((((((((/" + R + "\n"
        a = a + E + "[32;1m" + " /(((((((((((((((((,   /(((((((((((/" + R + "\n"
        a = a + E + "[32;1m" + "     */(((((//*.      */((/(/(/*" + R + "\n"
        emit a
    }
    if startsWith(dn, "os elbrus") {
        a = a + E + "[34;1m" + E + "[34;1m" + "   ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄" + R + "\n"
        a = a + E + "[34;1m" + "   ██▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀██" + R + "\n"
        a = a + E + "[34;1m" + "   ██                       ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ███████   ███████   ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██   ██   ██   ██   ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██   ██   ██   ██   ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██   ██   ██   ██   ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██   ██   ██   ██   ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██   ███████   ███████" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██                  ██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ██▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄██" + R + "\n"
        a = a + E + "[34;1m" + "   ██   ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀██" + R + "\n"
        a = a + E + "[34;1m" + "   ██                       ██" + R + "\n"
        a = a + E + "[34;1m" + "   ███████████████████████████" + R + "\n"
        emit a
    }
    if startsWith(dn, "pclinuxos") {
        a = a + E + "[34;1m" + E + "[34;1m" + "            mhhhyyyyhhhdN" + R + "\n"
        a = a + E + "[34;1m" + "        dyssyhhhhhhhhhhhssyhN" + R + "\n"
        a = a + E + "[34;1m" + "     Nysyhhyo/:-.....-/oyhhhssd" + R + "\n"
        a = a + E + "[34;1m" + "   Nsshhy+.              `/shhysm" + R + "\n"
        a = a + E + "[34;1m" + "  dohhy/                    -shhsy" + R + "\n"
        a = a + E + "[34;1m" + " dohhs`                       /hhys" + R + "\n"
        a = a + E + "[34;1m" + "N+hho   " + E + "[37;1m" + "+ssssss+-   .+syhys+   " + E + "[34;1m" + "/hhsy" + R + "\n"
        a = a + E + "[34;1m" + "ohhh`   " + E + "[37;1m" + "ymmo++hmm+`smmy/::+y`   " + E + "[34;1m" + "shh+" + R + "\n"
        a = a + E + "[34;1m" + "+hho    " + E + "[37;1m" + "ymm-  /mmy+mms          " + E + "[34;1m" + ":hhod" + R + "\n"
        a = a + E + "[34;1m" + "/hh+    " + E + "[37;1m" + "ymmhhdmmh.smm/          " + E + "[34;1m" + ".hhsh" + R + "\n"
        a = a + E + "[34;1m" + "+hhs    " + E + "[37;1m" + "ymm+::-`  /mmy`    `    " + E + "[34;1m" + "/hh+m" + R + "\n"
        a = a + E + "[34;1m" + "yyhh-   " + E + "[37;1m" + "ymm-       /dmdyosyd`  " + E + "[34;1m" + "`yhh+" + R + "\n"
        a = a + E + "[34;1m" + " ohhy`  " + E + "[37;1m" + "://`         -/+++/-   " + E + "[34;1m" + "ohhom" + R + "\n"
        a = a + E + "[34;1m" + " N+hhy-                      `shhoh" + R + "\n"
        a = a + E + "[34;1m" + "   sshho.                  `+hhyom" + R + "\n"
        a = a + E + "[34;1m" + "    dsyhhs/.            `:ohhhoy" + R + "\n"
        a = a + E + "[34;1m" + "      dysyhhhso///://+syhhhssh" + R + "\n"
        a = a + E + "[34;1m" + "         dhyssyhhhhhhyssyyhN" + R + "\n"
        a = a + E + "[34;1m" + "              mddhdhdmN" + R + "\n"
        emit a
    }
    if startsWith(dn, "reborn os") || startsWith(dn, "reborn") {
        a = a + E + "[32;1m" + E + "[38;5;8m" + R + "\n"
        a = a + E + "[38;5;8m" + "        mMMMMMMMMM  MMMMMMMMMm" + R + "\n"
        a = a + E + "[38;5;8m" + "       NM                    MN" + R + "\n"
        a = a + E + "[38;5;8m" + "      MM  " + E + "[32;1m" + "dddddddd  dddddddd  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + "     mM  " + E + "[32;1m" + "dd                dd  " + E + "[38;5;8m" + "MM" + R + "\n"
        a = a + E + "[38;5;8m" + "        " + E + "[32;1m" + "dd  hhhhhh   hhhhh  dd" + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[38;5;8m" + "mM      " + E + "[32;1m" + "hh            hh      " + E + "[38;5;8m" + "Mm" + R + "\n"
        a = a + E + "[38;5;8m" + "  NM  " + E + "[32;1m" + "hd       " + E + "[38;5;8m" + "mMMMMMMd       " + E + "[32;1m" + "dh  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + " NM  " + E + "[32;1m" + "dd  hh   " + E + "[38;5;8m" + "mMMMMMMMMm   " + E + "[32;1m" + "hh  dd  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + "NM  " + E + "[32;1m" + "dd  hh   " + E + "[38;5;8m" + "mMMMMMMMMMMm   " + E + "[32;1m" + "hh  dd  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + " NM  " + E + "[32;1m" + "dd  hh   " + E + "[38;5;8m" + "mMMMMMMMMm   " + E + "[32;1m" + "hh  dd  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + "  NM  " + E + "[32;1m" + "hd       " + E + "[38;5;8m" + "mMMMMMMm       " + E + "[32;1m" + "dh  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + "   mM      " + E + "[32;1m" + "hh            hh      " + E + "[38;5;8m" + "Mm" + R + "\n"
        a = a + E + "[38;5;8m" + "        " + E + "[32;1m" + "dd  hhhhhh  hhhhhh  dd" + R + "\n"
        a = a + E + "[32;1m" + "     " + E + "[38;5;8m" + "MM  " + E + "[32;1m" + "dd                dd  " + E + "[38;5;8m" + "MM" + R + "\n"
        a = a + E + "[38;5;8m" + "      MM  " + E + "[32;1m" + "dddddddd  dddddddd  " + E + "[38;5;8m" + "MN" + R + "\n"
        a = a + E + "[38;5;8m" + "       NM                    MN" + R + "\n"
        a = a + E + "[38;5;8m" + "        mMMMMMMMMM  MMMMMMMMMm" + R + "\n"
        emit a
    }
    if startsWith(dn, "siduction") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                _aass," + R + "\n"
        a = a + E + "[34;1m" + "               jQh: =$w" + R + "\n"
        a = a + E + "[34;1m" + "               QWmwawQW" + R + "\n"
        a = a + E + "[34;1m" + "               )$QQQQ@(   .." + R + "\n"
        a = a + E + "[34;1m" + "         _a_a.   ~??^  syDY?Sa," + R + "\n"
        a = a + E + "[34;1m" + "       _mW>-<$c       jWmi  imm." + R + "\n"
        a = a + E + "[34;1m" + "       ]QQwayQE       4QQmgwmQQ`" + R + "\n"
        a = a + E + "[34;1m" + "        ?WWQWP'       -9QQQQQ@'._aas," + R + "\n"
        a = a + E + "[34;1m" + " _a%is.        .adYYs,. -\"?!` aQB*~^3$c" + R + "\n"
        a = a + E + "[34;1m" + "_Qh;.nm       .QWc. {QL      ]QQp;..vmQ/" + R + "\n"
        a = a + E + "[34;1m" + "\"QQmmQ@       -QQQggmQP      ]QQWmggmQQ(" + R + "\n"
        a = a + E + "[34;1m" + " -???\"         \"$WQQQY`  __,  ?QQQQQQW!" + R + "\n"
        a = a + E + "[34;1m" + "        _yZ!?q,   -   .yWY!!Sw, \"???^" + R + "\n"
        a = a + E + "[34;1m" + "       .QQa_=qQ       mQm>..vmm" + R + "\n"
        a = a + E + "[34;1m" + "        $QQWQQP       $QQQgmQQ@" + R + "\n"
        a = a + E + "[34;1m" + "         \"???\"   _aa, -9WWQQWY`" + R + "\n"
        a = a + E + "[34;1m" + "               _mB>~)$a  -~~" + R + "\n"
        a = a + E + "[34;1m" + "               mQms_vmQ." + R + "\n"
        a = a + E + "[34;1m" + "               ]WQQQQQP" + R + "\n"
        a = a + E + "[34;1m" + "                -?T??\"" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_7(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "slackware") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                  :::::::" + R + "\n"
        a = a + E + "[34;1m" + "            :::::::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "         :::::::::::::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "       ::::::::" + E + "[37;1m" + "cllcccccllllllll" + E + "[34;1m" + "::::::" + R + "\n"
        a = a + E + "[34;1m" + "    :::::::::" + E + "[37;1m" + "lc               dc" + E + "[34;1m" + ":::::::" + R + "\n"
        a = a + E + "[34;1m" + "   ::::::::" + E + "[37;1m" + "cl   clllccllll    oc" + E + "[34;1m" + ":::::::::" + R + "\n"
        a = a + E + "[34;1m" + "  :::::::::" + E + "[37;1m" + "o   lc" + E + "[34;1m" + "::::::::" + E + "[37;1m" + "co   oc" + E + "[34;1m" + "::::::::::" + R + "\n"
        a = a + E + "[34;1m" + " ::::::::::" + E + "[37;1m" + "o    cccclc" + E + "[34;1m" + ":::::" + E + "[37;1m" + "clcc" + E + "[34;1m" + "::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + " :::::::::::" + E + "[37;1m" + "lc        cclccclc" + E + "[34;1m" + ":::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "::::::::::::::" + E + "[37;1m" + "lcclcc          lc" + E + "[34;1m" + "::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "::::::::::" + E + "[37;1m" + "cclcc" + E + "[34;1m" + ":::::" + E + "[37;1m" + "lccclc     oc" + E + "[34;1m" + ":::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "::::::::::" + E + "[37;1m" + "o    l" + E + "[34;1m" + "::::::::::" + E + "[37;1m" + "l    lc" + E + "[34;1m" + ":::::::::::" + R + "\n"
        a = a + E + "[34;1m" + " :::::" + E + "[37;1m" + "cll" + E + "[34;1m" + ":" + E + "[37;1m" + "o     clcllcccll     o" + E + "[34;1m" + ":::::::::::" + R + "\n"
        a = a + E + "[34;1m" + " :::::" + E + "[37;1m" + "occ" + E + "[34;1m" + ":" + E + "[37;1m" + "o                  clc" + E + "[34;1m" + ":::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "  ::::" + E + "[37;1m" + "ocl" + E + "[34;1m" + ":" + E + "[37;1m" + "ccslclccclclccclclc" + E + "[34;1m" + ":::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "   :::" + E + "[37;1m" + "oclcccccccccccccllllllllllllll" + E + "[34;1m" + ":::::" + R + "\n"
        a = a + E + "[34;1m" + "    ::" + E + "[37;1m" + "lcc1lcccccccccccccccccccccccco" + E + "[34;1m" + "::::" + R + "\n"
        a = a + E + "[34;1m" + "      ::::::::::::::::::::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "        ::::::::::::::::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "           ::::::::::::::::::::::" + R + "\n"
        a = a + E + "[34;1m" + "                ::::::::::::" + R + "\n"
        emit a
    }
    if startsWith(dn, "opensuse") || startsWith(dn, "open suse") || startsWith(dn, "suse") {
        a = a + E + "[32;1m" + E + "[37;1m" + "           .;ldkO0000Okdl;." + R + "\n"
        a = a + E + "[37;1m" + "       .;d00xl:^''''''^:ok00d;." + R + "\n"
        a = a + E + "[37;1m" + "     .d00l'                'o00d." + R + "\n"
        a = a + E + "[37;1m" + "   .d0Kd'" + E + "[32;1m" + "  Okxol:;,.          " + E + "[37;1m" + ":O0d." + R + "\n"
        a = a + E + "[37;1m" + "  .OK" + E + "[32;1m" + "KKK0kOKKKKKKKKKKOxo:,      " + E + "[37;1m" + "lKO." + R + "\n"
        a = a + E + "[37;1m" + " ,0K" + E + "[32;1m" + "KKKKKKKKKKKKKKK0P^" + E + "[37;1m" + ",,," + E + "[32;1m" + "^dx:" + E + "[37;1m" + "    ;00," + R + "\n"
        a = a + E + "[37;1m" + ".OK" + E + "[32;1m" + "KKKKKKKKKKKKKKKk'" + E + "[37;1m" + ".oOPPb." + E + "[32;1m" + "'0k." + E + "[37;1m" + "   cKO." + R + "\n"
        a = a + E + "[37;1m" + ":KK" + E + "[32;1m" + "KKKKKKKKKKKKKKK: " + E + "[37;1m" + "kKx..dd " + E + "[32;1m" + "lKd" + E + "[37;1m" + "   'OK:" + R + "\n"
        a = a + E + "[37;1m" + "dKK" + E + "[32;1m" + "KKKKKKKKKOx0KKKd " + E + "[37;1m" + "^0KKKO' " + E + "[32;1m" + "kKKc" + E + "[37;1m" + "   dKd" + R + "\n"
        a = a + E + "[37;1m" + "dKK" + E + "[32;1m" + "KKKKKKKKKK;.;oOKx,.." + E + "[37;1m" + "^" + E + "[32;1m" + "..;kKKK0." + E + "[37;1m" + "  dKd" + R + "\n"
        a = a + E + "[37;1m" + ":KK" + E + "[32;1m" + "KKKKKKKKKK0o;...^cdxxOK0O/^^'  " + E + "[37;1m" + ".0K:" + R + "\n"
        a = a + E + "[37;1m" + " kKK" + E + "[32;1m" + "KKKKKKKKKKKKK0x;,,......,;od  " + E + "[37;1m" + "lKk" + R + "\n"
        a = a + E + "[37;1m" + " '0K" + E + "[32;1m" + "KKKKKKKKKKKKKKKKKKKK00KKOo^  " + E + "[37;1m" + "c00'" + R + "\n"
        a = a + E + "[37;1m" + "  'kK" + E + "[32;1m" + "KKOxddxkOO00000Okxoc;''   " + E + "[37;1m" + ".dKk'" + R + "\n"
        a = a + E + "[37;1m" + "    l0Ko.                    .c00l'" + R + "\n"
        a = a + E + "[37;1m" + "     'l0Kk:.              .;xK0l'" + R + "\n"
        a = a + E + "[37;1m" + "        'lkK0xl:;,,,,;:ldO0kl'" + R + "\n"
        a = a + E + "[37;1m" + "            '^:ldxkkkkxdl:^'" + R + "\n"
        emit a
    }
    if startsWith(dn, "antergos") {
        a = a + E + "[34;1m" + E + "[36;1m" + "              `.-/::/-``" + R + "\n"
        a = a + E + "[36;1m" + "            .-/osssssssso/." + R + "\n"
        a = a + E + "[36;1m" + "           :osyysssssssyyys+-" + R + "\n"
        a = a + E + "[36;1m" + "        `.+yyyysssssssssyyyyy+." + R + "\n"
        a = a + E + "[36;1m" + "       `/syyyyyssssssssssyyyyys-`" + R + "\n"
        a = a + E + "[36;1m" + "      `/yhyyyyysss" + E + "[34;1m" + "++" + E + "[36;1m" + "ssosyyyyhhy/`" + R + "\n"
        a = a + E + "[36;1m" + "     .ohhhyyyys" + E + "[34;1m" + "o++/+o" + E + "[36;1m" + "so" + E + "[34;1m" + "+" + E + "[36;1m" + "syy" + E + "[34;1m" + "+" + E + "[36;1m" + "shhhho." + R + "\n"
        a = a + E + "[36;1m" + "    .shhhhys" + E + "[34;1m" + "oo++//+" + E + "[36;1m" + "sss" + E + "[34;1m" + "+++" + E + "[36;1m" + "yyy" + E + "[34;1m" + "+s" + E + "[36;1m" + "hhhhs." + R + "\n"
        a = a + E + "[36;1m" + "   -yhhhhs" + E + "[34;1m" + "+++++++o" + E + "[36;1m" + "ssso" + E + "[34;1m" + "+++" + E + "[36;1m" + "yyy" + E + "[34;1m" + "s+o" + E + "[36;1m" + "hhddy:" + R + "\n"
        a = a + E + "[36;1m" + "  -yddhhy" + E + "[34;1m" + "o+++++o" + E + "[36;1m" + "syyss" + E + "[34;1m" + "++++" + E + "[36;1m" + "yyy" + E + "[34;1m" + "yooy" + E + "[36;1m" + "hdddy-" + R + "\n"
        a = a + E + "[36;1m" + " .yddddhs" + E + "[34;1m" + "o++o" + E + "[36;1m" + "syyyyys" + E + "[34;1m" + "+++++" + E + "[36;1m" + "yyhh" + E + "[34;1m" + "sos" + E + "[36;1m" + "hddddy`" + R + "\n"
        a = a + E + "[36;1m" + "`odddddhyosyhyyyyyy" + E + "[34;1m" + "++++++" + E + "[36;1m" + "yhhhyosddddddo" + R + "\n"
        a = a + E + "[36;1m" + ".dmdddddhhhhhhhyyyo" + E + "[34;1m" + "+++++" + E + "[36;1m" + "shhhhhohddddmmh." + R + "\n"
        a = a + E + "[36;1m" + "ddmmdddddhhhhhhhso" + E + "[34;1m" + "++++++" + E + "[36;1m" + "yhhhhhhdddddmmdy" + R + "\n"
        a = a + E + "[36;1m" + "dmmmdddddddhhhyso" + E + "[34;1m" + "++++++" + E + "[36;1m" + "shhhhhddddddmmmmh" + R + "\n"
        a = a + E + "[36;1m" + "-dmmmdddddddhhys" + E + "[34;1m" + "o++++o" + E + "[36;1m" + "shhhhdddddddmmmmd-" + R + "\n"
        a = a + E + "[36;1m" + ".smmmmddddddddhhhhhhhhhdddddddddmmmms." + R + "\n"
        a = a + E + "[36;1m" + "   `+ydmmmdddddddddddddddddddmmmmdy/." + R + "\n"
        a = a + E + "[36;1m" + "      `.:+ooyyddddddddddddyyso+:.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "apricity") {
        a = a + E + "[34;1m" + E + "[37;1m" + "                                    ./o-" + R + "\n"
        a = a + E + "[37;1m" + "          ``...``              `:. -/:" + R + "\n"
        a = a + E + "[37;1m" + "     `-+ymNMMMMMNmho-`      :sdNNm/" + R + "\n"
        a = a + E + "[37;1m" + "   `+dMMMMMMMMMMMMMMMmo` sh:.:::-" + R + "\n"
        a = a + E + "[37;1m" + "  /mMMMMMMMMMMMMMMMMMMMm/`sNd/" + R + "\n"
        a = a + E + "[37;1m" + " oMMMMMMMMMMMMMMMMMMMMMMMs -`" + R + "\n"
        a = a + E + "[37;1m" + ":MMMMMMMMMMMMMMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[37;1m" + "NMMMMMMMMMMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMmdmMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMy` .mMMMMMMMMMMMmho:`" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMNo/sMMMMMMMNdy+-.`-/" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMNdy+:.`.:ohmm:" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMmhs+-.`.:+ymNMMMy." + R + "\n"
        a = a + E + "[37;1m" + "MMMMMM/`.-/ohmNMMMMMMy-" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMNmNNMMMMMMMMmo." + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMMms:`" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMNds/." + R + "\n"
        a = a + E + "[37;1m" + "dhhyys+/-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "arch_old") {
        a = a + E + "[36;1m" + E + "[36;1m" + "             __" + R + "\n"
        a = a + E + "[36;1m" + "         _=(SDGJT=_" + R + "\n"
        a = a + E + "[36;1m" + "       _GTDJHGGFCVS)" + R + "\n"
        a = a + E + "[36;1m" + "      ,GTDJGGDTDFBGX0" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "     JDJDIJHRORVFSBSVL" + E + "[37;1m" + "-=+=,_" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "    IJFDUFHJNXIXCDXDSV," + E + "[37;1m" + "  \"DEBL" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "   [LKDSDJTDU=OUSCSBFLD." + E + "[37;1m" + "   '?ZWX," + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "  ,LMDSDSWH'     `DCBOSI" + E + "[37;1m" + "     DRDS]," + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "  SDDFDFH'         !YEWD," + E + "[37;1m" + "   )HDROD" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " !KMDOCG            &GSU|" + E + "[37;1m" + "\\_GFHRGO\\'" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + " HKLSGP'" + E + "[37;1m" + "           __" + E + "[36;1m" + "\\TKM0" + E + "[37;1m" + "\\GHRBV)'" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "JSNRVW'" + E + "[37;1m" + "       __+MNAEC" + E + "[36;1m" + "\\IOI," + E + "[37;1m" + "\\BN'" + R + "\n"
        a = a + E + "[37;1m" + E + "[36;1m" + "HELK['" + E + "[37;1m" + "    __,=OFFXCBGHC" + E + "[36;1m" + "\\FD)" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "?KGHE " + E + "[37;1m" + "\\_-#DASDFLSV='" + E + "[36;1m" + "    'EF" + R + "\n"
        a = a + E + "[36;1m" + "'EHTI                    !H" + R + "\n"
        a = a + E + "[36;1m" + " `0F'                    '!" + R + "\n"
        emit a
    }
    if startsWith(dn, "archlabs") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                     'c'" + R + "\n"
        a = a + E + "[36;1m" + "                    'kKk," + R + "\n"
        a = a + E + "[36;1m" + "                   .dKKKx." + R + "\n"
        a = a + E + "[36;1m" + "                  .oKXKXKd." + R + "\n"
        a = a + E + "[36;1m" + "                 .l0XXXXKKo." + R + "\n"
        a = a + E + "[36;1m" + "                 c0KXXXXKX0l." + R + "\n"
        a = a + E + "[36;1m" + "                :0XKKOxxOKX0l." + R + "\n"
        a = a + E + "[36;1m" + "               :OXKOc. .c0XX0l." + R + "\n"
        a = a + E + "[36;1m" + "              :OK0o. " + E + "[31;1m" + "..." + E + "[36;1m" + "'dKKX0l." + R + "\n"
        a = a + E + "[36;1m" + "             :OX0c  " + E + "[31;1m" + ";xOx'" + E + "[36;1m" + "'dKXX0l." + R + "\n"
        a = a + E + "[36;1m" + "            :0KKo." + E + "[31;1m" + ".o0XXKd'." + E + "[36;1m" + "lKXX0l." + R + "\n"
        a = a + E + "[36;1m" + "           c0XKd." + E + "[31;1m" + ".oKXXXXKd.." + E + "[36;1m" + "oKKX0l." + R + "\n"
        a = a + E + "[36;1m" + "         .c0XKk;" + E + "[31;1m" + ".l0K0OO0XKd.." + E + "[36;1m" + "oKXXKo." + R + "\n"
        a = a + E + "[36;1m" + "        .l0XXXk:" + E + "[31;1m" + ",dKx,.'l0XKo." + E + "[36;1m" + ".kXXXKo." + R + "\n"
        a = a + E + "[36;1m" + "       .o0XXXX0d," + E + "[31;1m" + ":x;   .oKKx'" + E + "[36;1m" + ".dXKXXKd." + R + "\n"
        a = a + E + "[36;1m" + "      .oKXXXXKK0c." + E + "[31;1m" + ";.    :00c'" + E + "[36;1m" + "cOXXXXXKd." + R + "\n"
        a = a + E + "[36;1m" + "     .dKXXXXXXXXk," + E + "[31;1m" + ".     cKx'" + E + "[36;1m" + "'xKXXXXXXKx'" + R + "\n"
        a = a + E + "[36;1m" + "    'xKXXXXK0kdl:.     " + E + "[31;1m" + ".ok; " + E + "[36;1m" + ".cdk0KKXXXKx'" + R + "\n"
        a = a + E + "[36;1m" + "   'xKK0koc,..         " + E + "[31;1m" + "'c, " + E + "[36;1m" + "    ..,cok0KKk," + R + "\n"
        a = a + E + "[36;1m" + "  ,xko:'.             " + E + "[31;1m" + ".. " + E + "[36;1m" + "           .':okx;" + R + "\n"
        a = a + E + "[36;1m" + " .,'.                                   .',." + R + "\n"
        emit a
    }
    if startsWith(dn, "chaletos") {
        a = a + E + "[34;1m" + E + "[34;1m" + "             `.//+osso+/:``" + R + "\n"
        a = a + E + "[34;1m" + "         `/sdNNmhyssssydmNNdo:`" + R + "\n"
        a = a + E + "[34;1m" + "       :hNmy+-`          .-+hNNs-" + R + "\n"
        a = a + E + "[34;1m" + "     /mMh/`       `+:`       `+dMd:" + R + "\n"
        a = a + E + "[34;1m" + "   .hMd-        -sNNMNo.  /yyy  /mMs`" + R + "\n"
        a = a + E + "[34;1m" + "  -NM+       `/dMd/--omNh::dMM   `yMd`" + R + "\n"
        a = a + E + "[34;1m" + " .NN+      .sNNs:/dMNy:/hNmo/s     yMd`" + R + "\n"
        a = a + E + "[34;1m" + " hMs    `/hNd+-smMMMMMMd+:omNy-    `dMo" + R + "\n"
        a = a + E + "[34;1m" + ":NM.  .omMy:/hNMMMMMMMMMMNy:/hMd+`  :Md`" + R + "\n"
        a = a + E + "[34;1m" + "/Md` `sm+.omMMMMMMMMMMMMMMMMd/-sm+  .MN:" + R + "\n"
        a = a + E + "[34;1m" + "/Md`      MMMMMMMMMMMMMMMMMMMN      .MN:" + R + "\n"
        a = a + E + "[34;1m" + ":NN.      MMMMMMm....--NMMMMMN      -Mm." + R + "\n"
        a = a + E + "[34;1m" + "`dMo      MMMMMMd      mMMMMMN      hMs" + R + "\n"
        a = a + E + "[34;1m" + " -MN:     MMMMMMd      mMMMMMN     oMm`" + R + "\n"
        a = a + E + "[34;1m" + "  :NM:    MMMMMMd      mMMMMMN    +Mm-" + R + "\n"
        a = a + E + "[34;1m" + "   -mMy.  mmmmmmh      dmmmmmh  -hMh." + R + "\n"
        a = a + E + "[34;1m" + "     oNNs-                    :yMm/" + R + "\n"
        a = a + E + "[34;1m" + "      .+mMdo:`            `:smMd/`" + R + "\n"
        a = a + E + "[34;1m" + "         -ohNNmhsoo++osshmNNh+." + R + "\n"
        a = a + E + "[34;1m" + "            `./+syyhhyys+:``" + R + "\n"
        emit a
    }
    if startsWith(dn, "freemint") {
        a = a + E + "[37;1m" + E + "[37;1m" + "          ##" + R + "\n"
        a = a + E + "[37;1m" + "          ##         #########" + R + "\n"
        a = a + E + "[37;1m" + "                    ####      ##" + R + "\n"
        a = a + E + "[37;1m" + "            ####  ####        ##" + R + "\n"
        a = a + E + "[37;1m" + "####        ####  ##        ##" + R + "\n"
        a = a + E + "[37;1m" + "        ####    ####      ##  ##" + R + "\n"
        a = a + E + "[37;1m" + "        ####  ####  ##  ##  ##" + R + "\n"
        a = a + E + "[37;1m" + "            ####  ######" + R + "\n"
        a = a + E + "[37;1m" + "        ######  ##  ##  ####" + R + "\n"
        a = a + E + "[37;1m" + "      ####    ################" + R + "\n"
        a = a + E + "[37;1m" + "    ####        ##  ####" + R + "\n"
        a = a + E + "[37;1m" + "    ##            ####  ######" + R + "\n"
        a = a + E + "[37;1m" + "    ##      ##    ####  ####" + R + "\n"
        a = a + E + "[37;1m" + "    ##    ##  ##    ##  ##  ####" + R + "\n"
        a = a + E + "[37;1m" + "      ####  ##          ##  ##" + R + "\n"
        emit a
    }
    if startsWith(dn, "magpieos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "        ;00000     :000Ol" + R + "\n"
        a = a + E + "[32;1m" + "     .x00kk00:    O0kk00k;" + R + "\n"
        a = a + E + "[32;1m" + "    l00:   :00.  o0k   :O0k." + R + "\n"
        a = a + E + "[32;1m" + "  .k0k.     x" + E + "[31;1m" + "d$dddd" + E + "[32;1m" + "k'    .d00;" + R + "\n"
        a = a + E + "[32;1m" + "  k0k.      " + E + "[31;1m" + ".dddddl       " + E + "[32;1m" + "o00," + R + "\n"
        a = a + E + "[32;1m" + " o00.        " + E + "[31;1m" + "':cc:.        " + E + "[32;1m" + "d0O" + R + "\n"
        a = a + E + "[32;1m" + ".00l                       ,00." + R + "\n"
        a = a + E + "[32;1m" + "l00.                       d0x" + R + "\n"
        a = a + E + "[32;1m" + "k0O                     .:k0o" + R + "\n"
        a = a + E + "[32;1m" + "O0k                 ;dO0000d." + R + "\n"
        a = a + E + "[32;1m" + "k0O               .O0O" + E + "[31;1m" + "xxxxk" + E + "[32;1m" + "00:" + R + "\n"
        a = a + E + "[32;1m" + "o00.              k0O" + E + "[31;1m" + "dddddd" + E + "[32;1m" + "occ" + R + "\n"
        a = a + E + "[32;1m" + "'00l              x0O" + E + "[31;1m" + "dddddo" + E + "[33;1m" + ";.." + E + "[32;1m" + R + "\n"
        a = a + E + "[32;1m" + " x00.             .x00" + E + "[31;1m" + "kxxd" + E + "[33;1m" + ":.." + E + "[32;1m" + R + "\n"
        a = a + E + "[32;1m" + " .O0x               .:oxxx" + E + "[35;1m" + "Okl." + E + "[32;1m" + R + "\n"
        a = a + E + "[32;1m" + "  .x0d                     " + E + "[35;1m" + ",xx," + E + "[32;1m" + R + "\n"
        a = a + E + "[32;1m" + "    .:o.          " + E + "[35;1m" + ".xd       ckd" + E + "[32;1m" + R + "\n"
        a = a + E + "[32;1m" + "       ..          " + E + "[35;1m" + "dxl     .xx;" + R + "\n"
        a = a + E + "[35;1m" + "                    :xxolldxd'" + R + "\n"
        a = a + E + "[35;1m" + "                      ;oxdl." + R + "\n"
        emit a
    }
    if startsWith(dn, "mandriva") || startsWith(dn, "mandrake") {
        a = a + E + "[34;1m" + E + "[33;1m" + "                        ``" + R + "\n"
        a = a + E + "[33;1m" + "                       `-." + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "      `               " + E + "[33;1m" + ".---" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "    -/               " + E + "[33;1m" + "-::--`" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  `++    " + E + "[33;1m" + "`----...```-:::::." + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + " `os.      " + E + "[33;1m" + ".::::::::::::::-```     `  `" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + " +s+         " + E + "[33;1m" + ".::::::::::::::::---...--`" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "-ss:          " + E + "[33;1m" + "`-::::::::::::::::-.``.``" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "/ss-           " + E + "[33;1m" + ".::::::::::::-.``   `" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "+ss:          " + E + "[33;1m" + ".::::::::::::-" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "/sso         " + E + "[33;1m" + ".::::::-::::::-" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + ".sss/       " + E + "[33;1m" + "-:::-.`   .:::::" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + " /sss+.    " + E + "[33;1m" + "..`" + E + "[34;1m" + "  `--`    " + E + "[33;1m" + ".:::" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  -ossso+/:://+/-`        " + E + "[33;1m" + ".:`" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "    -/+ooo+/-.              " + E + "[33;1m" + "`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_8(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "nurunner") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                  ,xc" + R + "\n"
        a = a + E + "[34;1m" + "                ;00cxXl" + R + "\n"
        a = a + E + "[34;1m" + "              ;K0,   .xNo." + R + "\n"
        a = a + E + "[34;1m" + "            :KO'       .lXx." + R + "\n"
        a = a + E + "[34;1m" + "          cXk.    ;xl     cXk." + R + "\n"
        a = a + E + "[34;1m" + "        cXk.    ;k:.,xo.    cXk." + R + "\n"
        a = a + E + "[34;1m" + "     .lXx.    :x::0MNl,dd.    :KO," + R + "\n"
        a = a + E + "[34;1m" + "   .xNx.    cx;:KMMMMMNo'dx.    ;KK;" + R + "\n"
        a = a + E + "[34;1m" + " .dNl.    cd,cXMMMMMMMMMWd,ox'    'OK:" + R + "\n"
        a = a + E + "[34;1m" + ";WK.    'K,.KMMMMMMMMMMMMMWc.Kx     lMO" + R + "\n"
        a = a + E + "[34;1m" + " 'OK:    'dl'xWMMMMMMMMMM0::x:    'OK:" + R + "\n"
        a = a + E + "[34;1m" + "   .kNo    .xo'xWMMMMMM0;:O:    ;KK;" + R + "\n"
        a = a + E + "[34;1m" + "     .dXd.   .do,oNMMO;ck:    ;00," + R + "\n"
        a = a + E + "[34;1m" + "        oNd.   .dx,;'cO;    ;K0," + R + "\n"
        a = a + E + "[34;1m" + "          oNx.    okk;    ;K0," + R + "\n"
        a = a + E + "[34;1m" + "            lXx.        :KO'" + R + "\n"
        a = a + E + "[34;1m" + "              cKk'    cXk." + R + "\n"
        a = a + E + "[34;1m" + "                ;00:lXx." + R + "\n"
        a = a + E + "[34;1m" + "                  ,kd." + R + "\n"
        emit a
    }
    if startsWith(dn, "parabola") {
        a = a + E + "[35;1m" + E + "[35;1m" + "                          `.-.    `." + R + "\n"
        a = a + E + "[35;1m" + "                   `.`  `:++.   `-+o+." + R + "\n"
        a = a + E + "[35;1m" + "             `` `:+/. `:+/.   `-+oooo+" + R + "\n"
        a = a + E + "[35;1m" + "        ``-::-.:+/. `:+/.   `-+oooooo+" + R + "\n"
        a = a + E + "[35;1m" + "    `.-:///-  ..`   .-.   `-+oooooooo-" + R + "\n"
        a = a + E + "[35;1m" + " `..-..`                 `+ooooooooo:" + R + "\n"
        a = a + E + "[35;1m" + "``                        :oooooooo/" + R + "\n"
        a = a + E + "[35;1m" + "                          `ooooooo:" + R + "\n"
        a = a + E + "[35;1m" + "                          `oooooo:" + R + "\n"
        a = a + E + "[35;1m" + "                          -oooo+." + R + "\n"
        a = a + E + "[35;1m" + "                          +ooo/`" + R + "\n"
        a = a + E + "[35;1m" + "                         -ooo-" + R + "\n"
        a = a + E + "[35;1m" + "                        `+o/." + R + "\n"
        a = a + E + "[35;1m" + "                        /+-" + R + "\n"
        a = a + E + "[35;1m" + "                       //`" + R + "\n"
        a = a + E + "[35;1m" + "                      -." + R + "\n"
        emit a
    }
    if startsWith(dn, "raspbian") {
        a = a + E + "[32;1m" + E + "[32;1m" + "  `.::///+:/-.        --///+//-:``" + R + "\n"
        a = a + E + "[32;1m" + " `+oooooooooooo:   `+oooooooooooo:" + R + "\n"
        a = a + E + "[32;1m" + "  /oooo++//ooooo:  ooooo+//+ooooo." + R + "\n"
        a = a + E + "[32;1m" + "  `+ooooooo:-:oo-  +o+::/ooooooo:" + R + "\n"
        a = a + E + "[32;1m" + "   `:oooooooo+``    `.oooooooo+-" + R + "\n"
        a = a + E + "[32;1m" + "     `:++ooo/.        :+ooo+/.`" + R + "\n"
        a = a + E + "[32;1m" + "        " + E + "[31;1m" + "...`  `.----.` ``.." + R + "\n"
        a = a + E + "[31;1m" + "     .::::-``:::::::::.`-:::-`" + R + "\n"
        a = a + E + "[31;1m" + "    -:::-`   .:::::::-`  `-:::-" + R + "\n"
        a = a + E + "[31;1m" + "   `::.  `.--.`  `` `.---.``.::`" + R + "\n"
        a = a + E + "[31;1m" + "       .::::::::`  -::::::::` `" + R + "\n"
        a = a + E + "[31;1m" + " .::` .:::::::::- `::::::::::``::." + R + "\n"
        a = a + E + "[31;1m" + "-:::` ::::::::::.  ::::::::::.`:::-" + R + "\n"
        a = a + E + "[31;1m" + "::::  -::::::::.   `-::::::::  ::::" + R + "\n"
        a = a + E + "[31;1m" + "-::-   .-:::-.``....``.-::-.   -::-" + R + "\n"
        a = a + E + "[31;1m" + " .. ``       .::::::::.     `..`.." + R + "\n"
        a = a + E + "[31;1m" + "   -:::-`   -::::::::::`  .:::::`" + R + "\n"
        a = a + E + "[31;1m" + "   :::::::` -::::::::::` :::::::." + R + "\n"
        a = a + E + "[31;1m" + "   .:::::::  -::::::::. ::::::::" + R + "\n"
        a = a + E + "[31;1m" + "    `-:::::`   ..--.`   ::::::." + R + "\n"
        a = a + E + "[31;1m" + "      `...`  `...--..`  `...`" + R + "\n"
        a = a + E + "[31;1m" + "            .::::::::::" + R + "\n"
        a = a + E + "[31;1m" + "             `.-::::-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "red star") || startsWith(dn, "redstar") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                    .." + R + "\n"
        a = a + E + "[31;1m" + "                  .oK0l" + R + "\n"
        a = a + E + "[31;1m" + "                 :0KKKKd." + R + "\n"
        a = a + E + "[31;1m" + "               .xKO0KKKKd" + R + "\n"
        a = a + E + "[31;1m" + "              ,Od' .d0000l" + R + "\n"
        a = a + E + "[31;1m" + "             .c;.   .'''...           ..'." + R + "\n"
        a = a + E + "[31;1m" + ".,:cloddxxxkkkkOOOOkkkkkkkkxxxxxxxxxkkkx:" + R + "\n"
        a = a + E + "[31;1m" + ";kOOOOOOOkxOkc'...',;;;;,,,'',;;:cllc:,." + R + "\n"
        a = a + E + "[31;1m" + " .okkkkd,.lko  .......',;:cllc:;,,'''''." + R + "\n"
        a = a + E + "[31;1m" + "   .cdo. :xd' cd:.  ..';'',,,'',,;;;,'." + R + "\n"
        a = a + E + "[31;1m" + "      . .ddl.;doooc'..;oc;'..';::;,'." + R + "\n"
        a = a + E + "[31;1m" + "        coo;.oooolllllllcccc:'.  ." + R + "\n"
        a = a + E + "[31;1m" + "       .ool''lllllccccccc:::::;." + R + "\n"
        a = a + E + "[31;1m" + "       ;lll. .':cccc:::::::;;;;'" + R + "\n"
        a = a + E + "[31;1m" + "       :lcc:'',..';::::;;;;;;;,,." + R + "\n"
        a = a + E + "[31;1m" + "       :cccc::::;...';;;;;,,,,,,." + R + "\n"
        a = a + E + "[31;1m" + "       ,::::::;;;,'.  ..',,,,'''." + R + "\n"
        a = a + E + "[31;1m" + "        ........          ......" + R + "\n"
        emit a
    }
    if startsWith(dn, "regolith") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "                 ``....```" + R + "\n"
        a = a + E + "[31;1m" + "            `.:/++++++/::-.`" + R + "\n"
        a = a + E + "[31;1m" + "          -/+++++++:.`" + R + "\n"
        a = a + E + "[31;1m" + "        -++++++++:`" + R + "\n"
        a = a + E + "[31;1m" + "      `/++++++++-" + R + "\n"
        a = a + E + "[31;1m" + "     `/++++++++.                    -/+/" + R + "\n"
        a = a + E + "[31;1m" + "     /++++++++/             ``   .:+++:." + R + "\n"
        a = a + E + "[31;1m" + "    -+++++++++/          ./++++:+++/-`" + R + "\n"
        a = a + E + "[31;1m" + "    :+++++++++/         `+++++++/-`" + R + "\n"
        a = a + E + "[31;1m" + "    :++++++++++`      .-/+++++++`" + R + "\n"
        a = a + E + "[31;1m" + "   `:++++++++++/``.-/++++:-:::-`      `" + R + "\n"
        a = a + E + "[31;1m" + " `:+++++++++++++++++/:.`            ./`" + R + "\n"
        a = a + E + "[31;1m" + ":++/-:+++++++++/:-..              -/+." + R + "\n"
        a = a + E + "[31;1m" + "+++++++++/::-...:/+++/-..````..-/+++." + R + "\n"
        a = a + E + "[31;1m" + "`......``.::/+++++++++++++++++++++/." + R + "\n"
        a = a + E + "[31;1m" + "         -/+++++++++++++++++++++/." + R + "\n"
        a = a + E + "[31;1m" + "           .:/+++++++++++++++/-`" + R + "\n"
        a = a + E + "[31;1m" + "              `.-:://////:-." + R + "\n"
        emit a
    }
    if startsWith(dn, "sabotage") {
        a = a + E + "[34;1m" + E + "[37;1m" + " .|'''.|      |     '||''|.    ..|''||" + R + "\n"
        a = a + E + "[37;1m" + " ||..  '     |||     ||   ||  .|'    ||" + R + "\n"
        a = a + E + "[37;1m" + "  ''|||.    |  ||    ||'''|.  ||      ||" + R + "\n"
        a = a + E + "[37;1m" + ".     '||  .''''|.   ||    || '|.     ||" + R + "\n"
        a = a + E + "[37;1m" + "|'....|'  .|.  .||. .||...|'   ''|...|'" + R + "\n"
        a = a + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "|''||''|     |      ..|'''.|  '||''''|" + R + "\n"
        a = a + E + "[37;1m" + "   ||       |||    .|'     '   ||  ." + R + "\n"
        a = a + E + "[37;1m" + "   ||      |  ||   ||    ....  ||''|" + R + "\n"
        a = a + E + "[37;1m" + "   ||     .''''|.  '|.    ||   ||" + R + "\n"
        a = a + E + "[37;1m" + "  .||.   .|.  .||.  ''|...'|  .||.....|" + R + "\n"
        emit a
    }
    if startsWith(dn, "sailfish") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                 _a@b" + R + "\n"
        a = a + E + "[34;1m" + "              _#b (b" + R + "\n"
        a = a + E + "[34;1m" + "            _@@   @_         _," + R + "\n"
        a = a + E + "[34;1m" + "          _#^@ _#*^^*gg,aa@^^" + R + "\n"
        a = a + E + "[34;1m" + "          #- @@^  _a@^^" + R + "\n"
        a = a + E + "[34;1m" + "          @_  *g#b" + R + "\n"
        a = a + E + "[34;1m" + "          ^@_   ^@_" + R + "\n"
        a = a + E + "[34;1m" + "            ^@_   @" + R + "\n"
        a = a + E + "[34;1m" + "             @(b (b" + R + "\n"
        a = a + E + "[34;1m" + "            #b(b#^" + R + "\n"
        a = a + E + "[34;1m" + "          _@_#@^" + R + "\n"
        a = a + E + "[34;1m" + "       _a@a*^" + R + "\n"
        a = a + E + "[34;1m" + "   ,a@*^" + R + "\n"
        emit a
    }
    if startsWith(dn, "salentos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                 ``..``" + R + "\n"
        a = a + E + "[32;1m" + "        .-:+oshdNMMMMMMNdhyo+:-.`" + R + "\n"
        a = a + E + "[32;1m" + "  -oydmMMMMMMMMMMMMMMMMMMMMMMMMMMNdhs/" + R + "\n"
        a = a + E + "[32;1m" + E + "[37;1m" + " +hdddm" + E + "[32;1m" + "NMMMMMMMMMMMMMMMMMMMMMMMMN" + E + "[37;1m" + "mdddh+`" + R + "\n"
        a = a + E + "[37;1m" + E + "[31;1m" + "`MMMMMN" + E + "[37;1m" + "mdddddm" + E + "[32;1m" + "MMMMMMMMMMMM" + E + "[37;1m" + "mdddddm" + E + "[33;1m" + "NMMMMM-" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " mMMMMMMMMMMMN" + E + "[37;1m" + "ddddhyyhhddd" + E + "[33;1m" + "NMMMMMMMMMMMM`" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " dMMMMMMMMMMMMMMMMM" + E + "[37;1m" + "oo" + E + "[33;1m" + "MMMMMMMMMMMMMMMMMN`" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " yMMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " +MMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMMy" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " :MMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMMo" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " .MMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMM/" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + " `NMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMM-" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "  mMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMN`" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "  hMMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMm" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "  /MMMMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMMMMy" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "   .+hMMMMMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMMMMMms:" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "      `:smMMMMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMMMMNh+." + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "          .+hMMMMMM" + E + "[37;1m" + "hh" + E + "[33;1m" + "MMMMMMdo:" + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + "             `:smMM" + E + "[37;1m" + "yy" + E + "[33;1m" + "MMNy/`" + R + "\n"
        a = a + E + "[33;1m" + "                 " + E + "[31;1m" + ".- " + E + "[37;1m" + "`" + E + "[33;1m" + ":." + R + "\n"
        emit a
    }
    if startsWith(dn, "swagarch") {
        a = a + E + "[34;1m" + E + "[37;1m" + "        .;ldkOKXXNNNNXXK0Oxoc,." + R + "\n"
        a = a + E + "[37;1m" + "   ,lkXMMNK0OkkxkkOKWMMMMMMMMMM;" + R + "\n"
        a = a + E + "[37;1m" + " 'K0xo  ..,;:c:.     `'lKMMMMM0" + R + "\n"
        a = a + E + "[37;1m" + "     .lONMMMMMM'         `lNMk'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "    ;WMMMMMMMMMO.              " + E + "[34;1m" + "....::..." + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "    OMMMMMMMMMMMMKl.       " + E + "[34;1m" + ".,;;;;;ccccccc," + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "    `0MMMMMMMMMMMMMM0:         " + E + "[34;1m" + ".. .ccccccc." + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "      'kWMMMMMMMMMMMMMNo.   " + E + "[34;1m" + ".,:'  .ccccccc." + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "        `c0MMMMMMMMMMMMMN," + E + "[34;1m" + ",:c;    :cccccc:" + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + " ckl.      `lXMMMMMMMMMX" + E + "[34;1m" + "occcc:.. ;ccccccc." + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "dMMMMXd,     `OMMMMMMWk" + E + "[34;1m" + "ccc;:''` ,ccccccc:" + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "XMMMMMMMWKkxxOWMMMMMNo" + E + "[34;1m" + "ccc;     .cccccccc." + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + " `':ldxO0KXXXXXK0Okdo" + E + "[34;1m" + "cccc.     :cccccccc." + R + "\n"
        a = a + E + "[34;1m" + "                    :ccc:'     `cccccccc:," + R + "\n"
        a = a + E + "[34;1m" + "                                   ''" + R + "\n"
        emit a
    }
    if startsWith(dn, "trisquel") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                         ▄▄▄▄▄▄" + R + "\n"
        a = a + E + "[34;1m" + "                      ▄█████████▄" + R + "\n"
        a = a + E + "[34;1m" + "      ▄▄▄▄▄▄         ████▀   ▀████" + R + "\n"
        a = a + E + "[34;1m" + "   ▄██████████▄     ████▀   ▄▄ ▀███" + R + "\n"
        a = a + E + "[34;1m" + " ▄███▀▀   ▀▀████     ███▄   ▄█   ███" + R + "\n"
        a = a + E + "[34;1m" + "▄███   ▄▄▄   ████▄    ▀██████   ▄███" + R + "\n"
        a = a + E + "[34;1m" + "███   █▀▀██▄  █████▄     ▀▀   ▄████" + R + "\n"
        a = a + E + "[34;1m" + "▀███      ███  ███████▄▄  ▄▄██████" + R + "\n"
        a = a + E + "[34;1m" + E + "[34;1m" + " ▀███▄   ▄███  █████████████" + E + "[36;1m" + "████▀" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "  ▀█████████    ███████" + E + "[36;1m" + "███▀▀▀" + R + "\n"
        a = a + E + "[36;1m" + "    ▀▀███▀▀     ██████▀▀" + R + "\n"
        a = a + E + "[36;1m" + "               ██████▀   ▄▄▄▄" + R + "\n"
        a = a + E + "[36;1m" + "              █████▀   ████████" + R + "\n"
        a = a + E + "[36;1m" + "              █████   ███▀  ▀███" + R + "\n"
        a = a + E + "[36;1m" + "               ████▄   ██▄▄▄  ███" + R + "\n"
        a = a + E + "[36;1m" + "                █████▄   ▀▀  ▄██" + R + "\n"
        a = a + E + "[36;1m" + "                  ██████▄▄▄████" + R + "\n"
        a = a + E + "[36;1m" + "                     ▀▀█████▀▀" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_9(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "anarchy") {
        a = a + E + "[37;1m" + "                         " + E + "[34;1m" + ".." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                        " + E + "[34;1m" + ".." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                      " + E + "[34;1m" + ":.." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                    " + E + "[34;1m" + ":+++." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "              .:::++" + E + "[34;1m" + "++++" + E + "[37;1m" + "+::." + R + "\n"
        a = a + E + "[37;1m" + "          .:+######" + E + "[34;1m" + "++++" + E + "[37;1m" + "######+:." + R + "\n"
        a = a + E + "[37;1m" + "       .+#########" + E + "[34;1m" + "+++++" + E + "[37;1m" + "##########:." + R + "\n"
        a = a + E + "[37;1m" + "     .+##########" + E + "[34;1m" + "+++++++" + E + "[37;1m" + "##" + E + "[34;1m" + "+" + E + "[37;1m" + "#########+." + R + "\n"
        a = a + E + "[37;1m" + "    +###########" + E + "[34;1m" + "+++++++++" + E + "[37;1m" + "############:" + R + "\n"
        a = a + E + "[37;1m" + "   +##########" + E + "[34;1m" + "++++++" + E + "[37;1m" + "#" + E + "[34;1m" + "++++" + E + "[37;1m" + "#" + E + "[34;1m" + "+" + E + "[37;1m" + "###########+" + R + "\n"
        a = a + E + "[37;1m" + "  +###########" + E + "[34;1m" + "+++++" + E + "[37;1m" + "###" + E + "[34;1m" + "++++" + E + "[37;1m" + "#" + E + "[34;1m" + "+" + E + "[37;1m" + "###########+" + R + "\n"
        a = a + E + "[37;1m" + " :##########" + E + "[34;1m" + "+" + E + "[37;1m" + "#" + E + "[34;1m" + "++++" + E + "[37;1m" + "####" + E + "[34;1m" + "++++" + E + "[37;1m" + "#" + E + "[34;1m" + "+" + E + "[37;1m" + "############:" + R + "\n"
        a = a + E + "[37;1m" + " ###########" + E + "[34;1m" + "+++++" + E + "[37;1m" + "#####" + E + "[34;1m" + "+++++" + E + "[37;1m" + "#" + E + "[34;1m" + "+" + E + "[37;1m" + "###" + E + "[34;1m" + "++" + E + "[37;1m" + "######+" + R + "\n"
        a = a + E + "[37;1m" + ".##########" + E + "[34;1m" + "++++++" + E + "[37;1m" + "#####" + E + "[34;1m" + "++++++++++++" + E + "[37;1m" + "#######." + R + "\n"
        a = a + E + "[37;1m" + ".##########" + E + "[34;1m" + "+++++++++++++++++++" + E + "[37;1m" + "###########." + R + "\n"
        a = a + E + "[37;1m" + " #####" + E + "[34;1m" + "++++++++++++++" + E + "[37;1m" + "###" + E + "[34;1m" + "++++++++" + E + "[37;1m" + "#########+" + R + "\n"
        a = a + E + "[37;1m" + " :###" + E + "[34;1m" + "++++++++++" + E + "[37;1m" + "#########" + E + "[34;1m" + "+++++++" + E + "[37;1m" + "#########:" + R + "\n"
        a = a + E + "[37;1m" + "  +######" + E + "[34;1m" + "+++++" + E + "[37;1m" + "##########" + E + "[34;1m" + "++++++++" + E + "[37;1m" + "#######+" + R + "\n"
        a = a + E + "[37;1m" + "   +####" + E + "[34;1m" + "+++++" + E + "[37;1m" + "###########" + E + "[34;1m" + "+++++++++" + E + "[37;1m" + "#####+" + R + "\n"
        a = a + E + "[37;1m" + "    :##" + E + "[34;1m" + "++++++" + E + "[37;1m" + "############" + E + "[34;1m" + "++++++++++" + E + "[37;1m" + "##:" + R + "\n"
        a = a + E + "[37;1m" + "     ." + E + "[34;1m" + "++++++" + E + "[37;1m" + "#############" + E + "[34;1m" + "++++++++++" + E + "[37;1m" + "+." + R + "\n"
        a = a + E + "[37;1m" + "      :" + E + "[34;1m" + "++++" + E + "[37;1m" + "###############" + E + "[34;1m" + "+++++++" + E + "[37;1m" + "::" + R + "\n"
        a = a + E + "[37;1m" + "     ." + E + "[34;1m" + "++. .:+" + E + "[37;1m" + "##############" + E + "[34;1m" + "+++++++" + E + "[37;1m" + ".." + R + "\n"
        a = a + E + "[37;1m" + "     " + E + "[34;1m" + ".:." + E + "[37;1m" + "      ..::++++++::..:" + E + "[34;1m" + "++++" + E + "[37;1m" + "+." + R + "\n"
        a = a + E + "[37;1m" + "     " + E + "[34;1m" + "." + E + "[37;1m" + "                       " + E + "[34;1m" + ".:+++" + E + "[37;1m" + "." + R + "\n"
        a = a + E + "[37;1m" + "                                " + E + "[34;1m" + ".:" + E + "[37;1m" + ":" + R + "\n"
        a = a + E + "[37;1m" + "                                   " + E + "[34;1m" + ".." + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "                                    " + E + "[34;1m" + ".." + E + "[37;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "android") {
        a = a + E + "[32;1m" + E + "[32;1m" + "         -o          o-" + R + "\n"
        a = a + E + "[32;1m" + "          +hydNNNNdyh+" + R + "\n"
        a = a + E + "[32;1m" + "        +mMMMMMMMMMMMMm+" + R + "\n"
        a = a + E + "[32;1m" + "      `dMM" + E + "[37;1m" + "m:" + E + "[32;1m" + "NMMMMMMN" + E + "[37;1m" + ":m" + E + "[32;1m" + "MMd`" + R + "\n"
        a = a + E + "[32;1m" + "      hMMMMMMMMMMMMMMMMMMh" + R + "\n"
        a = a + E + "[32;1m" + "  ..  yyyyyyyyyyyyyyyyyyyy  .." + R + "\n"
        a = a + E + "[32;1m" + ".mMMm`MMMMMMMMMMMMMMMMMMMM`mMMm." + R + "\n"
        a = a + E + "[32;1m" + ":MMMM-MMMMMMMMMMMMMMMMMMMM-MMMM:" + R + "\n"
        a = a + E + "[32;1m" + ":MMMM-MMMMMMMMMMMMMMMMMMMM-MMMM:" + R + "\n"
        a = a + E + "[32;1m" + ":MMMM-MMMMMMMMMMMMMMMMMMMM-MMMM:" + R + "\n"
        a = a + E + "[32;1m" + ":MMMM-MMMMMMMMMMMMMMMMMMMM-MMMM:" + R + "\n"
        a = a + E + "[32;1m" + "-MMMM-MMMMMMMMMMMMMMMMMMMM-MMMM-" + R + "\n"
        a = a + E + "[32;1m" + " +yy+ MMMMMMMMMMMMMMMMMMMM +yy+" + R + "\n"
        a = a + E + "[32;1m" + "      mMMMMMMMMMMMMMMMMMMm" + R + "\n"
        a = a + E + "[32;1m" + "      `/++MMMMh++hMMMM++/`" + R + "\n"
        a = a + E + "[32;1m" + "          MMMMo  oMMMM" + R + "\n"
        a = a + E + "[32;1m" + "          MMMMo  oMMMM" + R + "\n"
        a = a + E + "[32;1m" + "          oNMm-  -mMNs" + R + "\n"
        emit a
    }
    if startsWith(dn, "aosc os") {
        a = a + E + "[34;1m" + E + "[37;1m" + "             .:+syhhhhys+:." + R + "\n"
        a = a + E + "[37;1m" + "         .ohNMMMMMMMMMMMMMMNho." + R + "\n"
        a = a + E + "[37;1m" + "      `+mMMMMMMMMMMmdmNMMMMMMMMm+`" + R + "\n"
        a = a + E + "[37;1m" + "     +NMMMMMMMMMMMM/   `./smMMMMMN+" + R + "\n"
        a = a + E + "[37;1m" + "   .mMMMMMMMMMMMMMMo        -yMMMMMm." + R + "\n"
        a = a + E + "[37;1m" + "  :NMMMMMMMMMMMMMMMs          .hMMMMN:" + R + "\n"
        a = a + E + "[37;1m" + " .NMMMMhmMMMMMMMMMMm+/-         oMMMMN." + R + "\n"
        a = a + E + "[37;1m" + " dMMMMs  ./ymMMMMMMMMMMNy.       sMMMMd" + R + "\n"
        a = a + E + "[37;1m" + "-MMMMN`      oMMMMMMMMMMMN:      `NMMMM-" + R + "\n"
        a = a + E + "[37;1m" + "/MMMMh       NMMMMMMMMMMMMm       hMMMM/" + R + "\n"
        a = a + E + "[37;1m" + "/MMMMh       NMMMMMMMMMMMMm       hMMMM/" + R + "\n"
        a = a + E + "[37;1m" + "-MMMMN`      :MMMMMMMMMMMMy.     `NMMMM-" + R + "\n"
        a = a + E + "[37;1m" + " dMMMMs       .yNMMMMMMMMMMMNy/. sMMMMd" + R + "\n"
        a = a + E + "[37;1m" + " .NMMMMo         -/+sMMMMMMMMMMMmMMMMN." + R + "\n"
        a = a + E + "[37;1m" + "  :NMMMMh.          .MMMMMMMMMMMMMMMN:" + R + "\n"
        a = a + E + "[37;1m" + "   .mMMMMMy-         NMMMMMMMMMMMMMm." + R + "\n"
        a = a + E + "[37;1m" + "     +NMMMMMms/.`    mMMMMMMMMMMMN+" + R + "\n"
        a = a + E + "[37;1m" + "      `+mMMMMMMMMNmddMMMMMMMMMMm+`" + R + "\n"
        a = a + E + "[37;1m" + "         .ohNMMMMMMMMMMMMMMNho." + R + "\n"
        a = a + E + "[37;1m" + "             .:+syhhhhys+:." + R + "\n"
        emit a
    }
    if startsWith(dn, "archbox") {
        a = a + E + "[32;1m" + E + "[32;1m" + "              ...:+oh/:::.." + R + "\n"
        a = a + E + "[32;1m" + "         ..-/oshhhhhh`   `::::-." + R + "\n"
        a = a + E + "[32;1m" + "     .:/ohhhhhhhhhhhh`        `-::::." + R + "\n"
        a = a + E + "[32;1m" + " .+shhhhhhhhhhhhhhhhh`             `.::-." + R + "\n"
        a = a + E + "[32;1m" + " /`-:+shhhhhhhhhhhhhh`            .-/+shh" + R + "\n"
        a = a + E + "[32;1m" + " /      .:/ohhhhhhhhh`       .:/ohhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /           `-:+shhh`  ..:+shhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /                 .:ohhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /                  `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /                  `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /                  `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /                  `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /      .+o+        `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /     -hhhhh       `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /     ohhhhho      `hhhhhhhhhhhhhhhhhhhh" + R + "\n"
        a = a + E + "[32;1m" + " /:::+`hhhhoos`     `hhhhhhhhhhhhhhhhhs+`" + R + "\n"
        a = a + E + "[32;1m" + "    `--/:`   /:     `hhhhhhhhhhhho/-" + R + "\n"
        a = a + E + "[32;1m" + "             -/:.   `hhhhhhs+:-`" + R + "\n"
        a = a + E + "[32;1m" + "                ::::/ho/-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "bedrock") {
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "---" + E + "[37;1m" + "\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\" + E + "[38;5;8m" + "-----------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "----" + E + "[37;1m" + "\\\\\\\\\\\\      \\\\\\\\\\\\" + E + "[38;5;8m" + "----------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "-----" + E + "[37;1m" + "\\\\\\\\\\\\      \\\\\\\\\\\\" + E + "[38;5;8m" + "---------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "------" + E + "[37;1m" + "\\\\\\\\\\\\      \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\" + E + "[38;5;8m" + "------" + R + "\n"
        a = a + E + "[38;5;8m" + "-------" + E + "[37;1m" + "\\\\\\\\\\\\                    \\\\\\\\\\\\" + E + "[38;5;8m" + "-----" + R + "\n"
        a = a + E + "[38;5;8m" + "--------" + E + "[37;1m" + "\\\\\\\\\\\\                    \\\\\\\\\\\\" + E + "[38;5;8m" + "----" + R + "\n"
        a = a + E + "[38;5;8m" + "---------" + E + "[37;1m" + "\\\\\\\\\\\\        ______      \\\\\\\\\\\\" + E + "[38;5;8m" + "---" + R + "\n"
        a = a + E + "[38;5;8m" + "----------" + E + "[37;1m" + "\\\\\\\\\\\\                   ///" + E + "[38;5;8m" + "---" + R + "\n"
        a = a + E + "[38;5;8m" + "-----------" + E + "[37;1m" + "\\\\\\\\\\\\                 ///" + E + "[38;5;8m" + "----" + R + "\n"
        a = a + E + "[38;5;8m" + "------------" + E + "[37;1m" + "\\\\\\\\\\\\               ///" + E + "[38;5;8m" + "-----" + R + "\n"
        a = a + E + "[38;5;8m" + "-------------" + E + "[37;1m" + "\\\\\\\\\\\\////////////////" + E + "[38;5;8m" + "------" + R + "\n"
        a = a + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        a = a + E + "[38;5;8m" + "--------------------------------------" + R + "\n"
        emit a
    }
    if startsWith(dn, "blankon") {
        a = a + E + "[31;1m" + E + "[37;1m" + "        `./ohdNMMMMNmho+.` " + E + "[31;1m" + "       .+oo:`" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "      -smMMMMMMMMMMMMMMMMmy-`    " + E + "[31;1m" + "`yyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "   `:dMMMMMMMMMMMMMMMMMMMMMMd/`  " + E + "[31;1m" + "`yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "  .hMMMMMMMNmhso/++symNMMMMMMMh- " + E + "[31;1m" + "`yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + " -mMMMMMMms-`         -omMMMMMMN-" + E + "[31;1m" + ".yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + ".mMMMMMMy.              .yMMMMMMm:" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "sMMMMMMy                 `sMMMMMMh" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "NMMMMMN:                  .NMMMMMN" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "MMMMMMm.                   NMMMMMN" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "hMMMMMM+                  /MMMMMMN" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + ":NMMMMMN:                :mMMMMMM+" + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + " oMMMMMMNs-            .sNMMMMMMs." + E + "[31;1m" + "yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "  +MMMMMMMNho:.`  `.:ohNMMMMMMNo " + E + "[31;1m" + "`yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "   -hMMMMMMMMNNNmmNNNMMMMMMMMh-  " + E + "[31;1m" + "`yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "     :yNMMMMMMMMMMMMMMMMMMNy:`   " + E + "[31;1m" + "`yyyyys" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "       .:sdNMMMMMMMMMMNds/.      " + E + "[31;1m" + "`yyyyyo" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "           `.:/++++/:.`           " + E + "[31;1m" + ":oys+." + R + "\n"
        emit a
    }
    if startsWith(dn, "chapeau") {
        a = a + E + "[32;1m" + E + "[32;1m" + "               .-/-." + R + "\n"
        a = a + E + "[32;1m" + "            ////////." + R + "\n"
        a = a + E + "[32;1m" + "          ////////" + E + "[37;1m" + "y+" + E + "[32;1m" + "//." + R + "\n"
        a = a + E + "[32;1m" + "        ////////" + E + "[37;1m" + "mMN" + E + "[32;1m" + "/////." + R + "\n"
        a = a + E + "[32;1m" + "      ////////" + E + "[37;1m" + "mMN+" + E + "[32;1m" + "////////." + R + "\n"
        a = a + E + "[32;1m" + "    ////////////////////////." + R + "\n"
        a = a + E + "[32;1m" + "  /////////+" + E + "[37;1m" + "shhddhyo" + E + "[32;1m" + "+////////." + R + "\n"
        a = a + E + "[32;1m" + " ////////" + E + "[37;1m" + "ymMNmdhhdmNNdo" + E + "[32;1m" + "///////." + R + "\n"
        a = a + E + "[32;1m" + "///////+" + E + "[37;1m" + "mMms" + E + "[32;1m" + "////////" + E + "[37;1m" + "hNMh" + E + "[32;1m" + "///////." + R + "\n"
        a = a + E + "[32;1m" + "///////" + E + "[37;1m" + "NMm+" + E + "[32;1m" + "//////////" + E + "[37;1m" + "sMMh" + E + "[32;1m" + "///////" + R + "\n"
        a = a + E + "[32;1m" + "//////" + E + "[37;1m" + "oMMNmmmmmmmmmmmmMMm" + E + "[32;1m" + "///////" + R + "\n"
        a = a + E + "[32;1m" + "//////" + E + "[37;1m" + "+MMmssssssssssssss+" + E + "[32;1m" + "///////" + R + "\n"
        a = a + E + "[32;1m" + "`//////" + E + "[37;1m" + "yMMy" + E + "[32;1m" + "////////////////////" + R + "\n"
        a = a + E + "[32;1m" + " `//////" + E + "[37;1m" + "smMNhso++oydNm" + E + "[32;1m" + "////////" + R + "\n"
        a = a + E + "[32;1m" + "  `///////" + E + "[37;1m" + "ohmNMMMNNdy+" + E + "[32;1m" + "///////" + R + "\n"
        a = a + E + "[32;1m" + "    `//////////" + E + "[37;1m" + "++" + E + "[32;1m" + "//////////" + R + "\n"
        a = a + E + "[32;1m" + "       `////////////////." + R + "\n"
        a = a + E + "[32;1m" + "           -////////-" + R + "\n"
        emit a
    }
    if startsWith(dn, "clearos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "             `.--::::::--.`" + R + "\n"
        a = a + E + "[32;1m" + "         .-:////////////////:-." + R + "\n"
        a = a + E + "[32;1m" + "      `-////////////////////////-`" + R + "\n"
        a = a + E + "[32;1m" + "     -////////////////////////////-" + R + "\n"
        a = a + E + "[32;1m" + "   `//////////////-..-//////////////`" + R + "\n"
        a = a + E + "[32;1m" + "  ./////////////:      ://///////////." + R + "\n"
        a = a + E + "[32;1m" + " `//////:..-////:      :////-..-//////`" + R + "\n"
        a = a + E + "[32;1m" + " ://////`    -///:.``.:///-`    ://///:" + R + "\n"
        a = a + E + "[32;1m" + "`///////:.     -////////-`    `:///////`" + R + "\n"
        a = a + E + "[32;1m" + ".//:--////:.     -////-`    `:////--://." + R + "\n"
        a = a + E + "[32;1m" + "./:    .////:.     --`    `:////-    :/." + R + "\n"
        a = a + E + "[32;1m" + "`//-`    .////:.        `:////-    `-//`" + R + "\n"
        a = a + E + "[32;1m" + " :///-`    .////:.    `:////-    `-///:" + R + "\n"
        a = a + E + "[32;1m" + " `/////-`    -///:    :///-    `-/////`" + R + "\n"
        a = a + E + "[32;1m" + "  `//////-   `///:    :///`   .//////`" + R + "\n"
        a = a + E + "[32;1m" + "   `:////:   `///:    :///`   -////:`" + R + "\n"
        a = a + E + "[32;1m" + "     .://:   `///:    :///`   -//:." + R + "\n"
        a = a + E + "[32;1m" + "       .::   `///:    :///`   -:." + R + "\n"
        a = a + E + "[32;1m" + "             `///:    :///`" + R + "\n"
        a = a + E + "[32;1m" + "              `...    ...`" + R + "\n"
        emit a
    }
    if startsWith(dn, "condres") {
        a = a + E + "[32;1m" + E + "[32;1m" + "syyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy+" + E + "[36;1m" + ".+." + R + "\n"
        a = a + E + "[36;1m" + E + "[32;1m" + "`oyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy+" + E + "[36;1m" + ":++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/o" + E + "[32;1m" + "+oyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy/" + E + "[36;1m" + "oo++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/y+" + E + "[32;1m" + "syyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + E + "[36;1m" + "+ooo++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hy+" + E + "[32;1m" + "oyyyhhhhhhhhhhhhhhyyyyyyyyy" + E + "[36;1m" + "+oo+++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhh+" + E + "[32;1m" + "shhhhhdddddhhhhhhhyyyyyyy" + E + "[36;1m" + "+oo++++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhdd+" + E + "[32;1m" + "oddddddddddddhhhhhyyyys" + E + "[36;1m" + "+oo+++++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhddd+" + E + "[32;1m" + "odmmmdddddddhhhhyyyy" + E + "[36;1m" + "+ooo++++++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhdddmo" + E + "[32;1m" + "odmmmdddddhhhhhyyy" + E + "[36;1m" + "+oooo++++++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hdddmmms" + E + "[32;1m" + "/dmdddddhhhhyyys" + E + "[36;1m" + "+oooo+++++++++." + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hddddmmmy" + E + "[32;1m" + "/hdddhhhhyyyyo" + E + "[36;1m" + "+oooo++++++++++:" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhdddmmmmy" + E + "[32;1m" + ":yhhhhyyyyy+" + E + "[36;1m" + "+oooo+++++++++++:" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhddddddddy" + E + "[32;1m" + "-syyyyyys+" + E + "[36;1m" + "ooooo++++++++++++:" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhhddddddddy" + E + "[32;1m" + "-+yyyy+" + E + "[36;1m" + "/ooooo+++++++++++++:" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhhhhdddddhhy" + E + "[32;1m" + "./yo:" + E + "[36;1m" + "+oooooo+++++++++++++/" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "/hhhhhhhhhhhhhy" + E + "[32;1m" + ":-." + E + "[36;1m" + "+sooooo+++++++++++///:" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + ":sssssssssssso++" + E + "[32;1m" + E + "[36;1m" + "`:/:--------.````````" + R + "\n"
        emit a
    }
    if startsWith(dn, "cyberos") {
        a = a + E + "[38;5;50m" + E + "[38;5;57m" + "             !M$EEEEEEEEEEEP" + R + "\n"
        a = a + E + "[38;5;57m" + "            .MMMMM000000Nr." + R + "\n"
        a = a + E + "[38;5;57m" + "            " + E + "[38;5;57m" + "&MMMMMM" + E + "[38;5;32m" + "MMMMMMMMMMMMM9" + R + "\n"
        a = a + E + "[38;5;32m" + "           " + E + "[38;5;57m" + "~MMM" + E + "[38;5;50m" + "MMMM" + E + "[38;5;32m" + "MMMMMMMMMMMMC" + R + "\n"
        a = a + E + "[38;5;32m" + "      " + E + "[38;5;50m" + "\"    " + E + "[38;5;57m" + "M" + E + "[38;5;50m" + "MMMMMMM" + E + "[38;5;32m" + "MMMMMMMMMMs" + R + "\n"
        a = a + E + "[38;5;32m" + "    " + E + "[38;5;50m" + "iM" + E + "[38;5;32m" + "MMM&&" + E + "[38;5;50m" + "MMMMMMMM" + E + "[38;5;32m" + "MMMMMMMM\\\\" + R + "\n"
        a = a + E + "[38;5;32m" + "   " + E + "[38;5;50m" + "BMMM" + E + "[38;5;32m" + "MMMMM" + E + "[38;5;50m" + "MMMMMMM" + E + "[38;5;32m" + "MMMMMM" + E + "[38;5;57m" + "\"" + R + "\n"
        a = a + E + "[38;5;57m" + "  " + E + "[38;5;50m" + "9MMMMM" + E + "[38;5;32m" + "MMMMMMM" + E + "[38;5;50m" + "MMMM" + E + "[38;5;32m" + "MMMM" + E + "[38;5;57m" + "MMMf-" + R + "\n"
        a = a + E + "[38;5;57m" + "        " + E + "[38;5;32m" + "sMMMMMMMM" + E + "[38;5;50m" + "MM" + E + "[38;5;32m" + "M" + E + "[38;5;57m" + "MMMMMMMMM3_" + R + "\n"
        a = a + E + "[38;5;57m" + "         " + E + "[38;5;32m" + "+ffffffff" + E + "[38;5;50m" + "P" + E + "[38;5;57m" + "MMMMMMMMMMMM0" + R + "\n"
        a = a + E + "[38;5;57m" + "                    " + E + "[38;5;32m" + "CMMMMMMMMMMM" + R + "\n"
        a = a + E + "[38;5;32m" + "                      }MMMMMMMMM" + R + "\n"
        a = a + E + "[38;5;32m" + "                        ~MMMMMMM" + R + "\n"
        a = a + E + "[38;5;32m" + "                          \"RMMMM" + R + "\n"
        a = a + E + "[38;5;32m" + "                            .PMB" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_10(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "drauger") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                  -``-" + R + "\n"
        a = a + E + "[31;1m" + "                `:+``+:`" + R + "\n"
        a = a + E + "[31;1m" + "               `/++``++/." + R + "\n"
        a = a + E + "[31;1m" + "              .++/.  ./++." + R + "\n"
        a = a + E + "[31;1m" + "             :++/`    `/++:" + R + "\n"
        a = a + E + "[31;1m" + "           `/++:        :++/`" + R + "\n"
        a = a + E + "[31;1m" + "          ./+/-          -/+/." + R + "\n"
        a = a + E + "[31;1m" + "         -++/.            ./++-" + R + "\n"
        a = a + E + "[31;1m" + "        :++:`              `:++:" + R + "\n"
        a = a + E + "[31;1m" + "      `/++-                  -++/`" + R + "\n"
        a = a + E + "[31;1m" + "     ./++.                    ./+/." + R + "\n"
        a = a + E + "[31;1m" + "    -++/`                      `/++-" + R + "\n"
        a = a + E + "[31;1m" + "   :++:`                        `:++:" + R + "\n"
        a = a + E + "[31;1m" + " `/++-                            -++/`" + R + "\n"
        a = a + E + "[31;1m" + ".:-.`..............................`.-:." + R + "\n"
        a = a + E + "[31;1m" + "`.-/++++++++++++++++++++++++++++++++/-.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "endless") {
        a = a + E + "[31;1m" + E + "[31;1m" + "           `:+yhmNMMMMNmhy+:`" + R + "\n"
        a = a + E + "[31;1m" + "        -odMMNhso//////oshNMMdo-" + R + "\n"
        a = a + E + "[31;1m" + "      /dMMh+.              .+hMMd/" + R + "\n"
        a = a + E + "[31;1m" + "    /mMNo`                    `oNMm:" + R + "\n"
        a = a + E + "[31;1m" + "  `yMMo`                        `oMMy`" + R + "\n"
        a = a + E + "[31;1m" + " `dMN-                            -NMd`" + R + "\n"
        a = a + E + "[31;1m" + " hMN.                              .NMh" + R + "\n"
        a = a + E + "[31;1m" + "/MM/                  -os`          /MM/" + R + "\n"
        a = a + E + "[31;1m" + "dMm    `smNmmhs/- `:sNMd+   ``       mMd" + R + "\n"
        a = a + E + "[31;1m" + "MMy    oMd--:+yMMMMMNo.:ohmMMMNy`    yMM" + R + "\n"
        a = a + E + "[31;1m" + "MMy    -NNyyhmMNh+oNMMMMMy:.  dMo    yMM" + R + "\n"
        a = a + E + "[31;1m" + "dMm     `/++/-``/yNNh+/sdNMNddMm-    mMd" + R + "\n"
        a = a + E + "[31;1m" + "/MM/          `dNy:       `-::-     /MM/" + R + "\n"
        a = a + E + "[31;1m" + " hMN.                              .NMh" + R + "\n"
        a = a + E + "[31;1m" + " `dMN-                            -NMd`" + R + "\n"
        a = a + E + "[31;1m" + "  `yMMo`                        `oMMy`" + R + "\n"
        a = a + E + "[31;1m" + "    /mMNo`                    `oNMm/" + R + "\n"
        a = a + E + "[31;1m" + "      /dMMh+.              .+hMMd/" + R + "\n"
        a = a + E + "[31;1m" + "        -odMMNhso//////oshNMMdo-" + R + "\n"
        a = a + E + "[31;1m" + "           `:+yhmNMMMMNmhy+:`" + R + "\n"
        emit a
    }
    if startsWith(dn, "exherbo") {
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
    if startsWith(dn, "glaucus") {
        a = a + E + "[35;1m" + E + "[35;1m" + "             ,,        ,d88P" + R + "\n"
        a = a + E + "[35;1m" + "           ,d8P    ,ad8888*" + R + "\n"
        a = a + E + "[35;1m" + "         ,888P    d88888*     ,,ad8888P*" + R + "\n"
        a = a + E + "[35;1m" + "    d   d888P   a88888P*  ,ad8888888*" + R + "\n"
        a = a + E + "[35;1m" + "  .d8  d8888:  d888888* ,d888888P*" + R + "\n"
        a = a + E + "[35;1m" + " .888; 88888b d8888888b8888888P" + R + "\n"
        a = a + E + "[35;1m" + " d8888J888888a88888888888888P*    ,d" + R + "\n"
        a = a + E + "[35;1m" + " 88888888888888888888888888P   ,,d8*" + R + "\n"
        a = a + E + "[35;1m" + " 888888888888888888888888888888888*" + R + "\n"
        a = a + E + "[35;1m" + " *8888888888888888888888888888888*" + R + "\n"
        a = a + E + "[35;1m" + "  Y888888888P* `*``*888888888888*" + R + "\n"
        a = a + E + "[35;1m" + "   *^888^*            *Y888P**" + R + "\n"
        emit a
    }
    if startsWith(dn, "hydroos") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "  _    _           _            ____   _____" + R + "\n"
        a = a + E + "[31;1m" + " | |  | |         | |          / __ \\ / ____|" + R + "\n"
        a = a + E + "[31;1m" + " | |__| |_   _  __| |_ __ ___ | |  | | (___" + R + "\n"
        a = a + E + "[31;1m" + " |  __  | | | |/ _` | '__/ _ \\| |  | |\\___ \\" + R + "\n"
        a = a + E + "[31;1m" + " | |  | | |_| | (_| | | | (_) | |__| |____) |" + R + "\n"
        a = a + E + "[31;1m" + " |_|  |_|\\__, |\\__,_|_|  \\___/ \\____/|_____/" + R + "\n"
        a = a + E + "[31;1m" + "          __/ |" + R + "\n"
        a = a + E + "[31;1m" + "         |___/" + R + "\n"
        emit a
    }
    if startsWith(dn, "iglunix") || startsWith(dn, "iglu") {
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "     |" + R + "\n"
        a = a + E + "[38;5;8m" + "     |        |" + R + "\n"
        a = a + E + "[38;5;8m" + "              |" + R + "\n"
        a = a + E + "[38;5;8m" + "|    ________" + R + "\n"
        a = a + E + "[38;5;8m" + "|  /\\   |    \\" + R + "\n"
        a = a + E + "[38;5;8m" + "  /  \\  |     \\  |" + R + "\n"
        a = a + E + "[38;5;8m" + " /    \\        \\ |" + R + "\n"
        a = a + E + "[38;5;8m" + "/      \\________\\" + R + "\n"
        a = a + E + "[38;5;8m" + "\\      /        /" + R + "\n"
        a = a + E + "[38;5;8m" + " \\    /        /" + R + "\n"
        a = a + E + "[38;5;8m" + "  \\  /        /" + R + "\n"
        a = a + E + "[38;5;8m" + "   \\/________/" + R + "\n"
        emit a
    }
    if startsWith(dn, "kibojoe") {
        a = a + E + "[32;1m" + "            " + E + "[34;1m" + "           ./+oooooo+/." + R + "\n"
        a = a + E + "[34;1m" + "           -/+ooooo+/:.`" + R + "\n"
        a = a + E + "[34;1m" + "          " + E + "[32;1m" + "`" + E + "[34;1m" + "yyyo" + E + "[37;1m" + "+++/++" + E + "[34;1m" + "osss" + E + "[32;1m" + "." + R + "\n"
        a = a + E + "[32;1m" + "         " + E + "[32;1m" + "+NMN" + E + "[34;1m" + "yssssssssssss" + E + "[32;1m" + "." + R + "\n"
        a = a + E + "[32;1m" + "       " + E + "[32;1m" + ".dMMMMN" + E + "[34;1m" + "sssssssssssy" + E + "[32;1m" + "Ns`" + R + "\n"
        a = a + E + "[32;1m" + "      +MMMMMMMm" + E + "[34;1m" + "sssssssssssh" + E + "[32;1m" + "MNo`" + R + "\n"
        a = a + E + "[32;1m" + "    `hMMMMMNNNMd" + E + "[34;1m" + "sssssssssssd" + E + "[32;1m" + "MMN/" + R + "\n"
        a = a + E + "[32;1m" + "   ." + E + "[34;1m" + "syyyssssssy" + E + "[32;1m" + "NNmmmmd" + E + "[34;1m" + "sssss" + E + "[32;1m" + "hMMMMd:" + R + "\n"
        a = a + E + "[32;1m" + "  -NMmh" + E + "[34;1m" + "yssssssssyhhhhyssyh" + E + "[32;1m" + "mMMMMMMMy`" + R + "\n"
        a = a + E + "[32;1m" + " -NMMMMMNN" + E + "[34;1m" + "mdhyyyyyyyhdm" + E + "[32;1m" + "NMMMMMMMMMMMN+" + R + "\n"
        a = a + E + "[32;1m" + "`NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMd." + R + "\n"
        a = a + E + "[32;1m" + "ods+/:-----://+oyydmNMMMMMMMMMMMMMMMMMN-" + R + "\n"
        a = a + E + "[32;1m" + "`                     .-:+osyhhdmmNNNmdo" + R + "\n"
        emit a
    }
    if startsWith(dn, "kogaion") {
        a = a + E + "[34;1m" + E + "[34;1m" + "            ;;      ,;" + R + "\n"
        a = a + E + "[34;1m" + "           ;;;     ,;;" + R + "\n"
        a = a + E + "[34;1m" + "         ,;;;;     ;;;;" + R + "\n"
        a = a + E + "[34;1m" + "      ,;;;;;;;;    ;;;;" + R + "\n"
        a = a + E + "[34;1m" + "     ;;;;;;;;;;;   ;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "    ,;;;;;;;;;;;;  ';;;;;," + R + "\n"
        a = a + E + "[34;1m" + "    ;;;;;;;;;;;;;;, ';;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "    ;;;;;;;;;;;;;;;;;, ';;;;;" + R + "\n"
        a = a + E + "[34;1m" + ";    ';;;;;;;;;;;;;;;;;;, ;;;" + R + "\n"
        a = a + E + "[34;1m" + ";;;,  ';;;;;;;;;;;;;;;;;;;,;;" + R + "\n"
        a = a + E + "[34;1m" + ";;;;;,  ';;;;;;;;;;;;;;;;;;," + R + "\n"
        a = a + E + "[34;1m" + ";;;;;;;;,  ';;;;;;;;;;;;;;;;," + R + "\n"
        a = a + E + "[34;1m" + ";;;;;;;;;;;;, ';;;;;;;;;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "';;;;;;;;;;;;; ';;;;;;;;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + " ';;;;;;;;;;;;;, ';;;;;;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "  ';;;;;;;;;;;;;  ;;;;;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "    ';;;;;;;;;;;; ;;;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "        ';;;;;;;; ;;;;;;" + R + "\n"
        a = a + E + "[34;1m" + "           ';;;;; ;;;;" + R + "\n"
        a = a + E + "[34;1m" + "             ';;; ;;" + R + "\n"
        emit a
    }
    if startsWith(dn, "kslinux") {
        a = a + E + "[34;1m" + E + "[34;1m" + " K   K U   U RRRR   ooo" + R + "\n"
        a = a + E + "[34;1m" + " K  K  U   U R   R o   o" + R + "\n"
        a = a + E + "[34;1m" + " KKK   U   U RRRR  o   o" + R + "\n"
        a = a + E + "[34;1m" + " K  K  U   U R  R  o   o" + R + "\n"
        a = a + E + "[34;1m" + " K   K  UUU  R   R  ooo" + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + E + "[37;1m" + "  SSS   AAA  W   W  AAA" + R + "\n"
        a = a + E + "[37;1m" + " S     A   A W   W A   A" + R + "\n"
        a = a + E + "[37;1m" + "  SSS  AAAAA W W W AAAAA" + R + "\n"
        a = a + E + "[37;1m" + "     S A   A WW WW A   A" + R + "\n"
        a = a + E + "[37;1m" + "  SSS  A   A W   W A   A" + R + "\n"
        emit a
    }
    if startsWith(dn, "kubuntu") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           `.:/ossyyyysso/:." + R + "\n"
        a = a + E + "[34;1m" + "        .:oyyyyyyyyyyyyyyyyyyo:`" + R + "\n"
        a = a + E + "[34;1m" + "      -oyyyyyyyo" + E + "[37;1m" + "dMMy" + E + "[34;1m" + "yyyyyyysyyyyo-" + R + "\n"
        a = a + E + "[34;1m" + "    -syyyyyyyyyy" + E + "[37;1m" + "dMMy" + E + "[34;1m" + "oyyyy" + E + "[37;1m" + "dmMMy" + E + "[34;1m" + "yyyys-" + R + "\n"
        a = a + E + "[34;1m" + "   oyyys" + E + "[37;1m" + "dMy" + E + "[34;1m" + "syyyy" + E + "[37;1m" + "dMMMMMMMMMMMMMy" + E + "[34;1m" + "yyyyyyo" + R + "\n"
        a = a + E + "[34;1m" + " `oyyyy" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "syysoooooo" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "yyyyyyyyo`" + R + "\n"
        a = a + E + "[34;1m" + " oyyyyyy" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "yyyyyyyyyyys" + E + "[37;1m" + "dMMy" + E + "[34;1m" + "sssssyyyo" + R + "\n"
        a = a + E + "[34;1m" + "-yyyyyyyy" + E + "[37;1m" + "dMy" + E + "[34;1m" + "syyyyyyyyyyyyyys" + E + "[37;1m" + "dMMMMMy" + E + "[34;1m" + "syyy-" + R + "\n"
        a = a + E + "[34;1m" + "oyyyysoo" + E + "[37;1m" + "dMy" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyy" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "syyyo" + R + "\n"
        a = a + E + "[34;1m" + "yyys" + E + "[37;1m" + "dMMMMMy" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyysosyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyys" + E + "[37;1m" + "dMMMMMy" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "oyyyyysos" + E + "[37;1m" + "dy" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyy" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "syyyo" + R + "\n"
        a = a + E + "[34;1m" + "-yyyyyyyy" + E + "[37;1m" + "dMy" + E + "[34;1m" + "syyyyyyyyyyyyyys" + E + "[37;1m" + "dMMMMMy" + E + "[34;1m" + "syyy-" + R + "\n"
        a = a + E + "[34;1m" + " oyyyyyy" + E + "[37;1m" + "dMMMy" + E + "[34;1m" + "syyyyyyyyyyys" + E + "[37;1m" + "dMMy" + E + "[34;1m" + "oyyyoyyyo" + R + "\n"
        a = a + E + "[34;1m" + " `oyyyy" + E + "[37;1m" + "dMMMy" + E + "[34;1m" + "syyyoooooo" + E + "[37;1m" + "dMMMMy" + E + "[34;1m" + "oyyyyyyyyo" + R + "\n"
        a = a + E + "[34;1m" + "   oyyysyyoyyyys" + E + "[37;1m" + "dMMMMMMMMMMMy" + E + "[34;1m" + "yyyyyyyo" + R + "\n"
        a = a + E + "[34;1m" + "    -syyyyyyyyy" + E + "[37;1m" + "dMMMy" + E + "[34;1m" + "syyy" + E + "[37;1m" + "dMMMy" + E + "[34;1m" + "syyyys-" + R + "\n"
        a = a + E + "[34;1m" + "      -oyyyyyyy" + E + "[37;1m" + "dMMy" + E + "[34;1m" + "yyyyyysosyyyyo-" + R + "\n"
        a = a + E + "[34;1m" + "        ./oyyyyyyyyyyyyyyyyyyo/." + R + "\n"
        a = a + E + "[34;1m" + "           `.:/oosyyyysso/:.`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_11(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "laxeros") {
        a = a + E + "[37;1m" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "                    /." + R + "\n"
        a = a + E + "[34;1m" + "                 `://:-" + R + "\n"
        a = a + E + "[34;1m" + "                `//////:" + R + "\n"
        a = a + E + "[34;1m" + "               .////////:`" + R + "\n"
        a = a + E + "[34;1m" + "              -//////////:`" + R + "\n"
        a = a + E + "[34;1m" + "             -/////////////`" + R + "\n"
        a = a + E + "[34;1m" + "            :///////////////." + R + "\n"
        a = a + E + "[34;1m" + "          `://////.```-//////-" + R + "\n"
        a = a + E + "[34;1m" + "         `://///:`     .//////-" + R + "\n"
        a = a + E + "[34;1m" + "        `//////:        `//////:" + R + "\n"
        a = a + E + "[34;1m" + "       .//////-          `://///:`" + R + "\n"
        a = a + E + "[34;1m" + "      -//////-            `://///:`" + R + "\n"
        a = a + E + "[34;1m" + "     -//////.               ://////`" + R + "\n"
        a = a + E + "[34;1m" + "    ://////`                 -//////." + R + "\n"
        a = a + E + "[34;1m" + "   `/////:`                   ./////:" + R + "\n"
        a = a + E + "[34;1m" + "    .-::-`                     .:::-`" + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + ".:://////////////////////////////////::." + R + "\n"
        a = a + E + "[34;1m" + "////////////////////////////////////////" + R + "\n"
        a = a + E + "[34;1m" + ".:////////////////////////////////////:." + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "lubuntu") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           `.:/ossyyyysso/:." + R + "\n"
        a = a + E + "[34;1m" + "        `.:yyyyyyyyyyyyyyyyyy:.`" + R + "\n"
        a = a + E + "[34;1m" + "      .:yyyyyyyyyyyyyyyyyyyyyyyy:." + R + "\n"
        a = a + E + "[34;1m" + "    .:yyyyyyyyyyyyyyyyyyyyyyyyyyyy:." + R + "\n"
        a = a + E + "[34;1m" + "   -yyyyyyyyyyyyyy" + E + "[37;1m" + "+hNMMMNh+" + E + "[34;1m" + "yyyyyyyyy-" + R + "\n"
        a = a + E + "[34;1m" + "  :yy" + E + "[37;1m" + "mNy+" + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + "+Nmso++smMdhyysoo+" + E + "[34;1m" + "yy:" + R + "\n"
        a = a + E + "[34;1m" + " -yy" + E + "[37;1m" + "+MMMmmy" + E + "[34;1m" + "yyyyyy" + E + "[37;1m" + "hh" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyy-" + R + "\n"
        a = a + E + "[34;1m" + ".yyyy" + E + "[37;1m" + "NMN" + E + "[34;1m" + "yy" + E + "[37;1m" + "shhs" + E + "[34;1m" + "yyy" + E + "[37;1m" + "+o" + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyy." + R + "\n"
        a = a + E + "[34;1m" + ":yyyy" + E + "[37;1m" + "oNM+" + E + "[34;1m" + "yyyy" + E + "[37;1m" + "+sso" + E + "[34;1m" + "yyyyyyy" + E + "[37;1m" + "ss" + E + "[34;1m" + "yyyyyyyyyyyyy:" + R + "\n"
        a = a + E + "[34;1m" + ":yyyyy" + E + "[37;1m" + "+dNs" + E + "[34;1m" + "yyyyyyy" + E + "[37;1m" + "++" + E + "[34;1m" + "yyyyy" + E + "[37;1m" + "oN+" + E + "[34;1m" + "yyyyyyyyyyyy:" + R + "\n"
        a = a + E + "[34;1m" + ":yyyyy" + E + "[37;1m" + "oMMmhysso" + E + "[34;1m" + "yyyyyyyyyy" + E + "[37;1m" + "mN+" + E + "[34;1m" + "yyyyyyyyyyy:" + R + "\n"
        a = a + E + "[34;1m" + ":yyyyyy" + E + "[37;1m" + "hMm" + E + "[34;1m" + "yyyyy" + E + "[37;1m" + "+++" + E + "[34;1m" + "yyyyyyy" + E + "[37;1m" + "+MN" + E + "[34;1m" + "yyyyyyyyyyy:" + R + "\n"
        a = a + E + "[34;1m" + ".yyyyyyy" + E + "[37;1m" + "ohmy+" + E + "[34;1m" + "yyyyyyyyyyyyy" + E + "[37;1m" + "NMh" + E + "[34;1m" + "yyyyyyyyyy." + R + "\n"
        a = a + E + "[34;1m" + " -yyyyyyyyyy" + E + "[37;1m" + "++" + E + "[34;1m" + "yyyyyyyyyyyy" + E + "[37;1m" + "MMh" + E + "[34;1m" + "yyyyyyyyy-" + R + "\n"
        a = a + E + "[34;1m" + "  :yyyyyyyyyyyyyyyyyyyyy" + E + "[37;1m" + "+mMN+" + E + "[34;1m" + "yyyyyyyy:" + R + "\n"
        a = a + E + "[34;1m" + "   -yyyyyyyyyyyyyyyyy" + E + "[37;1m" + "+sdMMd+" + E + "[34;1m" + "yyyyyyyy-" + R + "\n"
        a = a + E + "[34;1m" + "    .:yyyyyyyyy" + E + "[37;1m" + "hmdmmNMNdy+" + E + "[34;1m" + "yyyyyyyy:." + R + "\n"
        a = a + E + "[34;1m" + "      .:yyyyyyy" + E + "[37;1m" + "my" + E + "[34;1m" + "yyyyyyyyyyyyyyy:." + R + "\n"
        a = a + E + "[34;1m" + "        `.:yyyy" + E + "[37;1m" + "s" + E + "[34;1m" + "yyyyyyyyyyyyy:.`" + R + "\n"
        a = a + E + "[34;1m" + "           `.:/oosyyyysso/:.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "manjaro") {
        a = a + E + "[32;1m" + E + "[32;1m" + "██████████████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "██████████████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "██████████████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "██████████████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████            ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        a = a + E + "[32;1m" + "████████  ████████  ████████" + R + "\n"
        emit a
    }
    if startsWith(dn, "neptune") {
        a = a + E + "[37;1m" + E + "[37;1m" + "            ./+sydddddddys/-." + R + "\n"
        a = a + E + "[37;1m" + "        .+ymNNdyooo/:+oooymNNmy/`" + R + "\n"
        a = a + E + "[37;1m" + "     `/hNNh/.`             `-+dNNy:`" + R + "\n"
        a = a + E + "[37;1m" + "    /mMd/.          .++.:oy/   .+mMd-" + R + "\n"
        a = a + E + "[37;1m" + "  `sMN/             oMMmdy+.     `oNNo" + R + "\n"
        a = a + E + "[37;1m" + " `hMd.           `/ymy/.           :NMo" + R + "\n"
        a = a + E + "[37;1m" + " oMN-          `/dMd:               /MM-" + R + "\n"
        a = a + E + "[37;1m" + "`mMy          -dMN+`                 mMs" + R + "\n"
        a = a + E + "[37;1m" + ".MMo         -NMM/                   yMs" + R + "\n"
        a = a + E + "[37;1m" + " dMh         mMMMo:`                `NMo" + R + "\n"
        a = a + E + "[37;1m" + " /MM/        /ymMMMm-               sMN." + R + "\n"
        a = a + E + "[37;1m" + "  +Mm:         .hMMd`              oMN/" + R + "\n"
        a = a + E + "[37;1m" + "   +mNs.      `yNd/`             -dMm-" + R + "\n"
        a = a + E + "[37;1m" + "    .yMNs:    `/.`            `/yNNo`" + R + "\n"
        a = a + E + "[37;1m" + "      .odNNy+-`           .:ohNNd/." + R + "\n"
        a = a + E + "[37;1m" + "         -+ymNNmdyyyyyyydmNNmy+." + R + "\n"
        a = a + E + "[37;1m" + "             `-//sssssss//." + R + "\n"
        emit a
    }
    if startsWith(dn, "openbsd") {
        a = a + E + "[33;1m" + E + "[36;1m" + "                                     _" + R + "\n"
        a = a + E + "[36;1m" + "                                    (_)" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "              |    ." + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "          .   |L  /|   .         " + E + "[36;1m" + " _" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "      _ . |\\ _| \\--+._/| .       " + E + "[36;1m" + "(_)" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "     / ||\\| Y J  )   / |/| ./" + R + "\n"
        a = a + E + "[33;1m" + "    J  |)'( |        ` F`.'/       " + E + "[36;1m" + " _" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "  -<|  F         __     .-<        " + E + "[36;1m" + "(_)" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "    | /       .-'" + E + "[36;1m" + ". " + E + "[33;1m" + "`.  /" + E + "[36;1m" + "-. " + E + "[33;1m" + "L___" + R + "\n"
        a = a + E + "[33;1m" + "    J \\\\      <    " + E + "[36;1m" + "\\ " + E + "[33;1m" + " | | " + E + "[38;5;8m" + "O" + E + "[36;1m" + "\\\\" + E + "[33;1m" + "|.-' " + E + "[36;1m" + " _" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + "  _J \\\\  .-    \\\\" + E + "[36;1m" + "/ " + E + "[38;5;8m" + "O " + E + "[36;1m" + "| " + E + "[33;1m" + "| \\\\  |" + E + "[33;1m" + "F    " + E + "[36;1m" + "(_)" + R + "\n"
        a = a + E + "[36;1m" + E + "[33;1m" + " '-F  -<_.     \\\\   .-'  `-' L__" + R + "\n"
        a = a + E + "[33;1m" + "__J  _   _.     >-'  " + E + "[33;1m" + ")" + E + "[31;1m" + "._.   " + E + "[33;1m" + "|-'" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + " `-|.'   /_.          " + E + "[31;1m" + "\\_|  " + E + "[33;1m" + " F" + R + "\n"
        a = a + E + "[33;1m" + "  /.-   .                _.<" + R + "\n"
        a = a + E + "[33;1m" + " /'    /.'             .'  `\\\\" + R + "\n"
        a = a + E + "[33;1m" + "  /L  /'   |/      _.-'-\\\\" + R + "\n"
        a = a + E + "[33;1m" + " /'J       ___.---'\\|" + R + "\n"
        a = a + E + "[33;1m" + "   |\\  .--' V  | `. `" + R + "\n"
        a = a + E + "[33;1m" + "   |/`. `-.     `._)" + R + "\n"
        a = a + E + "[33;1m" + "      / .-.\\\\" + R + "\n"
        a = a + E + "[33;1m" + "      \\\\ (  `\\\\" + R + "\n"
        a = a + E + "[33;1m" + "       `.\\\\" + R + "\n"
        emit a
    }
    if startsWith(dn, "openwrt") {
        a = a + E + "[34;1m" + E + "[34;1m" + " _______" + R + "\n"
        a = a + E + "[34;1m" + "|       |.-----.-----.-----." + R + "\n"
        a = a + E + "[34;1m" + "|   -   ||  _  |  -__|     |" + R + "\n"
        a = a + E + "[34;1m" + "|_______||   __|_____|__|__|" + R + "\n"
        a = a + E + "[34;1m" + "         |__|" + R + "\n"
        a = a + E + "[34;1m" + " ________        __" + R + "\n"
        a = a + E + "[34;1m" + "|  |  |  |.----.|  |_" + R + "\n"
        a = a + E + "[34;1m" + "|  |  |  ||   _||   _|" + R + "\n"
        a = a + E + "[34;1m" + "|________||__|  |____|" + R + "\n"
        emit a
    }
    if startsWith(dn, "pengwin") {
        a = a + E + "[35;1m" + E + "[38;5;13m" + "                     ...`" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;13m" + "                     `-///:-`" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;13m" + "                       .+" + E + "[35;1m" + "ssys" + E + "[38;5;13m" + "/" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;13m" + "                        +" + E + "[35;1m" + "yyyyy" + E + "[38;5;13m" + "o    " + E + "[35;1m" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "                        -yyyyyy:" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "           `.:/+ooo+/:` -yyyyyy+" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "         `:oyyyyyys+:-.`syyyyyy:" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "        .syyyyyyo-`   .oyyyyyyo" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "       `syyyyyy   `-+yyyyyyy/`" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "       /yyyyyy+ -/osyyyyyyo/." + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "       +yyyyyy-  `.-:::-.`" + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "       .yyyyyy-" + R + "\n"
        a = a + E + "[35;1m" + E + "[38;5;13m" + "        :" + E + "[35;1m" + "yyyyy" + E + "[38;5;13m" + "o" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;13m" + "         .+" + E + "[35;1m" + "ooo" + E + "[38;5;13m" + "+" + R + "\n"
        a = a + E + "[38;5;13m" + E + "[38;5;13m" + "           `.::/:." + R + "\n"
        emit a
    }
    if startsWith(dn, "pop!_os") || startsWith(dn, "popos") || startsWith(dn, "pop_os") {
        a = a + E + "[36;1m" + E + "[36;1m" + "             /////////////" + R + "\n"
        a = a + E + "[36;1m" + "         /////////////////////" + R + "\n"
        a = a + E + "[36;1m" + "      ///////" + E + "[37;1m" + "*767" + E + "[36;1m" + "////////////////" + R + "\n"
        a = a + E + "[36;1m" + "    //////" + E + "[37;1m" + "7676767676*" + E + "[36;1m" + "//////////////" + R + "\n"
        a = a + E + "[36;1m" + "   /////" + E + "[37;1m" + "76767" + E + "[36;1m" + "//" + E + "[37;1m" + "7676767" + E + "[36;1m" + "//////////////" + R + "\n"
        a = a + E + "[36;1m" + "  /////" + E + "[37;1m" + "767676" + E + "[36;1m" + "///" + E + "[37;1m" + "*76767" + E + "[36;1m" + "///////////////" + R + "\n"
        a = a + E + "[36;1m" + " ///////" + E + "[37;1m" + "767676" + E + "[36;1m" + "///" + E + "[37;1m" + "76767" + E + "[36;1m" + ".///" + E + "[37;1m" + "7676*" + E + "[36;1m" + "///////" + R + "\n"
        a = a + E + "[36;1m" + "/////////" + E + "[37;1m" + "767676" + E + "[36;1m" + "//" + E + "[37;1m" + "76767" + E + "[36;1m" + "///" + E + "[37;1m" + "767676" + E + "[36;1m" + "////////" + R + "\n"
        a = a + E + "[36;1m" + "//////////" + E + "[37;1m" + "76767676767" + E + "[36;1m" + "////" + E + "[37;1m" + "76767" + E + "[36;1m" + "/////////" + R + "\n"
        a = a + E + "[36;1m" + "///////////" + E + "[37;1m" + "76767676" + E + "[36;1m" + "//////" + E + "[37;1m" + "7676" + E + "[36;1m" + "//////////" + R + "\n"
        a = a + E + "[36;1m" + "////////////," + E + "[37;1m" + "7676" + E + "[36;1m" + ",///////" + E + "[37;1m" + "767" + E + "[36;1m" + "///////////" + R + "\n"
        a = a + E + "[36;1m" + "/////////////*" + E + "[37;1m" + "7676" + E + "[36;1m" + "///////" + E + "[37;1m" + "76" + E + "[36;1m" + "////////////" + R + "\n"
        a = a + E + "[36;1m" + "///////////////" + E + "[37;1m" + "7676" + E + "[36;1m" + "////////////////////" + R + "\n"
        a = a + E + "[36;1m" + " ///////////////" + E + "[37;1m" + "7676" + E + "[36;1m" + "///" + E + "[37;1m" + "767" + E + "[36;1m" + "////////////" + R + "\n"
        a = a + E + "[36;1m" + "  //////////////////////" + E + "[37;1m" + "'" + E + "[36;1m" + "////////////" + R + "\n"
        a = a + E + "[36;1m" + "   //////" + E + "[37;1m" + ".7676767676767676767," + E + "[36;1m" + "//////" + R + "\n"
        a = a + E + "[36;1m" + "    /////" + E + "[37;1m" + "767676767676767676767" + E + "[36;1m" + "/////" + R + "\n"
        a = a + E + "[36;1m" + "      ///////////////////////////" + R + "\n"
        a = a + E + "[36;1m" + "         /////////////////////" + R + "\n"
        a = a + E + "[36;1m" + "             /////////////" + R + "\n"
        emit a
    }
    if startsWith(dn, "porteus") {
        a = a + E + "[36;1m" + E + "[36;1m" + "             `.-:::-.`" + R + "\n"
        a = a + E + "[36;1m" + "         -+ydmNNNNNNNmdy+-" + R + "\n"
        a = a + E + "[36;1m" + "      .+dNmdhs+//////+shdmdo." + R + "\n"
        a = a + E + "[36;1m" + "    .smmy+-`             ./sdy:" + R + "\n"
        a = a + E + "[36;1m" + "  `omdo.    `.-/+osssso+/-` `+dy." + R + "\n"
        a = a + E + "[36;1m" + " `yms.   `:shmNmdhsoo++osyyo-``oh." + R + "\n"
        a = a + E + "[36;1m" + " hm/   .odNmds/.`    ``.....:::-+s" + R + "\n"
        a = a + E + "[36;1m" + "/m:  `+dNmy:`   `./oyhhhhyyooo++so" + R + "\n"
        a = a + E + "[36;1m" + "ys  `yNmy-    .+hmmho:-.`     ```" + R + "\n"
        a = a + E + "[36;1m" + "s:  yNm+`   .smNd+." + R + "\n"
        a = a + E + "[36;1m" + "`` /Nm:    +dNd+`" + R + "\n"
        a = a + E + "[36;1m" + "   yN+   `smNy." + R + "\n"
        a = a + E + "[36;1m" + "   dm    oNNy`" + R + "\n"
        a = a + E + "[36;1m" + "   hy   -mNm." + R + "\n"
        a = a + E + "[36;1m" + "   +y   oNNo" + R + "\n"
        a = a + E + "[36;1m" + "   `y`  sNN:" + R + "\n"
        a = a + E + "[36;1m" + "    `:  +NN:" + R + "\n"
        a = a + E + "[36;1m" + "     `  .mNo" + R + "\n"
        a = a + E + "[36;1m" + "         /mm`" + R + "\n"
        a = a + E + "[36;1m" + "          /my`" + R + "\n"
        a = a + E + "[36;1m" + "           .sy`" + R + "\n"
        a = a + E + "[36;1m" + "             .+:" + R + "\n"
        a = a + E + "[36;1m" + "                `" + R + "\n"
        emit a
    }
    if startsWith(dn, "proxmox") {
        a = a + E + "[37;1m" + E + "[37;1m" + "         .://:`              `://:." + R + "\n"
        a = a + E + "[37;1m" + "       `hMMMMMMd/          /dMMMMMMh`" + R + "\n"
        a = a + E + "[37;1m" + "        `sMMMMMMMd:      :mMMMMMMMs`" + R + "\n"
        a = a + E + "[37;1m" + E + "[38;5;202m" + "`-/+oo+/:" + E + "[37;1m" + "`.yMMMMMMMh-  -hMMMMMMMy.`" + E + "[38;5;202m" + ":/+oo+/-`" + R + "\n"
        a = a + E + "[38;5;202m" + "`:oooooooo/" + E + "[37;1m" + "`-hMMMMMMMyyMMMMMMMh-`" + E + "[38;5;202m" + "/oooooooo:`" + R + "\n"
        a = a + E + "[38;5;202m" + "  `/oooooooo:" + E + "[37;1m" + "`:mMMMMMMMMMMMMm:`" + E + "[38;5;202m" + ":oooooooo/`" + R + "\n"
        a = a + E + "[38;5;202m" + "    ./ooooooo+-" + E + "[37;1m" + " +NMMMMMMMMN+ " + E + "[38;5;202m" + "-+ooooooo/." + R + "\n"
        a = a + E + "[38;5;202m" + "      .+ooooooo+-" + E + "[37;1m" + "`oNMMMMNo`" + E + "[38;5;202m" + "-+ooooooo+." + R + "\n"
        a = a + E + "[38;5;202m" + "        -+ooooooo/." + E + "[37;1m" + "`sMMs`" + E + "[38;5;202m" + "./ooooooo+-" + R + "\n"
        a = a + E + "[38;5;202m" + "          :oooooooo/" + E + "[37;1m" + "`..`" + E + "[38;5;202m" + "/oooooooo:" + R + "\n"
        a = a + E + "[38;5;202m" + "          :oooooooo/`" + E + "[37;1m" + ".." + E + "[38;5;202m" + "`/oooooooo:" + R + "\n"
        a = a + E + "[38;5;202m" + "        -+ooooooo/.`" + E + "[37;1m" + "sMMs" + E + "[38;5;202m" + "`./ooooooo+-" + R + "\n"
        a = a + E + "[38;5;202m" + "      .+ooooooo+-`" + E + "[37;1m" + "oNMMMMNo" + E + "[38;5;202m" + "`-+ooooooo+." + R + "\n"
        a = a + E + "[38;5;202m" + "    ./ooooooo+-" + E + "[37;1m" + " +NMMMMMMMMN+ " + E + "[38;5;202m" + "-+ooooooo/." + R + "\n"
        a = a + E + "[38;5;202m" + "  `/oooooooo:`" + E + "[37;1m" + ":mMMMMMMMMMMMMm:" + E + "[38;5;202m" + "`:oooooooo/`" + R + "\n"
        a = a + E + "[38;5;202m" + "`:oooooooo/`" + E + "[37;1m" + "-hMMMMMMMyyMMMMMMMh-" + E + "[38;5;202m" + "`/oooooooo:`" + R + "\n"
        a = a + E + "[38;5;202m" + "`-/+oo+/:`" + E + "[37;1m" + ".yMMMMMMMh-  -hMMMMMMMy." + E + "[38;5;202m" + "`:/+oo+/-`" + R + "\n"
        a = a + E + "[38;5;202m" + E + "[37;1m" + "        `sMMMMMMMm:      :dMMMMMMMs`" + R + "\n"
        a = a + E + "[37;1m" + "       `hMMMMMMd/          /dMMMMMMh`" + R + "\n"
        a = a + E + "[37;1m" + "         `://:`              `://:`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_12(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "quibian") {
        a = a + E + "[33;1m" + E + "[33;1m" + "            `.--::::::::--.`" + R + "\n"
        a = a + E + "[33;1m" + "        `.-:::-..``   ``..-::-.`" + R + "\n"
        a = a + E + "[33;1m" + "      .::::-`   ." + E + "[37;1m" + "+" + E + "[33;1m" + ":``       `.-::.`" + R + "\n"
        a = a + E + "[33;1m" + "    .::::.`    -::::::-`       `.::." + R + "\n"
        a = a + E + "[33;1m" + "  `-:::-`    -:::::::::--..``     .::`" + R + "\n"
        a = a + E + "[33;1m" + " `::::-     ." + E + "[37;1m" + "oy" + E + "[33;1m" + ":::::::---.```.:    `::`" + R + "\n"
        a = a + E + "[33;1m" + " -::::  `.-:::::::::::-.```         `::" + R + "\n"
        a = a + E + "[33;1m" + ".::::.`-:::::::::::::.               `:." + R + "\n"
        a = a + E + "[33;1m" + "-::::.:::::::::::::::                 -:" + R + "\n"
        a = a + E + "[33;1m" + "::::::::::::::::::::`                 `:" + R + "\n"
        a = a + E + "[33;1m" + ":::::::::::::::::::-                  `:" + R + "\n"
        a = a + E + "[33;1m" + ":::::::::::::::::::                   --" + R + "\n"
        a = a + E + "[33;1m" + ".:::::::::::::::::`                  `:`" + R + "\n"
        a = a + E + "[33;1m" + "`:::::::::::::::::                   -`" + R + "\n"
        a = a + E + "[33;1m" + " .:::::::::::::::-                  -`" + R + "\n"
        a = a + E + "[33;1m" + "  `::::::::::::::-                `.`" + R + "\n"
        a = a + E + "[33;1m" + "    .::::::::::::-               ``" + R + "\n"
        a = a + E + "[33;1m" + "      `.--:::::-." + R + "\n"
        emit a
    }
    if startsWith(dn, "redcore") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                 RRRRRRRRR" + R + "\n"
        a = a + E + "[31;1m" + "               RRRRRRRRRRRRR" + R + "\n"
        a = a + E + "[31;1m" + "        RRRRRRRRRR      RRRRR" + R + "\n"
        a = a + E + "[31;1m" + "   RRRRRRRRRRRRRRRRRRRRRRRRRRR" + R + "\n"
        a = a + E + "[31;1m" + " RRRRRRR  RRR         RRR RRRRRRRR" + R + "\n"
        a = a + E + "[31;1m" + "RRRRR    RR                 RRRRRRRRR" + R + "\n"
        a = a + E + "[31;1m" + "RRRR    RR     RRRRRRRR      RR RRRRRR" + R + "\n"
        a = a + E + "[31;1m" + "RRRR   R    RRRRRRRRRRRRRR   RR   RRRRR" + R + "\n"
        a = a + E + "[31;1m" + "RRRR   R  RRRRRRRRRRRRRRRRRR  R   RRRRR" + R + "\n"
        a = a + E + "[31;1m" + "RRRR     RRRRRRRRRRRRRRRRRRR  R   RRRR" + R + "\n"
        a = a + E + "[31;1m" + " RRR     RRRRRRRRRRRRRRRRRRRR R   RRRR" + R + "\n"
        a = a + E + "[31;1m" + "  RRR    RRRRRRRRRRRRRRRRRRRR    RRRR" + R + "\n"
        a = a + E + "[31;1m" + "    RR   RRRRRRRRRRRRRRRRRRR    RRR" + R + "\n"
        a = a + E + "[31;1m" + "     RR   RRRRRRRRRRRRRRRRR    RRR" + R + "\n"
        a = a + E + "[31;1m" + "       RR   RRRRRRRRRRRRRR   RR" + R + "\n"
        a = a + E + "[31;1m" + "         R       RRRR      RR" + R + "\n"
        emit a
    }
    if startsWith(dn, "redhat") || startsWith(dn, "red hat") || startsWith(dn, "rhel") {
        a = a + E + "[31;1m" + E + "[31;1m" + "           .MMM..:MMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "          MMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "          MMMMMMMMMMMMMMMMMMMM." + R + "\n"
        a = a + E + "[31;1m" + "         MMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "        ,MMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + "        MMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "  .MMMM'  MMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + " MMMMMM    `MMMMMMMMMMMMMMMMMMMM." + R + "\n"
        a = a + E + "[31;1m" + "MMMMMMMM      MMMMMMMMMMMMMMMMMM ." + R + "\n"
        a = a + E + "[31;1m" + "MMMMMMMMM.       `MMMMMMMMMMMMM' MM." + R + "\n"
        a = a + E + "[31;1m" + "MMMMMMMMMMM.                     MMMM" + R + "\n"
        a = a + E + "[31;1m" + "`MMMMMMMMMMMMM.                 ,MMMMM." + R + "\n"
        a = a + E + "[31;1m" + " `MMMMMMMMMMMMMMMMM.          ,MMMMMMMM." + R + "\n"
        a = a + E + "[31;1m" + "    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "      MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + "         MMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[31;1m" + "            `MMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + "                ``MMMMMMMMMMMMMMMMM'" + R + "\n"
        emit a
    }
    if startsWith(dn, "sabayon") {
        a = a + E + "[34;1m" + E + "[34;1m" + "            ..........." + R + "\n"
        a = a + E + "[34;1m" + "         ..             .." + R + "\n"
        a = a + E + "[34;1m" + "      ..                   .." + R + "\n"
        a = a + E + "[34;1m" + "    ..           " + E + "[37;1m" + "o           " + E + "[34;1m" + ".." + R + "\n"
        a = a + E + "[34;1m" + "  ..            " + E + "[37;1m" + ":W'            " + E + "[34;1m" + ".." + R + "\n"
        a = a + E + "[34;1m" + " ..             " + E + "[37;1m" + ".d.             " + E + "[34;1m" + ".." + R + "\n"
        a = a + E + "[34;1m" + ":.             " + E + "[37;1m" + ".KNO              " + E + "[34;1m" + ".:" + R + "\n"
        a = a + E + "[34;1m" + ":.             " + E + "[37;1m" + "cNNN.             " + E + "[34;1m" + ".:" + R + "\n"
        a = a + E + "[34;1m" + ":              " + E + "[37;1m" + "dXXX,              " + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + ":   " + E + "[37;1m" + ".          dXXX,       .cd,   " + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + ":   " + E + "[37;1m" + "'kc ..     dKKK.    ,ll;:'    " + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + ":     " + E + "[37;1m" + ".xkkxc;..dkkkc',cxkkl       " + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + ":.     " + E + "[37;1m" + ".,cdddddddddddddo:.       " + E + "[34;1m" + ".:" + R + "\n"
        a = a + E + "[34;1m" + " ..         " + E + "[37;1m" + ":lllllll:           " + E + "[34;1m" + ".." + R + "\n"
        a = a + E + "[34;1m" + "   ..         " + E + "[37;1m" + "',,,,,          " + E + "[34;1m" + ".." + R + "\n"
        a = a + E + "[34;1m" + "     ..                     .." + R + "\n"
        a = a + E + "[34;1m" + "        ..               .." + R + "\n"
        a = a + E + "[34;1m" + "          ..............." + R + "\n"
        emit a
    }
    if startsWith(dn, "smartos") {
        a = a + E + "[36;1m" + E + "[36;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys             oyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys  yyyyyyyyy  oyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys  yyyyyyyyy  oyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys  yyyyyyyyy  oyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys  yyyyyyyyy  oyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyys  yyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyy                         syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyy  syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyy  syyyyyyyyy  syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyy  oyyyyyyyyy  syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyy  oyyyyyyyyy  syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyy  syyyyyyyyy  syyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyy              yyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[36;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        emit a
    }
    if startsWith(dn, "skiffos") {
        a = a + E + "[34;1m" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "             ,@@@@@@@@@@@w,_" + R + "\n"
        a = a + E + "[37;1m" + "  " + E + "[37;1m" + "====~~~,,." + E + "[37;1m" + "A@@@@@@@@@@@@@@@@@W,_" + R + "\n"
        a = a + E + "[37;1m" + "  " + E + "[34;1m" + "`||||||||||||||L{" + E + "[37;1m" + "\"@$@@@@@@@@B\"" + R + "\n"
        a = a + E + "[37;1m" + "   " + E + "[34;1m" + "`|||||||||||||||||||||L{" + E + "[37;1m" + "\"$D" + R + "\n"
        a = a + E + "[37;1m" + "     " + E + "[37;1m" + "@@@@@@@@@@@@@@@@@@@@@" + E + "[34;1m" + "_||||}==," + R + "\n"
        a = a + E + "[34;1m" + "      " + E + "[37;1m" + "*@@@@@@@@@@@@@@@@@@@@@@@@@p" + E + "[34;1m" + "||||==," + R + "\n"
        a = a + E + "[34;1m" + "        " + E + "[34;1m" + "`'||LLL{{\"\"" + E + "[37;1m" + "@$B@@@@@@@@@@@@@@@p" + E + "[34;1m" + "||" + R + "\n"
        a = a + E + "[34;1m" + "            " + E + "[34;1m" + "`~=|||||||||||L\"" + E + "[37;1m" + "$@@@@@@@@@@@" + R + "\n"
        a = a + E + "[37;1m" + "                   " + E + "[34;1m" + "````'\"\"\"\"\"\"\"" + E + "[37;1m" + "'\"\"\"\"\"\"\"\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "steamos") {
        a = a + E + "[35;1m" + E + "[35;1m" + "              .,,,,." + R + "\n"
        a = a + E + "[35;1m" + "        .,'onNMMMMMNNnn',." + R + "\n"
        a = a + E + "[35;1m" + "     .'oNMANKMMMMMMMMMMMNNn'." + R + "\n"
        a = a + E + "[35;1m" + "   .'ANMMMMMMMXKNNWWWPFFWNNMNn." + R + "\n"
        a = a + E + "[35;1m" + "  ;NNMMMMMMMMMMNWW'' ,.., 'WMMM," + R + "\n"
        a = a + E + "[35;1m" + " ;NMMMMV+##+VNWWW' .+;'':+, 'WMW," + R + "\n"
        a = a + E + "[35;1m" + ",VNNWP+" + E + "[37;1m" + "######" + E + "[35;1m" + "+WW,  " + E + "[37;1m" + "+:    " + E + "[35;1m" + ":+, +MMM," + R + "\n"
        a = a + E + "[35;1m" + "'" + E + "[37;1m" + "+#############,   +.    ,+' " + E + "[35;1m" + "+NMMM" + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "  '*#########*'     '*,,*' " + E + "[35;1m" + ".+NMMMM." + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "     `'*###*'          ,.,;###" + E + "[35;1m" + "+WNM," + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "         .,;;,      .;##########" + E + "[35;1m" + "+W" + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + ",',.         ';  ,+##############'" + R + "\n"
        a = a + E + "[37;1m" + " '###+. :,. .,; ,###############'" + R + "\n"
        a = a + E + "[37;1m" + "  '####.. `'' .,###############'" + R + "\n"
        a = a + E + "[37;1m" + "    '#####+++################'" + R + "\n"
        a = a + E + "[37;1m" + "      '*##################*'" + R + "\n"
        a = a + E + "[37;1m" + "         ''*##########*''" + R + "\n"
        a = a + E + "[37;1m" + "              ''''''" + R + "\n"
        emit a
    }
    if startsWith(dn, "sunos") || startsWith(dn, "solaris") {
        a = a + E + "[33;1m" + E + "[33;1m" + "                 `-     `" + R + "\n"
        a = a + E + "[33;1m" + "          `--    `+-    .:" + R + "\n"
        a = a + E + "[33;1m" + "           .+:  `++:  -/+-     ." + R + "\n"
        a = a + E + "[33;1m" + "    `.::`  -++/``:::`./+/  `.-/." + R + "\n"
        a = a + E + "[33;1m" + "      `++/-`.`          ` /++:`" + R + "\n"
        a = a + E + "[33;1m" + "  ``   ./:`                .: `..`.-" + R + "\n"
        a = a + E + "[33;1m" + "``./+/:-                     -+++:-" + R + "\n"
        a = a + E + "[33;1m" + "    -/+`                      :." + R + "\n"
        emit a
    }
    if startsWith(dn, "ubuntu") || startsWith(dn, "i3buntu") {
        a = a + E + "[31;1m" + E + "[31;1m" + "            .-/+oossssoo+\\-." + R + "\n"
        a = a + E + "[31;1m" + "        ´:+ssssssssssssssssss+:`" + R + "\n"
        a = a + E + "[31;1m" + "      -+ssssssssssssssssssyyssss+-" + R + "\n"
        a = a + E + "[31;1m" + "    .ossssssssssssssssss" + E + "[37;1m" + "dMMMNy" + E + "[31;1m" + "sssso." + R + "\n"
        a = a + E + "[31;1m" + "   /sssssssssss" + E + "[37;1m" + "hdmmNNmmyNMMMMh" + E + "[31;1m" + "ssssss\\" + R + "\n"
        a = a + E + "[31;1m" + "  +sssssssss" + E + "[37;1m" + "hm" + E + "[31;1m" + "yd" + E + "[37;1m" + "MMMMMMMNddddy" + E + "[31;1m" + "ssssssss+" + R + "\n"
        a = a + E + "[31;1m" + " /ssssssss" + E + "[37;1m" + "hNMMM" + E + "[31;1m" + "yh" + E + "[37;1m" + "hyyyyhmNMMMNh" + E + "[31;1m" + "ssssssss\\" + R + "\n"
        a = a + E + "[31;1m" + ".ssssssss" + E + "[37;1m" + "dMMMNh" + E + "[31;1m" + "ssssssssss" + E + "[37;1m" + "hNMMMd" + E + "[31;1m" + "ssssssss." + R + "\n"
        a = a + E + "[31;1m" + "+ssss" + E + "[37;1m" + "hhhyNMMNy" + E + "[31;1m" + "ssssssssssss" + E + "[37;1m" + "yNMMMy" + E + "[31;1m" + "sssssss+" + R + "\n"
        a = a + E + "[31;1m" + "oss" + E + "[37;1m" + "yNMMMNyMMh" + E + "[31;1m" + "ssssssssssssss" + E + "[37;1m" + "hmmmh" + E + "[31;1m" + "ssssssso" + R + "\n"
        a = a + E + "[31;1m" + "oss" + E + "[37;1m" + "yNMMMNyMMh" + E + "[31;1m" + "sssssssssssssshmmmh" + E + "[31;1m" + "ssssssso" + R + "\n"
        a = a + E + "[31;1m" + "+ssss" + E + "[37;1m" + "hhhyNMMNy" + E + "[31;1m" + "ssssssssssss" + E + "[37;1m" + "yNMMMy" + E + "[31;1m" + "sssssss+" + R + "\n"
        a = a + E + "[31;1m" + ".ssssssss" + E + "[37;1m" + "dMMMNh" + E + "[31;1m" + "ssssssssss" + E + "[37;1m" + "hNMMMd" + E + "[31;1m" + "ssssssss." + R + "\n"
        a = a + E + "[31;1m" + " \\ssssssss" + E + "[37;1m" + "hNMMM" + E + "[31;1m" + "yh" + E + "[37;1m" + "hyyyyhdNMMMNh" + E + "[31;1m" + "ssssssss/" + R + "\n"
        a = a + E + "[31;1m" + "  +sssssssss" + E + "[37;1m" + "dm" + E + "[31;1m" + "yd" + E + "[37;1m" + "MMMMMMMMddddy" + E + "[31;1m" + "ssssssss+" + R + "\n"
        a = a + E + "[31;1m" + "   \\sssssssssss" + E + "[37;1m" + "hdmNNNNmyNMMMMh" + E + "[31;1m" + "ssssss/" + R + "\n"
        a = a + E + "[31;1m" + "    .ossssssssssssssssss" + E + "[37;1m" + "dMMMNy" + E + "[31;1m" + "sssso." + R + "\n"
        a = a + E + "[31;1m" + "      -+sssssssssssssssss" + E + "[37;1m" + "yyy" + E + "[31;1m" + "ssss+-" + R + "\n"
        a = a + E + "[31;1m" + "        `:+ssssssssssssssssss+:`" + R + "\n"
        a = a + E + "[31;1m" + "            .-\\+oossssoo+/-." + R + "\n"
        emit a
    }
    if startsWith(dn, "windows") {
        a = a + E + "[31;1m" + E + "[31;1m" + "        ,.=:!!t3Z3z.," + R + "\n"
        a = a + E + "[31;1m" + "       :tt:::tt333EE3" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "       Et:::ztt33EEEL" + E + "[32;1m" + " @Ee.,      ..," + R + "\n"
        a = a + E + "[32;1m" + E + "[31;1m" + "      ;tt:::tt333EE7" + E + "[32;1m" + " ;EEEEEEttttt33#" + R + "\n"
        a = a + E + "[32;1m" + E + "[31;1m" + "     :Et:::zt333EEQ." + E + "[32;1m" + " $EEEEEttttt33QL" + R + "\n"
        a = a + E + "[32;1m" + E + "[31;1m" + "     it::::tt333EEF" + E + "[32;1m" + " @EEEEEEttttt33F" + R + "\n"
        a = a + E + "[32;1m" + E + "[31;1m" + "    ;3=*^```\"*4EEV" + E + "[32;1m" + " :EEEEEEttttt33@." + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "    ,.=::::!t=., " + E + "[31;1m" + "`" + E + "[32;1m" + " @EEEEEEtttz33QF" + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "   ;::::::::zt33)" + E + "[32;1m" + "   \"4EEEtttji3P*" + R + "\n"
        a = a + E + "[32;1m" + E + "[34;1m" + "  :t::::::::tt33." + E + "[33;1m" + ":Z3z.." + E + "[32;1m" + "  ``" + E + "[33;1m" + " ,..g." + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "  i::::::::zt33F" + E + "[33;1m" + " AEEEtttt::::ztF" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + " ;:::::::::t33V" + E + "[33;1m" + " ;EEEttttt::::t3" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + " E::::::::zt33L" + E + "[33;1m" + " @EEEtttt::::z3F" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "{3=*^```\"*4E3)" + E + "[33;1m" + " ;EEEtttt:::::tZ`" + R + "\n"
        a = a + E + "[33;1m" + E + "[34;1m" + "             `" + E + "[33;1m" + " :EEEEtttt::::z7" + R + "\n"
        a = a + E + "[33;1m" + "                 \"VEzjt:;;z>*`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_13(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "xubuntu") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           `.:/ossyyyysso/:." + R + "\n"
        a = a + E + "[34;1m" + "        `.yyyyyyyyyyyyyyyyyyyy.`" + R + "\n"
        a = a + E + "[34;1m" + "      `yyyyyyyyyyyyyyyyyyyyyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + "    `yyyyyyyyyyyyyyyyyyyy" + E + "[37;1m" + "::" + E + "[34;1m" + "yyyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + "   .yyyyyyyyyyy" + E + "[37;1m" + "/+:" + E + "[34;1m" + "yyyyyyy" + E + "[37;1m" + "ds" + E + "[34;1m" + "yyy" + E + "[37;1m" + "+y" + E + "[34;1m" + "yyyy." + R + "\n"
        a = a + E + "[34;1m" + "  yyyyyyy" + E + "[37;1m" + ":o/" + E + "[34;1m" + "yy" + E + "[37;1m" + "dMMM+" + E + "[34;1m" + "yyyyy" + E + "[37;1m" + "/M+" + E + "[34;1m" + "y" + E + "[37;1m" + ":hM+" + E + "[34;1m" + "yyyyyy" + R + "\n"
        a = a + E + "[34;1m" + " yyyyyyy" + E + "[37;1m" + "+MMMy" + E + "[34;1m" + "y" + E + "[37;1m" + "mMMMh" + E + "[34;1m" + "yyyyy" + E + "[37;1m" + "yM::mM+" + E + "[34;1m" + "yyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "`yyyyyyy" + E + "[37;1m" + "+MMMMysMMMd" + E + "[34;1m" + "yyyyy" + E + "[37;1m" + "dh:mN+" + E + "[34;1m" + "yyyyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + ":NMMMMmMMMMmmdhyy+/y:" + E + "[34;1m" + "yyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + "+MMMMMMMMMMMMMMMMMMNho:" + E + "[34;1m" + "yyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + "mMMMMMMMMMMMMMMMMMMMMMMy" + E + "[34;1m" + "yyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyy" + E + "[37;1m" + "+MMMMMMMMMMMMMMMMMMMMMMMM/" + E + "[34;1m" + "yyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "`yyyyyy" + E + "[37;1m" + "sMMMMMMMMMMMMMMMMMMMMMMmo" + E + "[34;1m" + "yyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + " yyyyyy" + E + "[37;1m" + "oMMMMMMMMMMMMMMMMMMMmy+" + E + "[34;1m" + "yyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "  yyyyy" + E + "[37;1m" + ":mMMMMMMMMMMMMMMNho/" + E + "[34;1m" + "yyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "   .yyyy" + E + "[37;1m" + ":yNMMMMMMMNdyo:" + E + "[34;1m" + "yyyyyyyyyyyyy." + R + "\n"
        a = a + E + "[34;1m" + "    `yyyyyy" + E + "[37;1m" + ":/++/::" + E + "[34;1m" + "yyyyyyyyyyyyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + "      `yyyyyyyyyyyyyyyyyyyyyyyyyy`" + R + "\n"
        a = a + E + "[34;1m" + "        `.yyyyyyyyyyyyyyyyyyyy.`" + R + "\n"
        a = a + E + "[34;1m" + "           `.:/oosyyyysso/:.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "chimera") {
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
    if startsWith(dn, "alpine") {
        a = a + E + "[34;1m" + E + "[34;1m" + "       .hddddddddddddddddddddddh." + R + "\n"
        a = a + E + "[34;1m" + "      :dddddddddddddddddddddddddd:" + R + "\n"
        a = a + E + "[34;1m" + "     /dddddddddddddddddddddddddddd/" + R + "\n"
        a = a + E + "[34;1m" + "    +dddddddddddddddddddddddddddddd+" + R + "\n"
        a = a + E + "[34;1m" + "  `sdddddddddddddddddddddddddddddddds`" + R + "\n"
        a = a + E + "[34;1m" + " `ydddddddddddd++hdddddddddddddddddddy`" + R + "\n"
        a = a + E + "[34;1m" + ".hddddddddddd+`  `+ddddh:-sdddddddddddh." + R + "\n"
        a = a + E + "[34;1m" + "hdddddddddd+`      `+y:    .sddddddddddh" + R + "\n"
        a = a + E + "[34;1m" + "ddddddddh+`   `//`   `.`     -sddddddddd" + R + "\n"
        a = a + E + "[34;1m" + "ddddddh+`   `/hddh/`   `:s-    -sddddddd" + R + "\n"
        a = a + E + "[34;1m" + "ddddh+`   `/+/dddddh/`   `+s-    -sddddd" + R + "\n"
        a = a + E + "[34;1m" + "ddd+`   `/o` :dddddddh/`   `oy-    .yddd" + R + "\n"
        a = a + E + "[34;1m" + "hdddyo+ohddyosdddddddddho+oydddy++ohdddh" + R + "\n"
        a = a + E + "[34;1m" + ".hddddddddddddddddddddddddddddddddddddh." + R + "\n"
        a = a + E + "[34;1m" + " `yddddddddddddddddddddddddddddddddddy`" + R + "\n"
        a = a + E + "[34;1m" + "  `sdddddddddddddddddddddddddddddddds`" + R + "\n"
        a = a + E + "[34;1m" + "    +dddddddddddddddddddddddddddddd+" + R + "\n"
        a = a + E + "[34;1m" + "     /dddddddddddddddddddddddddddd/" + R + "\n"
        a = a + E + "[34;1m" + "      :dddddddddddddddddddddddddd:" + R + "\n"
        a = a + E + "[34;1m" + "       .hddddddddddddddddddddddh." + R + "\n"
        emit a
    }
    if startsWith(dn, "amazon") {
        a = a + E + "[33;1m" + E + "[33;1m" + "             `-/oydNNdyo:.`" + R + "\n"
        a = a + E + "[33;1m" + "      `.:+shmMMMMMMMMMMMMMMmhs+:.`" + R + "\n"
        a = a + E + "[33;1m" + "    -+hNNMMMMMMMMMMMMMMMMMMMMMMNNho-" + R + "\n"
        a = a + E + "[33;1m" + ".``      -/+shmNNMMMMMMNNmhs+/-      ``." + R + "\n"
        a = a + E + "[33;1m" + "dNmhs+:.       `.:/oo/:.`       .:+shmNd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMNdhs+:..        ..:+shdNMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMNds    odNMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + "dMMMMMMMMMMMMMMMMh    yMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[33;1m" + ".:+ydNMMMMMMMMMMMh    yMMMMMMMMMMMNdy+:." + R + "\n"
        a = a + E + "[33;1m" + "     `.:+shNMMMMMh    yMMMMMNhs+:``" + R + "\n"
        a = a + E + "[33;1m" + "            `-+shy    shs+:`" + R + "\n"
        emit a
    }
    if startsWith(dn, "bitrig") {
        a = a + E + "[32;1m" + E + "[32;1m" + "   `hMMMMN+" + R + "\n"
        a = a + E + "[32;1m" + "   -MMo-dMd`" + R + "\n"
        a = a + E + "[32;1m" + "   oMN- oMN`" + R + "\n"
        a = a + E + "[32;1m" + "   yMd  /NM:" + R + "\n"
        a = a + E + "[32;1m" + "  .mMmyyhMMs" + R + "\n"
        a = a + E + "[32;1m" + "  :NMMMhsmMh" + R + "\n"
        a = a + E + "[32;1m" + "  +MNhNNoyMm-" + R + "\n"
        a = a + E + "[32;1m" + "  hMd.-hMNMN:" + R + "\n"
        a = a + E + "[32;1m" + "  mMmsssmMMMo" + R + "\n"
        a = a + E + "[32;1m" + " .MMdyyhNMMMd" + R + "\n"
        a = a + E + "[32;1m" + " oMN.`/dMddMN`" + R + "\n"
        a = a + E + "[32;1m" + " yMm/hNm+./MM/" + R + "\n"
        a = a + E + "[32;1m" + ".dMMMmo.``.NMo" + R + "\n"
        a = a + E + "[32;1m" + ":NMMMNmmmmmMMh" + R + "\n"
        a = a + E + "[32;1m" + "/MN/-------oNN:" + R + "\n"
        a = a + E + "[32;1m" + "hMd.       .dMh" + R + "\n"
        a = a + E + "[32;1m" + "sm/         /ms" + R + "\n"
        emit a
    }
    if startsWith(dn, "bonsai") {
        a = a + E + "[36;1m" + E + "[32;1m" + "   ,####," + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[32;1m" + "#######,  " + E + "[32;1m" + ",#####," + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[32;1m" + "#####',#  " + E + "[32;1m" + "'######" + R + "\n"
        a = a + E + "[32;1m" + "    " + E + "[32;1m" + "''###'" + E + "[33;1m" + "';,,,'" + E + "[32;1m" + "###'" + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[33;1m" + "       ,;  ''''" + R + "\n"
        a = a + E + "[33;1m" + "   " + E + "[33;1m" + "      ;;;   " + E + "[32;1m" + ",#####," + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[33;1m" + "     ;;;'  ,,;" + E + "[32;1m" + ";;###" + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[33;1m" + "     ';;;;''" + E + "[32;1m" + "'####'" + R + "\n"
        a = a + E + "[32;1m" + "   " + E + "[33;1m" + "      ;;;" + R + "\n"
        a = a + E + "[33;1m" + "   " + E + "[33;1m" + "   ,.;;';'',,," + R + "\n"
        a = a + E + "[33;1m" + "   " + E + "[33;1m" + "  '     '" + R + "\n"
        a = a + E + "[33;1m" + E + "[36;1m" + " #" + R + "\n"
        a = a + E + "[36;1m" + " #                        O" + R + "\n"
        a = a + E + "[36;1m" + " ##, ,##,',##, ,##  ,#,   ," + R + "\n"
        a = a + E + "[36;1m" + " # # #  # #''# #,,  # #   #" + R + "\n"
        a = a + E + "[36;1m" + " '#' '##' #  #  ,,# '##;, #" + R + "\n"
        emit a
    }
    if startsWith(dn, "centos") {
        a = a + E + "[33;1m" + E + "[33;1m" + "                 .." + R + "\n"
        a = a + E + "[33;1m" + "               .PLTJ." + R + "\n"
        a = a + E + "[33;1m" + "              <><><><>" + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[32;1m" + "KKSSV' 4KKK " + E + "[33;1m" + "LJ" + E + "[35;1m" + " KKKL.'VSSKK" + R + "\n"
        a = a + E + "[35;1m" + "     " + E + "[32;1m" + "KKV' 4KKKKK " + E + "[33;1m" + "LJ" + E + "[35;1m" + " KKKKAL 'VKK" + R + "\n"
        a = a + E + "[35;1m" + "     " + E + "[32;1m" + "V' ' 'VKKKK " + E + "[33;1m" + "LJ" + E + "[35;1m" + " KKKKV' ' 'V" + R + "\n"
        a = a + E + "[35;1m" + "     " + E + "[32;1m" + ".4MA.' 'VKK " + E + "[33;1m" + "LJ" + E + "[35;1m" + " KKV' '.4Mb." + R + "\n"
        a = a + E + "[35;1m" + E + "[35;1m" + "   . " + E + "[32;1m" + "KKKKKA.' 'V " + E + "[33;1m" + "LJ" + E + "[35;1m" + " V' '.4KKKKK " + E + "[34;1m" + "." + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + " .4D " + E + "[32;1m" + "KKKKKKKA.'' " + E + "[33;1m" + "LJ" + E + "[35;1m" + " ''.4KKKKKKK " + E + "[34;1m" + "FA." + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "<QDD ++++++++++++  " + E + "[34;1m" + "++++++++++++ GFD>" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + " 'VD " + E + "[34;1m" + "KKKKKKKK'.. " + E + "[32;1m" + "LJ " + E + "[33;1m" + "..'KKKKKKKK " + E + "[34;1m" + "FV" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "   ' " + E + "[34;1m" + "VKKKKK'. .4 " + E + "[32;1m" + "LJ " + E + "[33;1m" + "K. .'KKKKKV " + E + "[34;1m" + "'" + R + "\n"
        a = a + E + "[34;1m" + "     " + E + "[34;1m" + " 'VK'. .4KK " + E + "[32;1m" + "LJ " + E + "[33;1m" + "KKA. .'KV'" + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[34;1m" + "A. . .4KKKK " + E + "[32;1m" + "LJ " + E + "[33;1m" + "KKKKA. . .4" + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[34;1m" + "KKA. 'KKKKK " + E + "[32;1m" + "LJ " + E + "[33;1m" + "KKKKK' .4KK" + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[34;1m" + "KKSSA. VKKK " + E + "[32;1m" + "LJ " + E + "[33;1m" + "KKKV .4SSKK" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "              <><><><>" + R + "\n"
        a = a + E + "[32;1m" + "               'MKKM'" + R + "\n"
        a = a + E + "[32;1m" + "                 ''" + R + "\n"
        emit a
    }
    if startsWith(dn, "chakra") {
        a = a + E + "[34;1m" + E + "[34;1m" + "     _ _ _        \"kkkkkkkk." + R + "\n"
        a = a + E + "[34;1m" + "   ,kkkkkkkk.,    'kkkkkkkkk," + R + "\n"
        a = a + E + "[34;1m" + "   ,kkkkkkkkkkkk., 'kkkkkkkkk." + R + "\n"
        a = a + E + "[34;1m" + "  ,kkkkkkkkkkkkkkkk,'kkkkkkkk," + R + "\n"
        a = a + E + "[34;1m" + " ,kkkkkkkkkkkkkkkkkkk'kkkkkkk." + R + "\n"
        a = a + E + "[34;1m" + "  \"''\"''',;::,,\"''kkk''kkkkk;   __" + R + "\n"
        a = a + E + "[34;1m" + "      ,kkkkkkkkkk, \"k''kkkkk' ,kkkk" + R + "\n"
        a = a + E + "[34;1m" + "    ,kkkkkkk' ., ' .: 'kkkk',kkkkkk" + R + "\n"
        a = a + E + "[34;1m" + "  ,kkkkkkkk'.k'   ,  ,kkkk;kkkkkkkkk" + R + "\n"
        a = a + E + "[34;1m" + " ,kkkkkkkk';kk 'k  \"'k',kkkkkkkkkkkk" + R + "\n"
        a = a + E + "[34;1m" + ".kkkkkkkkk.kkkk.'kkkkkkkkkkkkkkkkkk'" + R + "\n"
        a = a + E + "[34;1m" + ";kkkkkkkk''kkkkkk;'kkkkkkkkkkkkk''" + R + "\n"
        a = a + E + "[34;1m" + "'kkkkkkk; 'kkkkkkkk.,\"\"''\"''\"\"" + R + "\n"
        a = a + E + "[34;1m" + "  ''kkkk;  'kkkkkkkkkk.," + R + "\n"
        a = a + E + "[34;1m" + "     ';'    'kkkkkkkkkkkk.," + R + "\n"
        a = a + E + "[34;1m" + "             ';kkkkkkkkkk'" + R + "\n"
        a = a + E + "[34;1m" + "               ';kkkkkk'" + R + "\n"
        a = a + E + "[34;1m" + "                  \"''\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "clover") {
        a = a + E + "[32;1m" + E + "[32;1m" + "               `omo``omo`" + R + "\n"
        a = a + E + "[32;1m" + "             `oNMMMNNMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + "           `oNMMMMMMMMMMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + "          oNMMMMMMMMMMMMMMMMNo" + R + "\n"
        a = a + E + "[32;1m" + "          `sNMMMMMMMMMMMMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "     `omo`  `sNMMMMMMMMMMNs`  `omo`" + R + "\n"
        a = a + E + "[32;1m" + "   `oNMMMNo`  `sNMMMMMMNs`  `oNMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + " `oNMMMMMMMNo`  `oNMMNs`  `oNMMMMMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + "oNMMMMMMMMMMMNo`  `sy`  `oNMMMMMMMMMMMNo" + R + "\n"
        a = a + E + "[32;1m" + "`sNMMMMMMMMMMMMNo." + E + "[36;1m" + "oNNs" + E + "[32;1m" + ".oNMMMMMMMMMMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "`oNMMMMMMMMMMMMNs." + E + "[36;1m" + "oNNs" + E + "[32;1m" + ".oNMMMMMMMMMMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + "oNMMMMMMMMMMMNs`  `sy`  `oNMMMMMMMMMMMNo" + R + "\n"
        a = a + E + "[32;1m" + " `oNMMMMMMMNs`  `oNMMNo`  `oNMMMMMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "   `oNMMMNs`  `sNMMMMMMNs`  `oNMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "     `oNs`  `sNMMMMMMMMMMNs`  `oNs`" + R + "\n"
        a = a + E + "[32;1m" + "          `sNMMMMMMMMMMMMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "          +NMMMMMMMMMMMMMMMMNo" + R + "\n"
        a = a + E + "[32;1m" + "           `oNMMMMMMMMMMMMNo`" + R + "\n"
        a = a + E + "[32;1m" + "             `oNMMMNNMMMNs`" + R + "\n"
        a = a + E + "[32;1m" + "               `omo``oNs`" + R + "\n"
        emit a
    }
    if startsWith(dn, "dahlia") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "                  .#." + R + "\n"
        a = a + E + "[31;1m" + "                *%@@@%*" + R + "\n"
        a = a + E + "[31;1m" + "        .,,,,,(&@@@@@@@&/,,,,,." + R + "\n"
        a = a + E + "[31;1m" + "       ,#@@@@@@@@@@@@@@@@@@@@@#." + R + "\n"
        a = a + E + "[31;1m" + "       ,#@@@@@@@&#///#&@@@@@@@#." + R + "\n"
        a = a + E + "[31;1m" + "     ,/%&@@@@@%/,    .,(%@@@@@&#/." + R + "\n"
        a = a + E + "[31;1m" + "   *#&@@@@@@#,.         .*#@@@@@@&#," + R + "\n"
        a = a + E + "[31;1m" + " .&@@@@@@@@@(            .(@@@@@@@@@&&." + R + "\n"
        a = a + E + "[31;1m" + "#@@@@@@@@@@(               )@@@@@@@@@@@#" + R + "\n"
        a = a + E + "[31;1m" + " °@@@@@@@@@@(            .(@@@@@@@@@@@°" + R + "\n"
        a = a + E + "[31;1m" + "   *%@@@@@@@(.           ,#@@@@@@@%*" + R + "\n"
        a = a + E + "[31;1m" + "     ,(&@@@@@@%*.     ./%@@@@@@%(," + R + "\n"
        a = a + E + "[31;1m" + "       ,#@@@@@@@&(***(&@@@@@@@#." + R + "\n"
        a = a + E + "[31;1m" + "       ,#@@@@@@@@@@@@@@@@@@@@@#." + R + "\n"
        a = a + E + "[31;1m" + "        ,*****#&@@@@@@@&(*****," + R + "\n"
        a = a + E + "[31;1m" + "               ,/%@@@%/." + R + "\n"
        a = a + E + "[31;1m" + "                  ,#," + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_14(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "debian") {
        a = a + E + "[31;1m" + E + "[37;1m" + "       _,met$$$$$gg." + R + "\n"
        a = a + E + "[37;1m" + "    ,g$$$$$$$$$$$$$$$P." + R + "\n"
        a = a + E + "[37;1m" + "  ,g$$P\"        \"\"\"Y$$.\"." + R + "\n"
        a = a + E + "[37;1m" + " ,$$P'              `$$$." + R + "\n"
        a = a + E + "[37;1m" + "',$$P       ,ggs.     `$$b:" + R + "\n"
        a = a + E + "[37;1m" + "`d$$'     ,$P\"'   " + E + "[31;1m" + "." + E + "[37;1m" + "    $$$" + R + "\n"
        a = a + E + "[37;1m" + " $$P      d$'     " + E + "[31;1m" + "," + E + "[37;1m" + "    $$P" + R + "\n"
        a = a + E + "[37;1m" + " $$:      $$.   " + E + "[31;1m" + "-" + E + "[37;1m" + "    ,d$$'" + R + "\n"
        a = a + E + "[37;1m" + " $$;      Y$b._   _,d$P'" + R + "\n"
        a = a + E + "[37;1m" + " Y$$.    " + E + "[31;1m" + "`." + E + "[37;1m" + "`\"Y$$$$P\"'" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + " `$$b      " + E + "[31;1m" + "\"-.__" + R + "\n"
        a = a + E + "[31;1m" + E + "[37;1m" + "  `Y$$" + R + "\n"
        a = a + E + "[37;1m" + "   `Y$$." + R + "\n"
        a = a + E + "[37;1m" + "     `$$b." + R + "\n"
        a = a + E + "[37;1m" + "       `Y$$b." + R + "\n"
        a = a + E + "[37;1m" + "          `\"Y$b._" + R + "\n"
        a = a + E + "[37;1m" + "              `\"\"\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "deepin") {
        a = a + E + "[32;1m" + E + "[32;1m" + "             ............" + R + "\n"
        a = a + E + "[32;1m" + "         .';;;;;.       .,;,." + R + "\n"
        a = a + E + "[32;1m" + "      .,;;;;;;;.       ';;;;;;;." + R + "\n"
        a = a + E + "[32;1m" + "    .;::::::::'     .,::;;,''''',." + R + "\n"
        a = a + E + "[32;1m" + "   ,'.::::::::    .;;'.          ';" + R + "\n"
        a = a + E + "[32;1m" + "  ;'  'cccccc,   ,' :: '..        .:" + R + "\n"
        a = a + E + "[32;1m" + " ,,    :ccccc.  ;: .c, '' :.       ,;" + R + "\n"
        a = a + E + "[32;1m" + ".l.     cllll' ., .lc  :; .l'       l." + R + "\n"
        a = a + E + "[32;1m" + ".c       :lllc  ;cl:  .l' .ll.      :'" + R + "\n"
        a = a + E + "[32;1m" + ".l        'looc. .   ,o:  'oo'      c," + R + "\n"
        a = a + E + "[32;1m" + ".o.         .:ool::coc'  .ooo'      o." + R + "\n"
        a = a + E + "[32;1m" + " ::            .....   .;dddo      ;c" + R + "\n"
        a = a + E + "[32;1m" + "  l:...            .';lddddo.     ,o" + R + "\n"
        a = a + E + "[32;1m" + "   lxxxxxdoolllodxxxxxxxxxc      :l" + R + "\n"
        a = a + E + "[32;1m" + "    ,dxxxxxxxxxxxxxxxxxxl.     'o," + R + "\n"
        a = a + E + "[32;1m" + "      ,dkkkkkkkkkkkkko;.    .;o;" + R + "\n"
        a = a + E + "[32;1m" + "        .;okkkkkdl;.    .,cl:." + R + "\n"
        a = a + E + "[32;1m" + "            .,:cccccccc:,." + R + "\n"
        emit a
    }
    if startsWith(dn, "desaos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "███████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "███████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "███████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "███████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "████████               ███████" + R + "\n"
        a = a + E + "[32;1m" + "██████████████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "██████████████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "████████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "████████████████████████" + R + "\n"
        a = a + E + "[32;1m" + "████████████████████████" + R + "\n"
        emit a
    }
    if startsWith(dn, "devuan") {
        a = a + E + "[35;1m" + E + "[35;1m" + "   ..,,;;;::;,.." + R + "\n"
        a = a + E + "[35;1m" + "           `':ddd;:,." + R + "\n"
        a = a + E + "[35;1m" + "                 `'dPPd:,." + R + "\n"
        a = a + E + "[35;1m" + "                     `:b$$b`." + R + "\n"
        a = a + E + "[35;1m" + "                        'P$$$d`" + R + "\n"
        a = a + E + "[35;1m" + "                         .$$$$$`" + R + "\n"
        a = a + E + "[35;1m" + "                         ;$$$$$P" + R + "\n"
        a = a + E + "[35;1m" + "                      .:P$$$$$$`" + R + "\n"
        a = a + E + "[35;1m" + "                  .,:b$$$$$$$;'" + R + "\n"
        a = a + E + "[35;1m" + "             .,:dP$$$$$$$$b:'" + R + "\n"
        a = a + E + "[35;1m" + "      .,:;db$$$$$$$$$$Pd'`" + R + "\n"
        a = a + E + "[35;1m" + " ,db$$$$$$$$$$$$$$b:'`" + R + "\n"
        a = a + E + "[35;1m" + ":$$$$$$$$$$$$b:'`" + R + "\n"
        a = a + E + "[35;1m" + " `$$$$$bd:''`" + R + "\n"
        a = a + E + "[35;1m" + "   `'''`" + R + "\n"
        emit a
    }
    if startsWith(dn, "dracos") {
        a = a + E + "[31;1m" + E + "[31;1m" + "       `-:/-" + R + "\n"
        a = a + E + "[31;1m" + "          -os:" + R + "\n"
        a = a + E + "[31;1m" + "            -os/`" + R + "\n"
        a = a + E + "[31;1m" + "              :sy+-`" + R + "\n"
        a = a + E + "[31;1m" + "               `/yyyy+." + R + "\n"
        a = a + E + "[31;1m" + "                 `+yyyyo-" + R + "\n"
        a = a + E + "[31;1m" + "                   `/yyyys:" + R + "\n"
        a = a + E + "[31;1m" + "`:osssoooo++-        +yyyyyy/`" + R + "\n"
        a = a + E + "[31;1m" + "   ./yyyyyyo         yo`:syyyy+." + R + "\n"
        a = a + E + "[31;1m" + "      -oyyy+         +-   :yyyyyo-" + R + "\n"
        a = a + E + "[31;1m" + "        `:sy:        `.    `/yyyyys:" + R + "\n"
        a = a + E + "[31;1m" + "           ./o/.`           .oyyso+oo:`" + R + "\n"
        a = a + E + "[31;1m" + "              :+oo+//::::///:-.`     `.`" + R + "\n"
        emit a
    }
    if startsWith(dn, "darkos") {
        a = a + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + E + "[35;1m" + "⠀⠀⠀⠀  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⠢⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[35;1m" + E + "[31;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣶⠋⡆⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡆⢀⣤⢛⠛⣠⣿⠀⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣶⣿⠟⣡⠊⣠⣾⣿⠃⣠⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[36;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣯⣿⠀⠊⣤⣿⣿⣿⠃⣴⣧⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[36;1m" + E + "[31;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣶⣿⣿⡟⣠⣶⣿⣿⣿⢋⣤⠿⠛⠉⢁⣭⣽⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "  ⠀⠀⠀⠀⠀⠀ ⠀⣠⠖⡭⢉⣿⣯⣿⣯⣿⣿⣿⣟⣧⠛⢉⣤⣶⣾⣿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⣴⣫⠓⢱⣯⣿⢿⠋⠛⢛⠟⠯⠶⢟⣿⣯⣿⣿⣿⣿⣿⣿⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[36;1m" + "⠀⠀⠀⠀⠀⠀⢀⡮⢁⣴⣿⣿⣿⠖⣠⠐⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠛⠛⠛⢿⣶⣄⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[36;1m" + E + "[35;1m" + "⠀⠀⠀⠀⢀⣤⣷⣿⣿⠿⢛⣭⠒⠉⠀⠀⠀⣀⣀⣄⣤⣤⣴⣶⣶⣶⣿⣿⣿⣿⣿⠿⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[35;1m" + E + "[31;1m" + "⠀⢀⣶⠏⠟⠝⠉⢀⣤⣿⣿⣶⣾⣿⣿⣿⣿⣿⣿⣟⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "⢴⣯⣤⣶⣿⣿⣿⣿⣿⡿⣿⣯⠉⠉⠉⠉⠀⠀⠀⠈⣿⡀⣟⣿⣿⢿⣿⣿⣿⣿⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "⠀⠀⠀⠉⠛⣿⣧⠀⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠃⣿⣿⣯⣿⣦⡀⠀⠉⠻⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[35;1m" + "⠀⠀⠀⠀⠀⠀⠉⢿⣮⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⠀⣯⠉⠉⠛⢿⣿⣷⣄⠀⠈⢻⣆⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[35;1m" + E + "[36;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠢⠀⠀⠀⠀⠀⠀⠀⢀⢡⠃⣾⣿⣿⣦⠀⠀⠀⠙⢿⣿⣤⠀⠙⣄⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[36;1m" + E + "[32;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⢋⡟⢠⣿⣿⣿⠋⢿⣄⠀⠀⠀⠈⡄⠙⣶⣈⡄⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + E + "[31;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠚⢲⣿⠀⣾⣿⣿⠁⠀⠀⠉⢷⡀⠀⠀⣇⠀⠀⠈⠻⡀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢢⣀⣿⡏⠀⣿⡿⠀⠀⠀⠀⠀⠀⠙⣦⠀⢧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[33;1m" + E + "[35;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠿⣧⣾⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣮⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[35;1m" + E + "[32;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠙⠛⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[32;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "fedora") {
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
    if startsWith(dn, "funtoo") {
        a = a + E + "[35;1m" + E + "[35;1m" + "   .dKXXd                         ." + R + "\n"
        a = a + E + "[35;1m" + "  :XXl;:.                      .OXo" + R + "\n"
        a = a + E + "[35;1m" + ".'OXO''  .''''''''''''''''''''':XNd..'oco.lco," + R + "\n"
        a = a + E + "[35;1m" + "xXXXXXX, cXXXNNNXXXXNNXXXXXXXXNNNNKOOK; d0O .k" + R + "\n"
        a = a + E + "[35;1m" + "  kXX  xXo  KNNN0  KNN.       'xXNo   :c; 'cc." + R + "\n"
        a = a + E + "[35;1m" + "  kXX  xNo  KNNN0  KNN. :xxxx. 'NNo" + R + "\n"
        a = a + E + "[35;1m" + "  kXX  xNo  loooc  KNN. oNNNN. 'NNo" + R + "\n"
        a = a + E + "[35;1m" + "  kXX  xN0:.       KNN' oNNNX' ,XNk" + R + "\n"
        a = a + E + "[35;1m" + "  kXX  xNNXNNNNNNNNXNNNNNNNNXNNOxXNX0Xl" + R + "\n"
        a = a + E + "[35;1m" + "  ...  ......................... .;cc;." + R + "\n"
        emit a
    }
    if startsWith(dn, "garuda") {
        a = a + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + E + "[33;1m" + R + "\n"
        a = a + E + "[33;1m" + "                     .%;888:8898898:" + R + "\n"
        a = a + E + "[33;1m" + "                   x;XxXB%89b8:b8%b88:" + R + "\n"
        a = a + E + "[33;1m" + "                .8Xxd                8X:." + R + "\n"
        a = a + E + "[33;1m" + "              .8Xx;                    8x:." + R + "\n"
        a = a + E + "[33;1m" + "            .tt8x          " + E + "[34;1m" + ".d" + E + "[33;1m" + "            x88;" + R + "\n"
        a = a + E + "[33;1m" + "         .@8x8;          " + E + "[34;1m" + ".db:" + E + "[33;1m" + "              xx@;" + R + "\n"
        a = a + E + "[33;1m" + "       " + E + "[37;1m" + ",tSXX°          .bbbbbbbbbbbbbbbbbbbB8x@;" + R + "\n"
        a = a + E + "[37;1m" + "     .SXxx            bBBBBBBBBBBBBBBBBBBBbSBX8;" + R + "\n"
        a = a + E + "[37;1m" + "   ,888S                                     pd!" + R + "\n"
        a = a + E + "[37;1m" + "  8X88/                                       q" + R + "\n"
        a = a + E + "[37;1m" + "  GBB." + R + "\n"
        a = a + E + "[37;1m" + "   " + E + "[32;1m" + "x%88        d888@8@X@X@X88X@@XX@@X@8@X." + R + "\n"
        a = a + E + "[32;1m" + "     dxXd    dB8b8b8B8B08bB88b998888b88x." + R + "\n"
        a = a + E + "[32;1m" + "      dxx8o                      .@@;." + R + "\n"
        a = a + E + "[32;1m" + "        dx88                   .t@x." + R + "\n"
        a = a + E + "[32;1m" + "          d:SS@8ba89aa67a853Sxxad." + R + "\n"
        a = a + E + "[32;1m" + "            .d988999889889899dd." + R + "\n"
        a = a + E + "[32;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "gentoo") {
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
    emit ""
}
func distroArt_15(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "pentoo") {
        a = a + E + "[35;1m" + E + "[37;1m" + "           `:oydNNMMMMNNdyo:`" + R + "\n"
        a = a + E + "[37;1m" + "        :yNMMMMMMMMMMMMMMMMNy:" + R + "\n"
        a = a + E + "[37;1m" + "      :dMMMMMMMMMMMMMMMMMMMMMMd:" + R + "\n"
        a = a + E + "[37;1m" + "     oMMMMMMMho/-....-/ohMMMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + "    oMMMMMMy.            .yMMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + "   .MMMMMMo                oMMMMMM." + R + "\n"
        a = a + E + "[37;1m" + "   +MMMMMm                  mMMMMM+" + R + "\n"
        a = a + E + "[37;1m" + "   oMMMMMh                  hMMMMMo" + R + "\n"
        a = a + E + "[37;1m" + " //hMMMMMm//" + E + "[35;1m" + "`" + E + "[37;1m" + "          " + E + "[35;1m" + "`" + E + "[37;1m" + "////mMMMMMh//" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMM" + E + "[35;1m" + "/" + E + "[37;1m" + "      " + E + "[35;1m" + "/o/`" + E + "[37;1m" + "  " + E + "[35;1m" + "." + E + "[37;1m" + "smMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMm      " + E + "[35;1m" + "`NMN:" + E + "[37;1m" + "    " + E + "[35;1m" + "." + E + "[37;1m" + "yMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMh" + E + "[35;1m" + ":." + E + "[37;1m" + "              dMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMy" + E + "[35;1m" + "." + E + "[37;1m" + "            " + E + "[35;1m" + "-" + E + "[37;1m" + "NMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMd:" + E + "[35;1m" + "`" + E + "[37;1m" + "           " + E + "[35;1m" + "-" + E + "[37;1m" + "yNMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMh" + E + "[35;1m" + "`" + E + "[37;1m" + "          " + E + "[35;1m" + "./" + E + "[37;1m" + "hNMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMM" + E + "[35;1m" + "s" + E + "[37;1m" + "        " + E + "[35;1m" + ".:" + E + "[37;1m" + "ymMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMN" + E + "[35;1m" + "s:..-/" + E + "[37;1m" + "ohNMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + " MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + R + "\n"
        emit a
    }
    if startsWith(dn, "huayra") {
        a = a + E + "[34;1m" + E + "[37;1m" + "                     `" + R + "\n"
        a = a + E + "[37;1m" + "            .       .       `" + R + "\n"
        a = a + E + "[37;1m" + "       ``    -      .      ." + R + "\n"
        a = a + E + "[37;1m" + "        `.`   -` `. -  `` .`" + R + "\n"
        a = a + E + "[37;1m" + "          ..`-`-` + -  / .`     ```" + R + "\n"
        a = a + E + "[37;1m" + "          .--.+--`+:- :/.` .-``.`" + R + "\n"
        a = a + E + "[37;1m" + "            -+/so::h:.d-`./:`.`" + R + "\n"
        a = a + E + "[37;1m" + "              :hNhyMomy:os-...-.  ````" + R + "\n"
        a = a + E + "[37;1m" + "               .dhsshNmNhoo+:-``.```" + R + "\n"
        a = a + E + "[37;1m" + "                " + E + "[34;1m" + "`ohy:-" + E + "[37;1m" + "NMds+::-.``" + R + "\n"
        a = a + E + "[37;1m" + "            ````" + E + "[34;1m" + ".hNN+`" + E + "[37;1m" + "mMNho/:-....````" + R + "\n"
        a = a + E + "[37;1m" + "       `````     `../dmNhoo+/:..``" + R + "\n"
        a = a + E + "[37;1m" + "    ````            .dh++o/:....`" + R + "\n"
        a = a + E + "[37;1m" + ".+s/`                `/s-.-.:.`` ````" + R + "\n"
        a = a + E + "[37;1m" + "::`                    `::`..`" + R + "\n"
        a = a + E + "[37;1m" + "                          .` `.." + R + "\n"
        a = a + E + "[37;1m" + "                                ``" + R + "\n"
        emit a
    }
    if startsWith(dn, "kaisen") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                          `" + R + "\n"
        a = a + E + "[31;1m" + "                  `:+oyyho." + R + "\n"
        a = a + E + "[31;1m" + "             `+:`sdddddd/" + R + "\n"
        a = a + E + "[31;1m" + "        `+` :ho oyo++ohds-`" + R + "\n"
        a = a + E + "[31;1m" + "       .ho :dd.  .: `sddddddhhyso+/-" + R + "\n"
        a = a + E + "[31;1m" + "       ody.ddd-:yd- +hysssyhddddddddho`" + R + "\n"
        a = a + E + "[31;1m" + "       yddddddhddd` ` `--`   -+hddddddh." + R + "\n"
        a = a + E + "[31;1m" + "       hddy-+dddddy+ohh/..+sddddy/:::+ys" + R + "\n"
        a = a + E + "[31;1m" + "      :ddd/sdddddddddd- oddddddd       `" + R + "\n"
        a = a + E + "[31;1m" + "     `yddddddddddddddd/ /ddddddd/" + R + "\n"
        a = a + E + "[31;1m" + ":.  :ydddddddddddddddddo..sddddddy/`" + R + "\n"
        a = a + E + "[31;1m" + "odhdddddddo- `ddddh+-``....-+hdddddds." + R + "\n"
        a = a + E + "[31;1m" + "-ddddddhd:   /dddo  -ydddddddhdddddddd-" + R + "\n"
        a = a + E + "[31;1m" + " /hdy:o - `:sddds   .`./hdddddddddddddo" + R + "\n"
        a = a + E + "[31;1m" + "  `/-  `+hddyosy+       :dddddddy-.-od/" + R + "\n"
        a = a + E + "[31;1m" + "      :sydds           -hddddddd`    /" + R + "\n"
        a = a + E + "[31;1m" + "       .+shd-      `:ohddddddddd`" + R + "\n"
        a = a + E + "[31;1m" + "                `:+ooooooooooooo:" + R + "\n"
        emit a
    }
    if startsWith(dn, "korora") {
        a = a + E + "[34;1m" + E + "[37;1m" + "                ____________" + R + "\n"
        a = a + E + "[37;1m" + "             _add55555555554" + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + "           _w?'" + E + "[34;1m" + "``````````'" + E + "[37;1m" + ")k" + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + "          _Z'" + E + "[34;1m" + "`" + E + "[37;1m" + "            ]k" + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + "          m(" + E + "[34;1m" + "`" + E + "[37;1m" + "             )k" + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + "     _.ss" + E + "[34;1m" + "`" + E + "[37;1m" + "m[" + E + "[34;1m" + "`" + E + "[37;1m" + ",            ]e" + E + "[34;1m" + ":" + R + "\n"
        a = a + E + "[34;1m" + "   .uY\"^`" + E + "[34;1m" + "`" + E + "[37;1m" + "Xc" + E + "[34;1m" + "`" + E + "[37;1m" + "?Ss.         d(" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + "  jF'" + E + "[34;1m" + "`" + E + "[37;1m" + "    `@.  " + E + "[34;1m" + "`" + E + "[37;1m" + "Sc      .jr" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + " jr" + E + "[34;1m" + "`" + E + "[37;1m" + "       `?n_ " + E + "[34;1m" + "`" + E + "[37;1m" + "$;   _a2\"" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + ".m" + E + "[34;1m" + ":" + E + "[37;1m" + "          `~M" + E + "[34;1m" + "`" + E + "[37;1m" + "1k" + E + "[34;1m" + "`" + E + "[37;1m" + "5?!`" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + ":#" + E + "[34;1m" + ":" + E + "[37;1m" + "             " + E + "[34;1m" + "`" + E + "[37;1m" + ")e" + E + "[34;1m" + "```" + R + "\n"
        a = a + E + "[34;1m" + ":m" + E + "[34;1m" + ":" + E + "[37;1m" + "             ,#'" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + ":#" + E + "[34;1m" + ":" + E + "[37;1m" + "           .s2'" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + ":m,________.aa7^" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + ":#baaaaaaas!J'" + E + "[34;1m" + "`" + R + "\n"
        a = a + E + "[34;1m" + " ```````````" + R + "\n"
        emit a
    }
    if startsWith(dn, "mac") || startsWith(dn, "darwin") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                    c.'" + R + "\n"
        a = a + E + "[32;1m" + "                 ,xNMM." + R + "\n"
        a = a + E + "[32;1m" + "               .OMMMMo" + R + "\n"
        a = a + E + "[32;1m" + "               lMM\"" + R + "\n"
        a = a + E + "[32;1m" + "     .;loddo:.  .olloddol;." + R + "\n"
        a = a + E + "[32;1m" + "   cKMMMMMMMMMMNWMMMMMMMMMM0:" + R + "\n"
        a = a + E + "[32;1m" + E + "[33;1m" + " .KMMMMMMMMMMMMMMMMMMMMMMMWd." + R + "\n"
        a = a + E + "[33;1m" + " XMMMMMMMMMMMMMMMMMMMMMMMX." + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + ";MMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + ":MMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + ".MMMMMMMMMMMMMMMMMMMMMMMMX." + R + "\n"
        a = a + E + "[31;1m" + " kMMMMMMMMMMMMMMMMMMMMMMMMWd." + R + "\n"
        a = a + E + "[31;1m" + " " + E + "[35;1m" + "'XMMMMMMMMMMMMMMMMMMMMMMMMMMk" + R + "\n"
        a = a + E + "[35;1m" + "  'XMMMMMMMMMMMMMMMMMMMMMMMMK." + R + "\n"
        a = a + E + "[35;1m" + "    " + E + "[34;1m" + "kMMMMMMMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "     ;KMMMMMMMWXXWMMMMMMMk." + R + "\n"
        a = a + E + "[34;1m" + "       \"cooc*\"    \"*coo'\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "mageia") {
        a = a + E + "[36;1m" + E + "[36;1m" + "        .°°." + R + "\n"
        a = a + E + "[36;1m" + "         °°   .°°." + R + "\n"
        a = a + E + "[36;1m" + "         .°°°. °°" + R + "\n"
        a = a + E + "[36;1m" + "         .   ." + R + "\n"
        a = a + E + "[36;1m" + "          °°° .°°°." + R + "\n"
        a = a + E + "[36;1m" + "      .°°°.   '___'" + R + "\n"
        a = a + E + "[36;1m" + E + "[37;1m" + "     ." + E + "[36;1m" + "'___'     " + E + "[37;1m" + "   ." + R + "\n"
        a = a + E + "[37;1m" + "   :dkxc;'.  ..,cxkd;" + R + "\n"
        a = a + E + "[37;1m" + " .dkk. kkkkkkkkkk .kkd." + R + "\n"
        a = a + E + "[37;1m" + ".dkk.  ';cloolc;.  .kkd" + R + "\n"
        a = a + E + "[37;1m" + "ckk.                .kk;" + R + "\n"
        a = a + E + "[37;1m" + "xO:                  cOd" + R + "\n"
        a = a + E + "[37;1m" + "xO:                  lOd" + R + "\n"
        a = a + E + "[37;1m" + "lOO.                .OO:" + R + "\n"
        a = a + E + "[37;1m" + ".k00.              .00x" + R + "\n"
        a = a + E + "[37;1m" + " .k00;            ;00O." + R + "\n"
        a = a + E + "[37;1m" + "  .lO0Kc;,,,,,,;c0KOc." + R + "\n"
        a = a + E + "[37;1m" + "     ;d00KKKKKK00d;" + R + "\n"
        a = a + E + "[37;1m" + "        .,KKKK,." + R + "\n"
        emit a
    }
    if startsWith(dn, "tearch") {
        a = a + E + "[38;5;39m" + E + "[38;5;39m" + "          @@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "      @@@@@@@@@              @@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "     @@@@@                     @@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "     @@                           @@" + R + "\n"
        a = a + E + "[38;5;39m" + "      @%                         @@" + R + "\n"
        a = a + E + "[38;5;39m" + "       @                         @" + R + "\n"
        a = a + E + "[38;5;39m" + "       @@@@@@@@@@@@@@@@@@@@@@@@ @@" + R + "\n"
        a = a + E + "[38;5;39m" + "       .@@@@@@@@@@@@/@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "       @@@@@@@@@@@@///@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "      @@@@@@@@@@@@@((((@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "     @@@@@@@@@@@#(((((((#@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "    @@@@@@@@@@@#//////////@@@@@@@@@@&" + R + "\n"
        a = a + E + "[38;5;39m" + "    @@@@@@@@@@////@@@@@////@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "    @@@@@@@@//////@@@@@/////@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "    @@@@@@@//@@@@@@@@@@@@@@@//@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + " @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "@@     .@@@@@@@@@@@@@@@@@@@@@@@@@      @" + R + "\n"
        a = a + E + "[38;5;39m" + " @@@@@@           @@@.           @@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "   @@@@@@@&@@@@@@@#  #@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[38;5;39m" + "          @@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        emit a
    }
    if startsWith(dn, "netbsd") {
        a = a + E + "[35;1m" + E + "[35;1m" + "                     `-/oshdmNMNdhyo+:-`" + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "y" + E + "[35;1m" + "/s+:-``    `.-:+oydNMMMMNhs/-``" + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "-m+" + E + "[35;1m" + "NMMMMMMMMMMMMMMMMMMMNdhmNMMMmdhs+/-`" + R + "\n"
        a = a + E + "[35;1m" + " " + E + "[37;1m" + "-m+" + E + "[35;1m" + "NMMMMMMMMMMMMMMMMMMMMmy+:`" + R + "\n"
        a = a + E + "[35;1m" + "  " + E + "[37;1m" + "-N/" + E + "[35;1m" + "dMMMMMMMMMMMMMMMds:`" + R + "\n"
        a = a + E + "[35;1m" + "   " + E + "[37;1m" + "-N/" + E + "[35;1m" + "hMMMMMMMMMmho:`" + R + "\n"
        a = a + E + "[35;1m" + "    " + E + "[37;1m" + "-N/" + E + "[35;1m" + "-:/++/:.`" + R + "\n"
        a = a + E + "[35;1m" + E + "[37;1m" + "     :M+" + R + "\n"
        a = a + E + "[37;1m" + "      :Mo" + R + "\n"
        a = a + E + "[37;1m" + "       :Ms" + R + "\n"
        a = a + E + "[37;1m" + "        :Ms" + R + "\n"
        a = a + E + "[37;1m" + "         :Ms" + R + "\n"
        a = a + E + "[37;1m" + "          :Ms" + R + "\n"
        a = a + E + "[37;1m" + "           :Ms" + R + "\n"
        a = a + E + "[37;1m" + "            :Ms" + R + "\n"
        a = a + E + "[37;1m" + "             :Ms" + R + "\n"
        a = a + E + "[37;1m" + "              :Ms" + R + "\n"
        emit a
    }
    if startsWith(dn, "nitrux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "`:/." + R + "\n"
        a = a + E + "[34;1m" + "`/yo" + R + "\n"
        a = a + E + "[34;1m" + "`/yo" + R + "\n"
        a = a + E + "[34;1m" + "`/yo      .+:." + R + "\n"
        a = a + E + "[34;1m" + "`/yo      .sys+:.`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo       `-/sys+:.`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo           ./sss+:.`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo              .:oss+:-`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo                 ./o///:-`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo              `.-:///////:`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo           `.://///++//-``" + R + "\n"
        a = a + E + "[34;1m" + "`/yo       `.-:////++++/-`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo    `-://///++o+/-`" + R + "\n"
        a = a + E + "[34;1m" + "`/yo `-/+o+++ooo+/-`" + R + "\n"
        a = a + E + "[34;1m" + "`/s+:+oooossso/.`" + R + "\n"
        a = a + E + "[34;1m" + "`//+sssssso:." + R + "\n"
        a = a + E + "[34;1m" + "`+syyyy+:`" + R + "\n"
        a = a + E + "[34;1m" + ":+s+-" + R + "\n"
        emit a
    }
    if startsWith(dn, "oracle") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "      `-/+++++++++++++++++/-.`" + R + "\n"
        a = a + E + "[31;1m" + "   `/syyyyyyyyyyyyyyyyyyyyyyys/." + R + "\n"
        a = a + E + "[31;1m" + "  :yyyyo/-...............-/oyyyy/" + R + "\n"
        a = a + E + "[31;1m" + " /yyys-                     .oyyy+" + R + "\n"
        a = a + E + "[31;1m" + ".yyyy`                       `syyy-" + R + "\n"
        a = a + E + "[31;1m" + ":yyyo                         /yyy/" + R + "\n"
        a = a + E + "[31;1m" + ".yyyy`                       `syyy-" + R + "\n"
        a = a + E + "[31;1m" + " /yyys.                     .oyyyo" + R + "\n"
        a = a + E + "[31;1m" + "  /yyyyo:-...............-:oyyyy/`" + R + "\n"
        a = a + E + "[31;1m" + "   `/syyyyyyyyyyyyyyyyyyyyyyys+." + R + "\n"
        a = a + E + "[31;1m" + "     `.:/+ooooooooooooooo+/:.`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_16(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "pacbsd") {
        a = a + E + "[31;1m" + E + "[31;1m" + "      :+sMs." + R + "\n"
        a = a + E + "[31;1m" + "  `:ddNMd-                         -o--`" + R + "\n"
        a = a + E + "[31;1m" + " -sMMMMh:                          `+N+``" + R + "\n"
        a = a + E + "[31;1m" + " yMMMMMs`     .....-/-...           `mNh/" + R + "\n"
        a = a + E + "[31;1m" + " yMMMMMmh+-`:sdmmmmmmMmmmmddy+-``./ddNMMm" + R + "\n"
        a = a + E + "[31;1m" + " yNMMNMMMMNdyyNNMMMMMMMMMMMMMMMhyshNmMMMm" + R + "\n"
        a = a + E + "[31;1m" + " :yMMMMMMMMMNdooNMMMMMMMMMMMMMMMMNmy:mMMd" + R + "\n"
        a = a + E + "[31;1m" + "  +MMMMMMMMMmy:sNMMMMMMMMMMMMMMMMMMMmshs-" + R + "\n"
        a = a + E + "[31;1m" + "  :hNMMMMMMN+-+MMMMMMMMMMMMMMMMMMMMMMMs." + R + "\n"
        a = a + E + "[31;1m" + " .omysmNNhy/+yNMMMMMMMMMMNMMMMMMMMMNdNNy-" + R + "\n"
        a = a + E + "[31;1m" + " /hMM:::::/hNMMMMMMMMMMMm/-yNMMMMMMN.mMNh`" + R + "\n"
        a = a + E + "[31;1m" + ".hMMMMdhdMMMMMMMMMMMMMMmo  `sMMMMMMN mMMm-" + R + "\n"
        a = a + E + "[31;1m" + ":dMMMMMMMMMMMMMMMMMMMMMdo+  oMMMMMMN`smMNo`" + R + "\n"
        a = a + E + "[31;1m" + "/dMMMMMMMMMMMMMMMMMMMMMNd/` :yMMMMMN:-hMMM." + R + "\n"
        a = a + E + "[31;1m" + ":dMMMMMMMMMMMMMMMMMMMMMNh`  oMMMMMMNo/dMNN`" + R + "\n"
        a = a + E + "[31;1m" + ":hMMMMMMMMMMMMMMMMMMMMMMNs--sMMMMMMMNNmy++`" + R + "\n"
        a = a + E + "[31;1m" + " sNMMMMMMMMMMMMMMMMMMMMMMMmmNMMMMMMNho::o." + R + "\n"
        a = a + E + "[31;1m" + " :yMMMMMMMMMMMMMNho+sydNNNNNNNmysso/` -//" + R + "\n"
        a = a + E + "[31;1m" + "  /dMMMMMMMMMMMMMs-  ````````..``" + R + "\n"
        a = a + E + "[31;1m" + "   .oMMMMMMMMMMMMNs`               ./y:`" + R + "\n"
        a = a + E + "[31;1m" + "     +dNMMNMMMMMMMmy`          ``./ys." + R + "\n"
        a = a + E + "[31;1m" + "      `/hMMMMMMMMMMMNo-``    `.+yy+-`" + R + "\n"
        a = a + E + "[31;1m" + "        `-/hmNMNMMMMMMmmddddhhy/-`" + R + "\n"
        a = a + E + "[31;1m" + "            `-+oooyMMMdsoo+/:." + R + "\n"
        emit a
    }
    if startsWith(dn, "pardus") {
        a = a + E + "[33;1m" + E + "[33;1m" + " .smNdy+-    `.:/osyyso+:.`    -+ydmNs." + R + "\n"
        a = a + E + "[33;1m" + "/Md- -/ymMdmNNdhso/::/oshdNNmdMmy/. :dM/" + R + "\n"
        a = a + E + "[33;1m" + "mN.     oMdyy- -y          `-dMo     .Nm" + R + "\n"
        a = a + E + "[33;1m" + ".mN+`  sMy hN+ -:             yMs  `+Nm." + R + "\n"
        a = a + E + "[33;1m" + " `yMMddMs.dy `+`               sMddMMy`" + R + "\n"
        a = a + E + "[33;1m" + "   +MMMo  .`  .                 oMMM+" + R + "\n"
        a = a + E + "[33;1m" + "   `NM/    `````.`    `.`````    +MN`" + R + "\n"
        a = a + E + "[33;1m" + "   yM+   `.-:yhomy    ymohy:-.`   +My" + R + "\n"
        a = a + E + "[33;1m" + "   yM:          yo    oy          :My" + R + "\n"
        a = a + E + "[33;1m" + "   +Ms         .N`    `N.      +h sM+" + R + "\n"
        a = a + E + "[33;1m" + "   `MN      -   -::::::-   : :o:+`NM`" + R + "\n"
        a = a + E + "[33;1m" + "    yM/    sh   -dMMMMd-   ho  +y+My" + R + "\n"
        a = a + E + "[33;1m" + "    .dNhsohMh-//: /mm/ ://-yMyoshNd`" + R + "\n"
        a = a + E + "[33;1m" + "      `-ommNMm+:/. oo ./:+mMNmmo:`" + R + "\n"
        a = a + E + "[33;1m" + "     `/o+.-somNh- :yy: -hNmos-.+o/`" + R + "\n"
        a = a + E + "[33;1m" + "    ./` .s/`s+sMdd+``+ddMs+s`/s. `/." + R + "\n"
        a = a + E + "[33;1m" + "        : -y.  -hNmddmNy.  .y- :" + R + "\n"
        a = a + E + "[33;1m" + "         -+       `..`       +-" + R + "\n"
        emit a
    }
    if startsWith(dn, "parrot") {
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
    if startsWith(dn, "parsix") {
        a = a + E + "[33;1m" + "                 " + E + "[31;1m" + "-/+/:." + R + "\n"
        a = a + E + "[31;1m" + "               " + E + "[31;1m" + ".syssssys." + R + "\n"
        a = a + E + "[31;1m" + "       " + E + "[33;1m" + ".--.    " + E + "[31;1m" + "ssssssssso" + E + "[33;1m" + "   ..--." + R + "\n"
        a = a + E + "[33;1m" + "     :++++++:  " + E + "[31;1m" + "+ssssssss+" + E + "[33;1m" + " ./++/+++:" + R + "\n"
        a = a + E + "[33;1m" + "    /+++++++++." + E + "[31;1m" + ".yssooooy`" + E + "[33;1m" + "-+///////o-" + R + "\n"
        a = a + E + "[33;1m" + "    /++++++++++." + E + "[31;1m" + "+soooos:" + E + "[33;1m" + ":+////////+-" + R + "\n"
        a = a + E + "[33;1m" + "     :+++++////o-" + E + "[31;1m" + "oooooo-" + E + "[33;1m" + "+/////////-" + R + "\n"
        a = a + E + "[33;1m" + "      `-/++//++-" + E + "[38;5;8m" + ".-----.-" + E + "[33;1m" + ":+/////:-" + R + "\n"
        a = a + E + "[33;1m" + "  " + E + "[37;1m" + "-://::--" + E + "[33;1m" + "-:/:" + E + "[38;5;8m" + ".--.````.--." + E + "[33;1m" + ":::-" + E + "[37;1m" + "--::::::." + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "-/:::::::://:" + E + "[38;5;8m" + ".:-`      `-:" + E + "[37;1m" + "`:/:::::::--/-" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "/::::::::::/-" + E + "[38;5;8m" + "--.        .-." + E + "[37;1m" + "-/://///::::/" + R + "\n"
        a = a + E + "[37;1m" + E + "[37;1m" + "-/:::::::::/:" + E + "[38;5;8m" + "`:-.      .-:" + E + "[37;1m" + "`:///////////-" + R + "\n"
        a = a + E + "[37;1m" + " `" + E + "[37;1m" + "-::::--" + E + "[33;1m" + ".-://." + E + "[38;5;8m" + "---....---" + E + "[33;1m" + "`:+/:-" + E + "[37;1m" + "--::::-`" + R + "\n"
        a = a + E + "[37;1m" + "       " + E + "[33;1m" + "-/+///+o/-" + E + "[38;5;8m" + ".----." + E + "[33;1m" + ".:oo+++o+." + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[33;1m" + "-+/////+++o:" + E + "[31;1m" + "syyyyy." + E + "[33;1m" + "o+++++++++:" + R + "\n"
        a = a + E + "[33;1m" + "    " + E + "[33;1m" + ".+////+++++-" + E + "[31;1m" + "+sssssy+" + E + "[33;1m" + ".++++++++++\\" + R + "\n"
        a = a + E + "[33;1m" + "    " + E + "[33;1m" + ".+:/++++++." + E + "[31;1m" + ".yssssssy-" + E + "[33;1m" + "`+++++++++:" + R + "\n"
        a = a + E + "[33;1m" + "     " + E + "[33;1m" + ":/+++++-  " + E + "[31;1m" + "+sssssssss  " + E + "[33;1m" + "-++++++-" + R + "\n"
        a = a + E + "[33;1m" + "       " + E + "[33;1m" + "`--`    " + E + "[31;1m" + "+sssssssso    " + E + "[33;1m" + "`--`" + R + "\n"
        a = a + E + "[33;1m" + "                " + E + "[31;1m" + "+sssssy+`" + R + "\n"
        a = a + E + "[31;1m" + "                 " + E + "[31;1m" + "`.::-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "pcbsd") || startsWith(dn, "trueos") {
        a = a + E + "[31;1m" + E + "[31;1m" + "                       .." + R + "\n"
        a = a + E + "[31;1m" + "                        s." + R + "\n"
        a = a + E + "[31;1m" + "                        +y" + R + "\n"
        a = a + E + "[31;1m" + "                        yN" + R + "\n"
        a = a + E + "[31;1m" + "                       -MN  `." + R + "\n"
        a = a + E + "[31;1m" + "                      :NMs `m" + R + "\n"
        a = a + E + "[31;1m" + "                    .yMMm` `No" + R + "\n"
        a = a + E + "[31;1m" + "            `-/+++sdMMMNs+-`+Ms" + R + "\n"
        a = a + E + "[31;1m" + "        `:oo+-` .yMMMMy` `-+oNMh" + R + "\n"
        a = a + E + "[31;1m" + "      -oo-     +NMMMM/       oMMh-" + R + "\n"
        a = a + E + "[31;1m" + "    .s+` `    oMMMMM/     -  oMMMhy." + R + "\n"
        a = a + E + "[31;1m" + "   +s`- ::   :MMMMMd     -o `mMMMy`s+" + R + "\n"
        a = a + E + "[31;1m" + "  y+  h .Ny+oNMMMMMN/    sh+NMMMMo  +y" + R + "\n"
        a = a + E + "[31;1m" + " s+ .ds  -NMMMMMMMMMMNdhdNMMMMMMh`   +s" + R + "\n"
        a = a + E + "[31;1m" + "-h .NM`   `hMMMMMMMMMMMMMMNMMNy:      h-" + R + "\n"
        a = a + E + "[31;1m" + "y- hMN`     hMMmMMMMMMMMMNsdMNs.      -y" + R + "\n"
        a = a + E + "[31;1m" + "m` mMMy`    oMMNoNMMMMMMo`  sMMMo     `m" + R + "\n"
        a = a + E + "[31;1m" + "m` :NMMMdyydMMMMo+MdMMMs     sMMMd`   `m" + R + "\n"
        a = a + E + "[31;1m" + "h-  `+ymMMMMMMMM--M+hMMN/    +MMMMy   -h" + R + "\n"
        a = a + E + "[31;1m" + ":y     `.sMMMMM/ oMM+.yMMNddNMMMMMm   y:" + R + "\n"
        a = a + E + "[31;1m" + " y:   `s  dMMN- .MMMM/ :MMMMMMMMMMh  :y" + R + "\n"
        a = a + E + "[31;1m" + " `h:  `mdmMMM/  yMMMMs  sMMMMMMMMN- :h`" + R + "\n"
        a = a + E + "[31;1m" + "   so  -NMMMN   /mmd+  `dMMMMMMMm- os" + R + "\n"
        a = a + E + "[31;1m" + "    :y: `yMMM`       `+NMMMMMMNo`:y:" + R + "\n"
        a = a + E + "[31;1m" + "      /s+`.omy      /NMMMMMNh/.+s:" + R + "\n"
        a = a + E + "[31;1m" + "        .+oo:-.     /mdhs+::oo+." + R + "\n"
        a = a + E + "[31;1m" + "            -/o+++++++++++/-" + R + "\n"
        emit a
    }
    if startsWith(dn, "puffos") {
        a = a + E + "[33;1m" + E + "[33;1m" + R + "\n"
        a = a + E + "[33;1m" + "              _,..._,m," + R + "\n"
        a = a + E + "[33;1m" + "            ,/'      '\"\";" + R + "\n"
        a = a + E + "[33;1m" + "           /             \"." + R + "\n"
        a = a + E + "[33;1m" + "         ,'mmmMMMMmm.      \\" + R + "\n"
        a = a + E + "[33;1m" + "       _/-\"^^^^^\"\"\"%#%mm,   ;" + R + "\n"
        a = a + E + "[33;1m" + " ,m,_,'              \"###)  ;," + R + "\n"
        a = a + E + "[33;1m" + "(###%                 \\#/  ;##mm." + R + "\n"
        a = a + E + "[33;1m" + " ^#/  __        ___    ;  (######)" + R + "\n"
        a = a + E + "[33;1m" + "  ;  //.\\\\     //.\\\\   ;   \\####/" + R + "\n"
        a = a + E + "[33;1m" + " _; (#\\\"//     \\\\\"/#)  ;  ,/" + R + "\n"
        a = a + E + "[33;1m" + "@##\\ \\##/   =   `\"=\" ,;mm/" + R + "\n"
        a = a + E + "[33;1m" + "`\\##>.____,...,____,<####@" + R + "\n"
        emit a
    }
    if startsWith(dn, "pureos") {
        a = a + E + "[32;1m" + E + "[32;1m" + "dmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmd" + R + "\n"
        a = a + E + "[32;1m" + "dNm//////////////////////////////////mNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNd                                  dNd" + R + "\n"
        a = a + E + "[32;1m" + "dNm//////////////////////////////////mNd" + R + "\n"
        a = a + E + "[32;1m" + "dmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmd" + R + "\n"
        emit a
    }
    if startsWith(dn, "regata") {
        a = a + E + "[37;1m" + E + "[37;1m" + "            ddhso+++++osydd" + R + "\n"
        a = a + E + "[37;1m" + "        dho/.`hh" + E + "[31;1m" + ".:/+/:." + E + "[37;1m" + "hhh`:+yd" + R + "\n"
        a = a + E + "[37;1m" + "      do-hhhhhh" + E + "[31;1m" + "/sssssss+`" + E + "[37;1m" + "hhhhh./yd" + R + "\n"
        a = a + E + "[37;1m" + "    h/`hhhhhhh" + E + "[31;1m" + "-sssssssss:" + E + "[37;1m" + "hhhhhhhh-yd" + R + "\n"
        a = a + E + "[37;1m" + "  do`hhhhhhhhh" + E + "[31;1m" + "`ossssssso." + E + "[37;1m" + "hhhhhhhhhh/d" + R + "\n"
        a = a + E + "[37;1m" + " d/hhhhhhhhhhhh" + E + "[31;1m" + "`/ossso/." + E + "[37;1m" + "hhhhhhhhhhhh.h" + R + "\n"
        a = a + E + "[37;1m" + " /hhhhhhhhhhhh" + E + "[34;1m" + "`-/osyso/-`" + E + "[37;1m" + "hhhhhhhhhhhh.h" + R + "\n"
        a = a + E + "[37;1m" + "shh" + E + "[35;1m" + "-/ooo+-" + E + "[37;1m" + "hhh" + E + "[34;1m" + ":syyso+osyys/`" + E + "[37;1m" + "hhh" + E + "[33;1m" + "`+oo`" + E + "[37;1m" + "hhh/" + R + "\n"
        a = a + E + "[37;1m" + "h" + E + "[35;1m" + "`ohhhhhhho`" + E + "[34;1m" + "+yyo." + E + "[37;1m" + "hhhhh" + E + "[34;1m" + ".+yyo`" + E + "[33;1m" + ".sssssss." + E + "[37;1m" + "h`h" + R + "\n"
        a = a + E + "[37;1m" + "s" + E + "[35;1m" + ":hhhhhhhhho" + E + "[34;1m" + "yys`" + E + "[37;1m" + "hhhhhhh" + E + "[34;1m" + ".oyy/" + E + "[33;1m" + "ossssssso-" + E + "[37;1m" + "hs" + R + "\n"
        a = a + E + "[37;1m" + "s" + E + "[35;1m" + ".yhhhhhhhy/" + E + "[34;1m" + "yys`" + E + "[37;1m" + "hhhhhhh" + E + "[34;1m" + ".oyy/" + E + "[33;1m" + "ossssssso-" + E + "[37;1m" + "hs" + R + "\n"
        a = a + E + "[37;1m" + "hh" + E + "[35;1m" + "./syyys+." + E + "[37;1m" + " " + E + "[34;1m" + "+yy+." + E + "[37;1m" + "hhhhh" + E + "[34;1m" + ".+yyo`" + E + "[33;1m" + ".ossssso/" + E + "[37;1m" + "h`h" + R + "\n"
        a = a + E + "[37;1m" + "shhh" + E + "[35;1m" + "``.`" + E + "[37;1m" + "hhh" + E + "[34;1m" + "`/syyso++oyys/`" + E + "[37;1m" + "hhh" + E + "[33;1m" + "`+++-`" + E + "[37;1m" + "hh:h" + R + "\n"
        a = a + E + "[37;1m" + "d/hhhhhhhhhhhh" + E + "[34;1m" + "`-/osyso+-`" + E + "[37;1m" + "hhhhhhhhhhhh.h" + R + "\n"
        a = a + E + "[37;1m" + " d/hhhhhhhhhhhh" + E + "[32;1m" + "`/ossso/." + E + "[37;1m" + "hhhhhhhhhhhh.h" + R + "\n"
        a = a + E + "[37;1m" + "  do`hhhhhhhhh" + E + "[32;1m" + "`ossssssso." + E + "[37;1m" + "hhhhhhhhhh:h" + R + "\n"
        a = a + E + "[37;1m" + "    h/`hhhhhhh" + E + "[32;1m" + "-sssssssss:" + E + "[37;1m" + "hhhhhhhh-yd" + R + "\n"
        a = a + E + "[37;1m" + "      h+.hhhhhh" + E + "[32;1m" + "+sssssss+" + E + "[37;1m" + "hhhhhh`/yd" + R + "\n"
        a = a + E + "[37;1m" + "        dho:.hhh" + E + "[32;1m" + ".:+++/." + E + "[37;1m" + "hhh`-+yd" + R + "\n"
        a = a + E + "[37;1m" + "            ddhso+++++osyhd" + R + "\n"
        emit a
    }
    if startsWith(dn, "septor") {
        a = a + E + "[34;1m" + E + "[34;1m" + "ssssssssssssssssssssssssssssssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssssssssssssssssssssssssssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssssssssssssssssssssssssssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssssssssssssssssssssssssssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssssss" + E + "[37;1m" + ";okOOOOOOOOOOOOOOko;" + E + "[34;1m" + "ssssssssss" + R + "\n"
        a = a + E + "[34;1m" + "sssssssss" + E + "[37;1m" + "oNWWWWWWWWWWWWWWWWWWNo" + E + "[34;1m" + "sssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssss" + E + "[37;1m" + ":WWWWWWWWWWWWWWWWWWWWWW:" + E + "[34;1m" + "ssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssss" + E + "[37;1m" + "lWWWWWk" + E + "[34;1m" + "ssssssssss" + E + "[37;1m" + "lddddd:" + E + "[34;1m" + "ssssssss" + R + "\n"
        a = a + E + "[34;1m" + "ssssssss" + E + "[37;1m" + "cWWWWWNKKKKKKKKKKKKOx:" + E + "[34;1m" + "ssssssssss" + R + "\n"
        a = a + E + "[34;1m" + E + "[34;1m" + "yy" + E + "[34;1m" + "sssssss" + E + "[37;1m" + "OWWWWWWWWWWWWWWWWWWWWx" + E + "[34;1m" + "sssssss" + E + "[34;1m" + "yy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyy" + E + "[37;1m" + ":kKNNNNNNNNNNNNWWWWWW:" + E + "[34;1m" + "yyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + "sccccc;" + E + "[34;1m" + "yyyyyyyyyy" + E + "[37;1m" + "kWWWWW:" + E + "[34;1m" + "yyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + ":WWWWWWNNNNNNNNNNWWWWWW;" + E + "[34;1m" + "yyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyy" + E + "[37;1m" + ".dWWWWWWWWWWWWWWWWWWWNd" + E + "[34;1m" + "yyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyy" + E + "[37;1m" + "sdO0KKKKKKKKKKKK0Od;" + E + "[34;1m" + "yyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        a = a + E + "[34;1m" + "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" + R + "\n"
        emit a
    }
    if startsWith(dn, "serene") {
        a = a + E + "[36;1m" + E + "[36;1m" + "              __---''''''---__" + R + "\n"
        a = a + E + "[36;1m" + "          .                      ." + R + "\n"
        a = a + E + "[36;1m" + "        :                          :" + R + "\n"
        a = a + E + "[36;1m" + "      -                       _______----_-" + R + "\n"
        a = a + E + "[36;1m" + "     s               __----'''     __----" + R + "\n"
        a = a + E + "[36;1m" + " __h_            _-'           _-'     h" + R + "\n"
        a = a + E + "[36;1m" + " '-._''--.._    ;           _-'         y" + R + "\n"
        a = a + E + "[36;1m" + "  :  ''-._  '-._/        _-'             :" + R + "\n"
        a = a + E + "[36;1m" + "  y       ':_       _--''                y" + R + "\n"
        a = a + E + "[36;1m" + "  m    .--'' '-._.;'                     m" + R + "\n"
        a = a + E + "[36;1m" + "  m   :        :                         m" + R + "\n"
        a = a + E + "[36;1m" + "  y    '.._     '-__                     y" + R + "\n"
        a = a + E + "[36;1m" + "  :        '--._    '''----___           :" + R + "\n"
        a = a + E + "[36;1m" + "   y            '--._         ''-- _    y" + R + "\n"
        a = a + E + "[36;1m" + "    h                '--._          :  h" + R + "\n"
        a = a + E + "[36;1m" + "     s                  __';         vs" + R + "\n"
        a = a + E + "[36;1m" + "      -         __..--''             -" + R + "\n"
        a = a + E + "[36;1m" + "        :_..--''                   :" + R + "\n"
        a = a + E + "[36;1m" + "          .                     _ ." + R + "\n"
        a = a + E + "[36;1m" + "            `''---______---''-``" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_17(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "slitaz") {
        a = a + E + "[33;1m" + E + "[33;1m" + "        @    @(               @" + R + "\n"
        a = a + E + "[33;1m" + "      @@   @@                  @    @/" + R + "\n"
        a = a + E + "[33;1m" + "     @@   @@                   @@   @@" + R + "\n"
        a = a + E + "[33;1m" + "    @@  %@@                     @@   @@" + R + "\n"
        a = a + E + "[33;1m" + "   @@  %@@@       @@@@@.       @@@@  @@" + R + "\n"
        a = a + E + "[33;1m" + "  @@@    @@@@    @@@@@@@    &@@@    @@@" + R + "\n"
        a = a + E + "[33;1m" + "   @@@@@@@ %@@@@@@@@@@@@ &@@@% @@@@@@@/" + R + "\n"
        a = a + E + "[33;1m" + "       ,@@@@@@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[33;1m" + "  .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/" + R + "\n"
        a = a + E + "[33;1m" + "@@@@@@.  @@@@@@@@@@@@@@@@@@@@@  /@@@@@@" + R + "\n"
        a = a + E + "[33;1m" + "@@    @@@@@  @@@@@@@@@@@@,  @@@@@   @@@" + R + "\n"
        a = a + E + "[33;1m" + "@@ @@@@.    @@@@@@@@@@@@@%    #@@@@ @@." + R + "\n"
        a = a + E + "[33;1m" + "@@ ,@@      @@@@@@@@@@@@@      @@@  @@" + R + "\n"
        a = a + E + "[33;1m" + "@   @@.     @@@@@@@@@@@@@     @@@  *@" + R + "\n"
        a = a + E + "[33;1m" + "@    @@     @@@@@@@@@@@@      @@   @" + R + "\n"
        a = a + E + "[33;1m" + "      @      @@@@@@@@@.     #@" + R + "\n"
        a = a + E + "[33;1m" + "       @      ,@@@@@       @" + R + "\n"
        emit a
    }
    if startsWith(dn, "sparky") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "           .            `-:-`" + R + "\n"
        a = a + E + "[31;1m" + "          .o`       .-///-`" + R + "\n"
        a = a + E + "[31;1m" + "         `oo`    .:/++:." + R + "\n"
        a = a + E + "[31;1m" + "         os+`  -/+++:` ``.........```" + R + "\n"
        a = a + E + "[31;1m" + "        /ys+`./+++/-.-::::::----......``" + R + "\n"
        a = a + E + "[31;1m" + "       `syyo`++o+--::::-::/+++/-``" + R + "\n"
        a = a + E + "[31;1m" + "       -yyy+.+o+`:/:-:sdmmmmmmmmdy+-`" + R + "\n"
        a = a + E + "[31;1m" + "::-`   :yyy/-oo.-+/`ymho++++++oyhdmdy/`" + R + "\n"
        a = a + E + "[31;1m" + "`/yy+-`.syyo`+o..o--h..osyhhddhs+//osyy/`" + R + "\n"
        a = a + E + "[31;1m" + "  -ydhs+-oyy/.+o.-: ` `  :/::+ydhy+```-os-" + R + "\n"
        a = a + E + "[31;1m" + "   .sdddy::syo--/:.     `.:dy+-ohhho    ./:" + R + "\n"
        a = a + E + "[31;1m" + "     :yddds/:+oo+//:-`- /+ +hy+.shhy:     ``" + R + "\n"
        a = a + E + "[31;1m" + "      `:ydmmdysooooooo-.ss`/yss--oyyo" + R + "\n"
        a = a + E + "[31;1m" + "        `./ossyyyyo+:-/oo:.osso- .oys" + R + "\n"
        a = a + E + "[31;1m" + "       ``..-------::////.-oooo/   :so" + R + "\n"
        a = a + E + "[31;1m" + "    `...----::::::::--.`/oooo:    .o:" + R + "\n"
        a = a + E + "[31;1m" + "           ```````     ++o+:`     `:`" + R + "\n"
        a = a + E + "[31;1m" + "                     ./+/-`        `" + R + "\n"
        a = a + E + "[31;1m" + "                   `-:-." + R + "\n"
        a = a + E + "[31;1m" + "                   ``" + R + "\n"
        emit a
    }
    if startsWith(dn, "obarun") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                    ,;::::;" + R + "\n"
        a = a + E + "[36;1m" + "                ;cooolc;," + R + "\n"
        a = a + E + "[36;1m" + "             ,coool;" + R + "\n"
        a = a + E + "[36;1m" + "           ,loool," + R + "\n"
        a = a + E + "[36;1m" + "          loooo;" + R + "\n"
        a = a + E + "[36;1m" + "        :ooool" + R + "\n"
        a = a + E + "[36;1m" + "       cooooc            ,:ccc;" + R + "\n"
        a = a + E + "[36;1m" + "      looooc           :oooooool" + R + "\n"
        a = a + E + "[36;1m" + "     cooooo          ;oooooooooo," + R + "\n"
        a = a + E + "[36;1m" + "    :ooooo;         :ooooooooooo" + R + "\n"
        a = a + E + "[36;1m" + "    oooooo          oooooooooooc" + R + "\n"
        a = a + E + "[36;1m" + "   :oooooo         :ooooooooool" + R + "\n"
        a = a + E + "[36;1m" + "   loooooo         ;oooooooool" + R + "\n"
        a = a + E + "[36;1m" + "   looooooc        .coooooooc" + R + "\n"
        a = a + E + "[36;1m" + "   cooooooo:           ,;co;" + R + "\n"
        a = a + E + "[36;1m" + "   ,ooooooool;       ,:loc" + R + "\n"
        a = a + E + "[36;1m" + "    cooooooooooooloooooc" + R + "\n"
        a = a + E + "[36;1m" + "     ;ooooooooooooool;" + R + "\n"
        a = a + E + "[36;1m" + "       ;looooooolc;" + R + "\n"
        emit a
    }
    if startsWith(dn, "darwin") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                    c.'" + R + "\n"
        a = a + E + "[32;1m" + "                 ,xNMM." + R + "\n"
        a = a + E + "[32;1m" + "               .OMMMMo" + R + "\n"
        a = a + E + "[32;1m" + "               lMMM\"" + R + "\n"
        a = a + E + "[32;1m" + "     .;loddo:.  .olloddol;." + R + "\n"
        a = a + E + "[32;1m" + "   cKMMMMMMMMMMNWMMMMMMMMMM0:" + R + "\n"
        a = a + E + "[32;1m" + E + "[33;1m" + " .KMMMMMMMMMMMMMMMMMMMMMMMWd." + R + "\n"
        a = a + E + "[33;1m" + " XMMMMMMMMMMMMMMMMMMMMMMMX." + R + "\n"
        a = a + E + "[33;1m" + E + "[31;1m" + ";MMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + ":MMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + ".MMMMMMMMMMMMMMMMMMMMMMMMX." + R + "\n"
        a = a + E + "[31;1m" + " kMMMMMMMMMMMMMMMMMMMMMMMMWd." + R + "\n"
        a = a + E + "[31;1m" + " " + E + "[35;1m" + "'XMMMMMMMMMMMMMMMMMMMMMMMMMMk" + R + "\n"
        a = a + E + "[35;1m" + "  'XMMMMMMMMMMMMMMMMMMMMMMMMK." + R + "\n"
        a = a + E + "[35;1m" + "    " + E + "[34;1m" + "kMMMMMMMMMMMMMMMMMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "     ;KMMMMMMMWXXWMMMMMMMk." + R + "\n"
        a = a + E + "[34;1m" + "       \"cooc*\"    \"*coo'\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "alter") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                      %," + R + "\n"
        a = a + E + "[36;1m" + "                    ^WWWw" + R + "\n"
        a = a + E + "[36;1m" + "                   'wwwwww" + R + "\n"
        a = a + E + "[36;1m" + "                  !wwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "                 #`wwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "                @wwwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "               wwwwwwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "              wwwwwwwwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "             wwwwwwwwwwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "            wwwwwwwwwwwwwwwwwwww," + R + "\n"
        a = a + E + "[36;1m" + "           w~1i.wwwwwwwwwwwwwwwww," + R + "\n"
        a = a + E + "[36;1m" + "         3~:~1lli.wwwwwwwwwwwwwwww." + R + "\n"
        a = a + E + "[36;1m" + "        :~~:~?ttttzwwwwwwwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "       #<~:~~~~?llllltO-.wwwwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "      #~:~~:~:~~?ltlltlttO-.wwwwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "     @~:~~:~:~:~~(zttlltltlOda.wwwwwww" + R + "\n"
        a = a + E + "[36;1m" + "    @~:~~: ~:~~:~:(zltlltlO    a,wwwwww" + R + "\n"
        a = a + E + "[36;1m" + "   8~~:~~:~~~~:~~~~_1ltltu          ,www" + R + "\n"
        a = a + E + "[36;1m" + "  5~~:~~:~~:~~:~~:~~~_1ltq             N,," + R + "\n"
        a = a + E + "[36;1m" + " g~:~~:~~~:~~:~~:~:~~~~1q                N," + R + "\n"
        emit a
    }
    if startsWith(dn, "antix") {
        a = a + E + "[31;1m" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "                    \\" + R + "\n"
        a = a + E + "[31;1m" + "         , - ~ ^ ~ - \\        /" + R + "\n"
        a = a + E + "[31;1m" + "     , '              \\ ' ,  /" + R + "\n"
        a = a + E + "[31;1m" + "   ,                   \\   '/" + R + "\n"
        a = a + E + "[31;1m" + "  ,                     \\  / ," + R + "\n"
        a = a + E + "[31;1m" + " ,___,                   \\/   ," + R + "\n"
        a = a + E + "[31;1m" + " /   |   _  _  _|_ o     /\\   ," + R + "\n"
        a = a + E + "[31;1m" + "|,   |  / |/ |  |  |    /  \\  ," + R + "\n"
        a = a + E + "[31;1m" + " \\,_/\\_/  |  |_/|_/|_/_/    \\," + R + "\n"
        a = a + E + "[31;1m" + "   ,                  /     ,\\" + R + "\n"
        a = a + E + "[31;1m" + "     ,               /  , '   \\" + R + "\n"
        a = a + E + "[31;1m" + "      ' - , _ _ _ ,  '" + R + "\n"
        emit a
    }
    if startsWith(dn, "artix") {
        a = a + E + "[36;1m" + E + "[36;1m" + "                   '" + R + "\n"
        a = a + E + "[36;1m" + "                  'o'" + R + "\n"
        a = a + E + "[36;1m" + "                 'ooo'" + R + "\n"
        a = a + E + "[36;1m" + "                'ooxoo'" + R + "\n"
        a = a + E + "[36;1m" + "               'ooxxxoo'" + R + "\n"
        a = a + E + "[36;1m" + "              'oookkxxoo'" + R + "\n"
        a = a + E + "[36;1m" + "             'oiioxkkxxoo'" + R + "\n"
        a = a + E + "[36;1m" + "            ':;:iiiioxxxoo'" + R + "\n"
        a = a + E + "[36;1m" + "               `'.;::ioxxoo'" + R + "\n"
        a = a + E + "[36;1m" + "          '-.      `':;jiooo'" + R + "\n"
        a = a + E + "[36;1m" + "         'oooio-..     `'i:io'" + R + "\n"
        a = a + E + "[36;1m" + "        'ooooxxxxoio:,.   `'-;'" + R + "\n"
        a = a + E + "[36;1m" + "       'ooooxxxxxkkxoooIi:-.  `'" + R + "\n"
        a = a + E + "[36;1m" + "      'ooooxxxxxkkkkxoiiiiiji'" + R + "\n"
        a = a + E + "[36;1m" + "     'ooooxxxxxkxxoiiii:'`     .i'" + R + "\n"
        a = a + E + "[36;1m" + "    'ooooxxxxxoi:::'`       .;ioxo'" + R + "\n"
        a = a + E + "[36;1m" + "   'ooooxooi::'`         .:iiixkxxo'" + R + "\n"
        a = a + E + "[36;1m" + "  'ooooi:'`                `'';ioxxo'" + R + "\n"
        a = a + E + "[36;1m" + " 'i:'`                          '':io'" + R + "\n"
        a = a + E + "[36;1m" + "'`                                   `'" + R + "\n"
        emit a
    }
    if startsWith(dn, "bodhi") {
        a = a + E + "[37;1m" + E + "[37;1m" + "|           " + E + "[38;5;11m" + ",,mmKKKKKKKKWm,," + R + "\n"
        a = a + E + "[38;5;11m" + " " + E + "[37;1m" + "'      " + E + "[38;5;11m" + ",aKKP" + E + "[37;1m" + "LL**********|L*" + E + "[38;5;11m" + "TKp," + R + "\n"
        a = a + E + "[38;5;11m" + "   " + E + "[37;1m" + "t  " + E + "[38;5;11m" + "aKP" + E + "[37;1m" + "L**```          ```**L" + E + "[38;5;11m" + "*Kp" + R + "\n"
        a = a + E + "[38;5;11m" + "    IX" + E + "[37;1m" + "EL" + E + "[32;1m" + "L,wwww,              " + E + "[37;1m" + "``*||" + E + "[38;5;11m" + "Kp" + R + "\n"
        a = a + E + "[38;5;11m" + "  ,#P" + E + "[37;1m" + "L|" + E + "[32;1m" + "KKKpPP@IPPTKmw,          " + E + "[37;1m" + "`*||" + E + "[38;5;11m" + "K" + R + "\n"
        a = a + E + "[38;5;11m" + " ,K" + E + "[37;1m" + "LL*" + E + "[32;1m" + "{KKKKKKPPb$KPhpKKPKp        " + E + "[37;1m" + "`||" + E + "[38;5;11m" + "K" + R + "\n"
        a = a + E + "[38;5;11m" + " #" + E + "[37;1m" + "PL  " + E + "[32;1m" + "!KKKKKKPhKPPP$KKEhKKKKp      " + E + "[37;1m" + "`||" + E + "[38;5;11m" + "K" + R + "\n"
        a = a + E + "[38;5;11m" + "!H" + E + "[37;1m" + "L*   " + E + "[32;1m" + "1KKKKKKKphKbPKKKKKK$KKp      " + E + "[37;1m" + "`|I" + E + "[38;5;11m" + "W" + R + "\n"
        a = a + E + "[38;5;11m" + "$" + E + "[37;1m" + "bL     " + E + "[32;1m" + "KKKKKKKKBQKhKbKKKKKKKK       " + E + "[37;1m" + "|I" + E + "[38;5;11m" + "N" + R + "\n"
        a = a + E + "[38;5;11m" + "$" + E + "[37;1m" + "bL     " + E + "[32;1m" + "!KKKKKKKKKKNKKKKKKKPP`       " + E + "[37;1m" + "|I" + E + "[38;5;11m" + "b" + R + "\n"
        a = a + E + "[38;5;11m" + "TH" + E + "[37;1m" + "L*     " + E + "[32;1m" + "TKKKKKK##KKKN@KKKK^         " + E + "[37;1m" + "|I" + E + "[38;5;11m" + "M" + R + "\n"
        a = a + E + "[38;5;11m" + " K@" + E + "[37;1m" + "L      " + E + "[32;1m" + "*KKKKKKKKKKKEKE5          " + E + "[37;1m" + "||" + E + "[38;5;11m" + "K" + R + "\n"
        a = a + E + "[38;5;11m" + " `NL" + E + "[37;1m" + "L      " + E + "[32;1m" + "`KKKKKKKKKK\"```|L       " + E + "[37;1m" + "||" + E + "[38;5;11m" + "#P" + R + "\n"
        a = a + E + "[38;5;11m" + "  `K@" + E + "[37;1m" + "LL       " + E + "[32;1m" + "`\"**\"`        " + E + "[37;1m" + "'.   :||" + E + "[38;5;11m" + "#P" + R + "\n"
        a = a + E + "[38;5;11m" + "    Yp" + E + "[37;1m" + "LL                      " + E + "[37;1m" + "' |L" + E + "[38;5;11m" + "$M`" + R + "\n"
        a = a + E + "[38;5;11m" + "     `Tp" + E + "[37;1m" + "pLL,                ,|||" + E + "[38;5;11m" + "p'L" + R + "\n"
        a = a + E + "[38;5;11m" + "        \"Kpp" + E + "[37;1m" + "LL++,.,    ,,|||$" + E + "[38;5;11m" + "#K*   " + E + "[37;1m" + "'." + R + "\n"
        a = a + E + "[37;1m" + "           " + E + "[38;5;11m" + "`\"MKWpppppppp#KM\"`        " + E + "[37;1m" + "`h," + R + "\n"
        emit a
    }
    if startsWith(dn, "carbs") {
        a = a + E + "[34;1m" + E + "[35;1m" + "             .........." + R + "\n"
        a = a + E + "[35;1m" + "          ..,;:ccccccc:;'.." + R + "\n"
        a = a + E + "[35;1m" + "       ..,clllc:;;;;;:cllc,." + R + "\n"
        a = a + E + "[35;1m" + "      .,cllc,...     ..';;'." + R + "\n"
        a = a + E + "[35;1m" + "     .;lol;..           .." + R + "\n"
        a = a + E + "[35;1m" + "    .,lol;." + R + "\n"
        a = a + E + "[35;1m" + "    .coo:." + R + "\n"
        a = a + E + "[35;1m" + "   .'lol,." + R + "\n"
        a = a + E + "[35;1m" + "   .,lol,." + R + "\n"
        a = a + E + "[35;1m" + "   .,lol,." + R + "\n"
        a = a + E + "[35;1m" + "    'col;." + R + "\n"
        a = a + E + "[35;1m" + "    .:ooc'." + R + "\n"
        a = a + E + "[35;1m" + "    .'col:." + R + "\n"
        a = a + E + "[35;1m" + "     .'cllc'..          .''." + R + "\n"
        a = a + E + "[35;1m" + "      ..:lolc,'.......',cll,." + R + "\n"
        a = a + E + "[35;1m" + "        ..;cllllccccclllc;'." + R + "\n"
        a = a + E + "[35;1m" + "          ...',;;;;;;,,..." + R + "\n"
        a = a + E + "[35;1m" + "                ....." + R + "\n"
        emit a
    }
    if startsWith(dn, "celos") {
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "                     .,cmmmmmmmmmmmc,." + R + "\n"
        a = a + E + "[35;1m" + "                .,cmMMMMMMMMMMMMMMMMMMMMmc." + R + "\n"
        a = a + E + "[35;1m" + "             .cMMMMMMMMMMMMMMMMMMMMMMMMMMMmc." + R + "\n"
        a = a + E + "[35;1m" + "           .cMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMc." + R + "\n"
        a = a + E + "[35;1m" + "         ,:MMM " + E + "[30;1m" + "####################################" + E + "[35;1m" + R + "\n"
        a = a + E + "[35;1m" + "        cMMMMMMmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmc." + R + "\n"
        a = a + E + "[35;1m" + "       .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM." + R + "\n"
        a = a + E + "[35;1m" + "      .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMc" + R + "\n"
        a = a + E + "[35;1m" + "      \"******************************MMMMMMMMMMMMMc:" + R + "\n"
        a = a + E + "[35;1m" + E + "[30;1m" + "#################################### " + E + "[35;1m" + "MMMMMMMMMMMMMc" + R + "\n"
        a = a + E + "[35;1m" + "      \"MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM:" + R + "\n"
        a = a + E + "[35;1m" + "       \"MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM\"" + R + "\n"
        a = a + E + "[35;1m" + "       'MMMMMMMMM*******************************:" + R + "\n"
        a = a + E + "[35;1m" + "        \\\"MMMMMM " + E + "[30;1m" + "#####################################" + R + "\n"
        a = a + E + "[30;1m" + "         " + E + "[35;1m" + "`:MMMMMMmmmmmmmmmmmmmmmmmmmmmmmmmmmmm;" + R + "\n"
        a = a + E + "[35;1m" + "           `\"MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM\"" + R + "\n"
        a = a + E + "[35;1m" + "             `\":MMMMMMMMMMMMMMMMMMMMMMMMM;'" + R + "\n"
        a = a + E + "[35;1m" + "                `\":MMMMMMMMMMMMMMMMMMM:\"" + R + "\n"
        a = a + E + "[35;1m" + "                     \"************\"" + R + "\n"
        a = a + E + "[35;1m" + R + "\n"
        a = a + E + "[35;1m" + R + "\n"
        a = a + E + "[35;1m" + R + "\n"
        a = a + E + "[35;1m" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_18(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "chrom") {
        a = a + E + "[32;1m" + E + "[31;1m" + "            .,:loool:,." + R + "\n"
        a = a + E + "[31;1m" + "        .,coooooooooooooc,." + R + "\n"
        a = a + E + "[31;1m" + "     .,lllllllllllllllllllll,." + R + "\n"
        a = a + E + "[31;1m" + "    ;ccccccccccccccccccccccccc;" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "  '" + E + "[31;1m" + "ccccccccccccccccccccccccccccc." + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + " ,oo" + E + "[31;1m" + "c::::::::okO" + E + "[37;1m" + "000" + E + "[33;1m" + "0OOkkkkkkkkkkk:" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + ".ooool" + E + "[31;1m" + ";;;;:x" + E + "[37;1m" + "K0" + E + "[34;1m" + "kxxxxxk" + E + "[37;1m" + "0X" + E + "[33;1m" + "K0000000000." + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + ":oooool" + E + "[31;1m" + ";,;O" + E + "[37;1m" + "K" + E + "[34;1m" + "ddddddddddd" + E + "[37;1m" + "KX" + E + "[33;1m" + "000000000d" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "lllllool" + E + "[31;1m" + ";l" + E + "[37;1m" + "N" + E + "[34;1m" + "dllllllllllld" + E + "[37;1m" + "N" + E + "[33;1m" + "K000000000" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "lllllllll" + E + "[31;1m" + "o" + E + "[37;1m" + "M" + E + "[34;1m" + "dccccccccccco" + E + "[37;1m" + "W" + E + "[33;1m" + "K000000000" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + ";cllllllllX" + E + "[37;1m" + "X" + E + "[34;1m" + "c:::::::::c" + E + "[37;1m" + "0X" + E + "[33;1m" + "000000000d" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + ".ccccllllllO" + E + "[37;1m" + "Nk" + E + "[34;1m" + "c;,,,;cx" + E + "[37;1m" + "KK" + E + "[33;1m" + "0000000000." + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + " .cccccclllllxOO" + E + "[37;1m" + "OOO" + E + "[32;1m" + "Okx" + E + "[33;1m" + "O0000000000;" + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "  .:ccccccccllllllllo" + E + "[33;1m" + "O0000000OOO," + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "    ,:ccccccccclllcd" + E + "[33;1m" + "0000OOOOOOl." + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "      '::ccccccccc" + E + "[33;1m" + "dOOOOOOOkx:." + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "        ..,::cccc" + E + "[33;1m" + "xOOOkkko;." + R + "\n"
        a = a + E + "[33;1m" + E + "[32;1m" + "            ..,:" + E + "[33;1m" + "dOkxl:." + R + "\n"
        emit a
    }
    if startsWith(dn, "feren") {
        a = a + E + "[34;1m" + E + "[34;1m" + " `----------`" + R + "\n"
        a = a + E + "[34;1m" + " :+ooooooooo+." + R + "\n"
        a = a + E + "[34;1m" + "-o+oooooooooo+-" + R + "\n"
        a = a + E + "[34;1m" + "..`/+++++++++++/...`````````````````" + R + "\n"
        a = a + E + "[34;1m" + "   .++++++++++++++++++++++++++/////-" + R + "\n"
        a = a + E + "[34;1m" + "    ++++++++++++++++++++++++++++++++//:`" + R + "\n"
        a = a + E + "[34;1m" + "    -++++++++++++++++++++++++++++++/-`" + R + "\n"
        a = a + E + "[34;1m" + "     ++++++++++++++++++++++++++++:." + R + "\n"
        a = a + E + "[34;1m" + "     -++++++++++++++++++++++++/." + R + "\n"
        a = a + E + "[34;1m" + "      +++++++++++++++++++++/-`" + R + "\n"
        a = a + E + "[34;1m" + "      -++++++++++++++++++//-`" + R + "\n"
        a = a + E + "[34;1m" + "        .:+++++++++++++//////-" + R + "\n"
        a = a + E + "[34;1m" + "           .:++++++++//////////-" + R + "\n"
        a = a + E + "[34;1m" + "             `-++++++---:::://///." + R + "\n"
        a = a + E + "[34;1m" + "           `.:///+++.             `" + R + "\n"
        a = a + E + "[34;1m" + "          `........." + R + "\n"
        emit a
    }
    if startsWith(dn, "gnome") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                               ,@@@@@@@@," + R + "\n"
        a = a + E + "[34;1m" + "                 @@@@@@      @@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "        ,@@.    @@@@@@@    *@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "       @@@@@%   @@@@@@(    @@@@@@@@@@@&" + R + "\n"
        a = a + E + "[34;1m" + "       @@@@@@    @@@@*     @@@@@@@@@#" + R + "\n"
        a = a + E + "[34;1m" + "@@@@*   @@@@,              *@@@@@%" + R + "\n"
        a = a + E + "[34;1m" + "@@@@@." + R + "\n"
        a = a + E + "[34;1m" + " @@@@#         @@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "         ,@@@@@@@@@@@@@@@@@@@@@@@," + R + "\n"
        a = a + E + "[34;1m" + "      ,@@@@@@@@@@@@@@@@@@@@@@@@@@&" + R + "\n"
        a = a + E + "[34;1m" + "    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "    @@@@@@@@@@@@@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "   @@@@@@@@@@@@@@@@@@@@@@@@(" + R + "\n"
        a = a + E + "[34;1m" + "   @@@@@@@@@@@@@@@@@@@@%" + R + "\n"
        a = a + E + "[34;1m" + "    @@@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "     @@@@@@@@@@@@*        @@@@@@@@/" + R + "\n"
        a = a + E + "[34;1m" + "      &@@@@@@@@@@        @@@@@@@@@*" + R + "\n"
        a = a + E + "[34;1m" + "        @@@@@@@@@@@,    @@@@@@@@@*" + R + "\n"
        a = a + E + "[34;1m" + "          ,@@@@@@@@@@@@@@@@@@@@&" + R + "\n"
        a = a + E + "[34;1m" + "              &@@@@@@@@@@@@@@" + R + "\n"
        a = a + E + "[34;1m" + "                     ..." + R + "\n"
        emit a
    }
    if startsWith(dn, "haiku") {
        a = a + E + "[31;1m" + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM" + E + "[32;1m" + "       .ciO| /YMMMMM*\"" + R + "\n"
        a = a + E + "[32;1m" + E + "[37;1m" + "           MMMM" + E + "[32;1m" + "   .cOMMMMM|/MMMMM/`" + R + "\n"
        a = a + E + "[32;1m" + " ,         ,iMM|/MMMMMMMMMMMMMMM*" + R + "\n"
        a = a + E + "[32;1m" + "  `*.__,-cMMMMMMMMMMMMMMMMM/`" + E + "[37;1m" + ".MMM" + R + "\n"
        a = a + E + "[37;1m" + "           MM" + E + "[32;1m" + "MMMMMMM/`:MMM/  " + E + "[37;1m" + "MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           MMMM              MMMM" + R + "\n"
        a = a + E + "[37;1m" + "           \"\"\"\"              \"\"\"\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "linux") {
        a = a + E + "[37;1m" + E + "[38;5;8m" + "        #####" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "       #######" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "       ##" + E + "[37;1m" + "O" + E + "[38;5;8m" + "#" + E + "[37;1m" + "O" + E + "[38;5;8m" + "##" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "       #" + E + "[33;1m" + "#####" + E + "[38;5;8m" + "#" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "     ##" + E + "[37;1m" + "##" + E + "[33;1m" + "###" + E + "[37;1m" + "##" + E + "[38;5;8m" + "##" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "    #" + E + "[37;1m" + "##########" + E + "[38;5;8m" + "##" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "   #" + E + "[37;1m" + "############" + E + "[38;5;8m" + "##" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "   #" + E + "[37;1m" + "############" + E + "[38;5;8m" + "###" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[33;1m" + "  ##" + E + "[38;5;8m" + "#" + E + "[37;1m" + "###########" + E + "[38;5;8m" + "##" + E + "[33;1m" + "#" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "######" + E + "[38;5;8m" + "#" + E + "[37;1m" + "#######" + E + "[38;5;8m" + "#" + E + "[33;1m" + "######" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "#######" + E + "[38;5;8m" + "#" + E + "[37;1m" + "#####" + E + "[38;5;8m" + "#" + E + "[33;1m" + "#######" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "  #####" + E + "[38;5;8m" + "#######" + E + "[33;1m" + "#####" + R + "\n"
        emit a
    }
    if startsWith(dn, "lunar") {
        a = a + E + "[34;1m" + E + "[34;1m" + "`-.                                 `-." + R + "\n"
        a = a + E + "[34;1m" + "  -ohys/-`                    `:+shy/`" + R + "\n"
        a = a + E + "[34;1m" + "     -omNNdyo/`          :+shmNNy/`" + R + "\n"
        a = a + E + "[34;1m" + "             " + E + "[33;1m" + "      -" + R + "\n"
        a = a + E + "[33;1m" + "                 /mMmo" + R + "\n"
        a = a + E + "[33;1m" + "                 hMMMN`" + R + "\n"
        a = a + E + "[33;1m" + "                 .NMMs" + R + "\n"
        a = a + E + "[33;1m" + "    " + E + "[34;1m" + "  -:+oooo+//: " + E + "[33;1m" + "/MN" + E + "[34;1m" + ". -///oooo+/-`" + R + "\n"
        a = a + E + "[34;1m" + "     /:.`          " + E + "[33;1m" + "/" + E + "[34;1m" + "           `.:/`" + R + "\n"
        a = a + E + "[34;1m" + E + "[33;1m" + "          __" + R + "\n"
        a = a + E + "[33;1m" + "         |  |   _ _ ___ ___ ___" + R + "\n"
        a = a + E + "[33;1m" + "         |  |__| | |   | .'|  _|" + R + "\n"
        a = a + E + "[33;1m" + "         |_____|___|_|_|__,|_|" + R + "\n"
        emit a
    }
    if startsWith(dn, "minix") {
        a = a + E + "[31;1m" + E + "[37;1m" + "   -sdhyo+:-`                -/syymm:" + R + "\n"
        a = a + E + "[37;1m" + "   sdyooymmNNy.     ``    .smNmmdysNd" + R + "\n"
        a = a + E + "[37;1m" + "   odyoso+syNNmysoyhhdhsoomNmm+/osdm/" + R + "\n"
        a = a + E + "[37;1m" + "    :hhy+-/syNNmddhddddddmNMNo:sdNd:" + R + "\n"
        a = a + E + "[37;1m" + "     `smNNdNmmNmddddddddddmmmmmmmy`" + R + "\n"
        a = a + E + "[37;1m" + "   `ohhhhdddddmmNNdmddNmNNmdddddmdh-" + R + "\n"
        a = a + E + "[37;1m" + "   odNNNmdyo/:/-/hNddNy-`..-+ydNNNmd:" + R + "\n"
        a = a + E + "[37;1m" + " `+mNho:`   smmd/ sNNh :dmms`   -+ymmo." + R + "\n"
        a = a + E + "[37;1m" + "-od/       -m" + E + "[31;1m" + "mm" + E + "[37;1m" + "mo -NN+ +m" + E + "[31;1m" + "mm" + E + "[37;1m" + "m-       yms:" + R + "\n"
        a = a + E + "[37;1m" + "+sms -.`    :so:  .NN+  :os/     .-`mNh:" + R + "\n"
        a = a + E + "[37;1m" + ".-hyh+:////-     -sNNd:`    .--://ohNs-" + R + "\n"
        a = a + E + "[37;1m" + " `:hNNNNNNNMMd/sNMmhsdMMh/ymmNNNmmNNy/" + R + "\n"
        a = a + E + "[37;1m" + "  -+sNNNNMMNNNsmNMo: :NNmymNNNNMMMms:" + R + "\n"
        a = a + E + "[37;1m" + "    //oydNMMMMydMMNysNMMmsMMMMMNyo/`" + R + "\n"
        a = a + E + "[37;1m" + "       ../-yNMMy--/::/-.sMMmos+.`" + R + "\n"
        a = a + E + "[37;1m" + "           -+oyhNsooo+omy/```" + R + "\n"
        a = a + E + "[37;1m" + "              `::ohdmds-`" + R + "\n"
        emit a
    }
    if startsWith(dn, "namib") {
        a = a + E + "[31;1m" + E + "[31;1m" + "          .:+shysyhhhhysyhs+:." + R + "\n"
        a = a + E + "[31;1m" + "       -/yyys              syyy/-" + R + "\n"
        a = a + E + "[31;1m" + "     -shy                      yhs-" + R + "\n"
        a = a + E + "[31;1m" + "   -yhs                          shy-" + R + "\n"
        a = a + E + "[31;1m" + "  +hy                              yh+" + R + "\n"
        a = a + E + "[31;1m" + " +ds                                sd+" + R + "\n"
        a = a + E + "[31;1m" + "/ys                  so              sy/" + R + "\n"
        a = a + E + "[31;1m" + "sh                 smMMNdyo           hs" + R + "\n"
        a = a + E + "[31;1m" + "yo               ymMMMMNNMMNho        oy" + R + "\n"
        a = a + E + "[31;1m" + "N             ydMMMNNMMMMMMMMMmy       N" + R + "\n"
        a = a + E + "[31;1m" + "N         shmMMMMNNMMMMMMMMMMMMMNy     N" + R + "\n"
        a = a + E + "[31;1m" + "yo  ooshmNMMMNNNNMMMMMMMMMMMMMMMMMms  oy" + R + "\n"
        a = a + E + "[31;1m" + "sd yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy ds" + R + "\n"
        a = a + E + "[31;1m" + "/ys                                  sy/" + R + "\n"
        a = a + E + "[31;1m" + " +ds                                sd+" + R + "\n"
        a = a + E + "[31;1m" + "  +hy                              yh+" + R + "\n"
        a = a + E + "[31;1m" + "   -yhs                          shy-" + R + "\n"
        a = a + E + "[31;1m" + "     -shy                      yhs-" + R + "\n"
        a = a + E + "[31;1m" + "       -/yyys              syyy/-" + R + "\n"
        a = a + E + "[31;1m" + "          .:+shysyhyhhysyhs+:." + R + "\n"
        emit a
    }
    if startsWith(dn, "nixos") {
        a = a + E + "[34;1m" + E + "[34;1m" + "          ▗▄▄▄       " + E + "[36;1m" + "▗▄▄▄▄    ▄▄▄▖" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "          ▜███▙       " + E + "[36;1m" + "▜███▙  ▟███▛" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "           ▜███▙       " + E + "[36;1m" + "▜███▙▟███▛" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "            ▜███▙       " + E + "[36;1m" + "▜██████▛" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "     ▟█████████████████▙ " + E + "[36;1m" + "▜████▛     " + E + "[34;1m" + "▟▙" + R + "\n"
        a = a + E + "[34;1m" + E + "[34;1m" + "    ▟███████████████████▙ " + E + "[36;1m" + "▜███▙    " + E + "[34;1m" + "▟██▙" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "           ▄▄▄▄▖           ▜███▙  " + E + "[34;1m" + "▟███▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "          ▟███▛             ▜██▛ " + E + "[34;1m" + "▟███▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "         ▟███▛               ▜▛ " + E + "[34;1m" + "▟███▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "▟███████████▛                  " + E + "[34;1m" + "▟██████████▙" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "▜██████████▛                  " + E + "[34;1m" + "▟███████████▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "      ▟███▛ " + E + "[34;1m" + "▟▙               ▟███▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "     ▟███▛ " + E + "[34;1m" + "▟██▙             ▟███▛" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "    ▟███▛  " + E + "[34;1m" + "▜███▙           ▝▀▀▀▀" + R + "\n"
        a = a + E + "[34;1m" + E + "[36;1m" + "    ▜██▛    " + E + "[34;1m" + "▜███▙ " + E + "[36;1m" + "▜██████████████████▛" + R + "\n"
        a = a + E + "[36;1m" + E + "[36;1m" + "     ▜▛     " + E + "[34;1m" + "▟████▙ " + E + "[36;1m" + "▜████████████████▛" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "           ▟██████▙       " + E + "[36;1m" + "▜███▙" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "          ▟███▛▜███▙       " + E + "[36;1m" + "▜███▙" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "         ▟███▛  ▜███▙       " + E + "[36;1m" + "▜███▙" + R + "\n"
        a = a + E + "[36;1m" + E + "[34;1m" + "         ▝▀▀▀    ▀▀▀▀▘       " + E + "[36;1m" + "▀▀▀▘" + R + "\n"
        emit a
    }
    if startsWith(dn, "nutyx") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                                      ." + R + "\n"
        a = a + E + "[34;1m" + "                                    ." + R + "\n"
        a = a + E + "[34;1m" + "                                 ..." + R + "\n"
        a = a + E + "[34;1m" + "                               ..." + R + "\n"
        a = a + E + "[34;1m" + "            ....     .........--." + R + "\n"
        a = a + E + "[34;1m" + "       ..-++-----....--++++++---." + R + "\n"
        a = a + E + "[34;1m" + "    .-++++++-.   .-++++++++++++-----.." + R + "\n"
        a = a + E + "[34;1m" + "  .--...  .++..-+++--.....-++++++++++--.." + R + "\n"
        a = a + E + "[34;1m" + " .     .-+-. .**-            ....  ..-+----.." + R + "\n"
        a = a + E + "[34;1m" + "     .+++.  .*+.         +            -++-----." + R + "\n"
        a = a + E + "[34;1m" + "   .+++++-  ++.         .*+.     .....-+++-----." + R + "\n"
        a = a + E + "[34;1m" + "  -+++-++. .+.          .-+***++***++--++++.  ." + R + "\n"
        a = a + E + "[34;1m" + " -+-. --   -.          -*- ......        ..--." + R + "\n"
        a = a + E + "[34;1m" + ".-. .+-    .          -+." + R + "\n"
        a = a + E + "[34;1m" + ".  .+-                +." + R + "\n"
        a = a + E + "[34;1m" + "   --                 --" + R + "\n"
        a = a + E + "[34;1m" + "  -+----.              .-" + R + "\n"
        a = a + E + "[34;1m" + "  -++-.+.                ." + R + "\n"
        a = a + E + "[34;1m" + " .++. --" + R + "\n"
        a = a + E + "[34;1m" + "  +.  ----." + R + "\n"
        a = a + E + "[34;1m" + "  .  .+. .." + R + "\n"
        a = a + E + "[34;1m" + "      -  ." + R + "\n"
        a = a + E + "[34;1m" + "      ." + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_19(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "qubes") {
        a = a + E + "[34;1m" + E + "[34;1m" + "               `..--..`" + R + "\n"
        a = a + E + "[34;1m" + "            `.----------.`" + R + "\n"
        a = a + E + "[34;1m" + "        `..----------------..`" + R + "\n"
        a = a + E + "[34;1m" + "     `.------------------------.``" + R + "\n"
        a = a + E + "[34;1m" + " `..-------------....-------------..`" + R + "\n"
        a = a + E + "[34;1m" + ".::----------..``    ``..----------:+:" + R + "\n"
        a = a + E + "[34;1m" + ":////:----..`            `..---:/ossso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:`                  `/osssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:                    /ssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:                    /ssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:                    /ssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:                    /ssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////:                    /ssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":////////-`                .:sssssssso" + R + "\n"
        a = a + E + "[34;1m" + ":///////////-.`        `-/osssssssssso" + R + "\n"
        a = a + E + "[34;1m" + "`//////////////:-```.:+ssssssssssssso-" + R + "\n"
        a = a + E + "[34;1m" + "  .-://////////////sssssssssssssso/-`" + R + "\n"
        a = a + E + "[34;1m" + "     `.:///////////sssssssssssssso:." + R + "\n"
        a = a + E + "[34;1m" + "         .-:///////ssssssssssssssssss/`" + R + "\n"
        a = a + E + "[34;1m" + "            `.:////ssss+/+ssssssssssss." + R + "\n"
        a = a + E + "[34;1m" + "                `--//-    `-/osssso/." + R + "\n"
        emit a
    }
    if startsWith(dn, "qubyt") {
        a = a + E + "[34;1m" + E + "[34;1m" + "    ########################" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "    ########################" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo                  " + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo           " + E + "[34;1m" + "##" + E + "[30;1m" + "o    " + E + "[35;1m" + "((((" + E + "[30;1m" + "ooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo          o" + E + "[35;1m" + "((" + E + "[34;1m" + "###   " + E + "[30;1m" + "oooooo" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo           oo" + E + "[35;1m" + "((" + E + "[34;1m" + "###" + E + "[30;1m" + "o" + R + "\n"
        a = a + E + "[30;1m" + E + "[34;1m" + "###" + E + "[35;1m" + "(" + E + "[30;1m" + "ooo             ooo" + E + "[35;1m" + "((" + E + "[34;1m" + "###" + R + "\n"
        a = a + E + "[34;1m" + E + "[34;1m" + "################" + E + "[35;1m" + "(" + E + "[30;1m" + "oo    oo" + E + "[35;1m" + "((((" + E + "[30;1m" + "o" + R + "\n"
        a = a + E + "[30;1m" + E + "[35;1m" + "(((((((((((((((((" + E + "[30;1m" + "ooo     ooooo" + R + "\n"
        a = a + E + "[30;1m" + "  oooooooooooooooooo        o" + R + "\n"
        emit a
    }
    if startsWith(dn, "radix") {
        a = a + E + "[31;1m" + E + "[32;1m" + "                .:oyhdmNo" + R + "\n"
        a = a + E + "[32;1m" + "             `/yhyoosdms`" + R + "\n"
        a = a + E + "[32;1m" + "            -o+/ohmmho-" + R + "\n"
        a = a + E + "[32;1m" + "           ..`.:/:-`" + R + "\n"
        a = a + E + "[32;1m" + "     `.--:::-.``" + E + "[31;1m" + R + "\n"
        a = a + E + "[31;1m" + "  .+ydNMMMMMMNmhs:`" + R + "\n"
        a = a + E + "[31;1m" + "`omMMMMMMMMMMMMMMNh-" + R + "\n"
        a = a + E + "[31;1m" + "oNMMMNmddhhyyhhhddmy." + R + "\n"
        a = a + E + "[31;1m" + "mMMMMNmmddhhysoo+/:-`" + R + "\n"
        a = a + E + "[31;1m" + "yMMMMMMMMMMMMMMMMNNh." + R + "\n"
        a = a + E + "[31;1m" + "-dmmmmmNNMMMMMMMMMMs`" + R + "\n"
        a = a + E + "[31;1m" + " -+oossyhmMMMMMMMMd-" + R + "\n"
        a = a + E + "[31;1m" + " `sNMMMMMMMMMMMMMm:" + R + "\n"
        a = a + E + "[31;1m" + "  `yMMMMMMNmdhhhh:" + R + "\n"
        a = a + E + "[31;1m" + "   `sNMMMMMNmmho." + R + "\n"
        a = a + E + "[31;1m" + "    `+mMMMMMMMy." + R + "\n"
        a = a + E + "[31;1m" + "      .yNMMMm+`" + R + "\n"
        a = a + E + "[31;1m" + "       `:yd+." + R + "\n"
        emit a
    }
    if startsWith(dn, "rocky") {
        a = a + E + "[38;5;35m" + E + "[38;5;35m" + "          __wgliliiligw_," + R + "\n"
        a = a + E + "[38;5;35m" + "       _williiiiiiliilililw," + R + "\n"
        a = a + E + "[38;5;35m" + "     _%iiiiiilililiiiiiiiiiii_" + R + "\n"
        a = a + E + "[38;5;35m" + "   .Qliiiililiiiiiiililililiilm." + R + "\n"
        a = a + E + "[38;5;35m" + "  _iiiiiliiiiiililiiiiiiiiiiliil," + R + "\n"
        a = a + E + "[38;5;35m" + " .lililiiilililiiiilililililiiiii," + R + "\n"
        a = a + E + "[38;5;35m" + "_liiiiiiliiiiiiiliiiiiF{iiiiiilili," + R + "\n"
        a = a + E + "[38;5;35m" + "jliililiiilililiiili@`  ~ililiiiiiL" + R + "\n"
        a = a + E + "[38;5;35m" + "iiiliiiiliiiiiiili>`      ~liililii" + R + "\n"
        a = a + E + "[38;5;35m" + "liliiiliiilililii`         -9liiiil" + R + "\n"
        a = a + E + "[38;5;35m" + "iiiiiliiliiiiii~             \"4lili" + R + "\n"
        a = a + E + "[38;5;35m" + "4ililiiiiilil~|      -w,       )4lf" + R + "\n"
        a = a + E + "[38;5;35m" + "-liiiiililiF'       _liig,       )'" + R + "\n"
        a = a + E + "[38;5;35m" + " )iiiliii@`       _QIililig," + R + "\n"
        a = a + E + "[38;5;35m" + "  )iiii>`       .Qliliiiililw" + R + "\n"
        a = a + E + "[38;5;35m" + "   )<>~       .mliiiiiliiiiiil," + R + "\n"
        a = a + E + "[38;5;35m" + "            _gllilililiililii~" + R + "\n"
        a = a + E + "[38;5;35m" + "           giliiiiiiiiiiiiT`" + R + "\n"
        a = a + E + "[38;5;35m" + "          -^~$ililili@~~'" + R + "\n"
        emit a
    }
    if startsWith(dn, "solus") {
        a = a + E + "[34;1m" + E + "[37;1m" + "            -```````````" + R + "\n"
        a = a + E + "[37;1m" + "          `-+/------------.`" + R + "\n"
        a = a + E + "[37;1m" + "       .---:mNo---------------." + R + "\n"
        a = a + E + "[37;1m" + "     .-----yMMMy:---------------." + R + "\n"
        a = a + E + "[37;1m" + "   `------oMMMMMm/----------------`" + R + "\n"
        a = a + E + "[37;1m" + "  .------/MMMMMMMN+----------------." + R + "\n"
        a = a + E + "[37;1m" + " .------/NMMMMMMMMm-+/--------------." + R + "\n"
        a = a + E + "[37;1m" + "`------/NMMMMMMMMMN-:mh/-------------`" + R + "\n"
        a = a + E + "[37;1m" + ".-----/NMMMMMMMMMMM:-+MMd//oso/:-----." + R + "\n"
        a = a + E + "[37;1m" + "-----/NMMMMMMMMMMMM+--mMMMh::smMmyo:--" + R + "\n"
        a = a + E + "[37;1m" + "----+NMMMMMMMMMMMMMo--yMMMMNo-:yMMMMd/." + R + "\n"
        a = a + E + "[37;1m" + ".--oMMMMMMMMMMMMMMMy--yMMMMMMh:-yMMMy-`" + R + "\n"
        a = a + E + "[37;1m" + "`-sMMMMMMMMMMMMMMMMh--dMMMMMMMd:/Ny+y." + R + "\n"
        a = a + E + "[37;1m" + "`-/+osyhhdmmNNMMMMMm-/MMMMMMMmh+/ohm+" + R + "\n"
        a = a + E + "[37;1m" + "  .------------:://+-/++++++" + E + "[34;1m" + "oshddys:" + R + "\n"
        a = a + E + "[34;1m" + "   -hhhhyyyyyyyyyyyhhhhddddhysssso-" + R + "\n"
        a = a + E + "[34;1m" + "    `:ossssssyysssssssssssssssso:`" + R + "\n"
        a = a + E + "[34;1m" + "      `:+ssssssssssssssssssss+-" + R + "\n"
        a = a + E + "[34;1m" + "         `-/+ssssssssssso+/-`" + R + "\n"
        a = a + E + "[34;1m" + "              `.-----..`" + R + "\n"
        emit a
    }
    if startsWith(dn, "tails") {
        a = a + E + "[35;1m" + E + "[35;1m" + "      ``" + R + "\n"
        a = a + E + "[35;1m" + "  ./yhNh" + R + "\n"
        a = a + E + "[35;1m" + "syy/Nshh         `:o/" + R + "\n"
        a = a + E + "[35;1m" + "N:dsNshh  █   `ohNMMd" + R + "\n"
        a = a + E + "[35;1m" + "N-/+Nshh      `yMMMMd" + R + "\n"
        a = a + E + "[35;1m" + "N-yhMshh       yMMMMd" + R + "\n"
        a = a + E + "[35;1m" + "N-s:hshh  █    yMMMMd so//." + R + "\n"
        a = a + E + "[35;1m" + "N-oyNsyh       yMMMMd d  Mms." + R + "\n"
        a = a + E + "[35;1m" + "N:hohhhd:.     yMMMMd  syMMM+" + R + "\n"
        a = a + E + "[35;1m" + "Nsyh+-..+y+-   yMMMMd   :mMM+" + R + "\n"
        a = a + E + "[35;1m" + "+hy-      -ss/`yMMMM     `+d+" + R + "\n"
        a = a + E + "[35;1m" + "  :sy/.     ./yNMMMMm      ``" + R + "\n"
        a = a + E + "[35;1m" + "    .+ys- `:+hNMMMMMMy/`" + R + "\n"
        a = a + E + "[35;1m" + "      `hNmmMMMMMMMMMMMMdo." + R + "\n"
        a = a + E + "[35;1m" + "       dMMMMMMMMMMMMMMMMMNh:" + R + "\n"
        a = a + E + "[35;1m" + "       +hMMMMMMMMMMMMMMMMMmy." + R + "\n"
        a = a + E + "[35;1m" + "         -oNMMMMMMMMMMmy+.`" + R + "\n"
        a = a + E + "[35;1m" + "           `:yNMMMds/.`" + R + "\n"
        a = a + E + "[35;1m" + "              .//`" + R + "\n"
        emit a
    }
    if startsWith(dn, "venom") {
        a = a + E + "[38;5;8m" + E + "[38;5;8m" + "   :::::::          :::::::" + R + "\n"
        a = a + E + "[38;5;8m" + "   mMMMMMMm        dMMMMMMm" + R + "\n"
        a = a + E + "[38;5;8m" + "   /MMMMMMMo      +MMMMMMM/" + R + "\n"
        a = a + E + "[38;5;8m" + "    yMMMMMMN      mMMMMMMy" + R + "\n"
        a = a + E + "[38;5;8m" + "     NMMMMMMs    oMMMMMMm" + R + "\n"
        a = a + E + "[38;5;8m" + "     +MMMMMMN:   NMMMMMM+" + R + "\n"
        a = a + E + "[38;5;8m" + "      hMMMMMMy  sMMMMMMy" + R + "\n"
        a = a + E + "[38;5;8m" + "      :NMMMMMM::NMMMMMN:" + R + "\n"
        a = a + E + "[38;5;8m" + "       oMMMMMMyyMMMMMM+" + R + "\n"
        a = a + E + "[38;5;8m" + "        dMMMMMMMMMMMMh" + R + "\n"
        a = a + E + "[38;5;8m" + "        /MMMMMMMMMMMN:" + R + "\n"
        a = a + E + "[38;5;8m" + "         sMMMMMMMMMMo" + R + "\n"
        a = a + E + "[38;5;8m" + "          mMMMMMMMMd" + R + "\n"
        a = a + E + "[38;5;8m" + "          +MMMMMMMN:" + R + "\n"
        a = a + E + "[38;5;8m" + "            ::::::" + R + "\n"
        emit a
    }
    if startsWith(dn, "zorin") {
        a = a + E + "[34;1m" + E + "[34;1m" + "        `osssssssssssssssssssso`" + R + "\n"
        a = a + E + "[34;1m" + "       .osssssssssssssssssssssso." + R + "\n"
        a = a + E + "[34;1m" + "      .+oooooooooooooooooooooooo+." + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "  `::::::::::::::::::::::.         .:`" + R + "\n"
        a = a + E + "[34;1m" + " `+ssssssssssssssssss+:.`     `.:+ssso`" + R + "\n"
        a = a + E + "[34;1m" + ".ossssssssssssssso/.       `-+ossssssso." + R + "\n"
        a = a + E + "[34;1m" + "ssssssssssssso/-`      `-/osssssssssssss" + R + "\n"
        a = a + E + "[34;1m" + ".ossssssso/-`      .-/ossssssssssssssso." + R + "\n"
        a = a + E + "[34;1m" + " `+sss+:.      `.:+ssssssssssssssssss+`" + R + "\n"
        a = a + E + "[34;1m" + "  `:.         .::::::::::::::::::::::`" + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "      .+oooooooooooooooooooooooo+." + R + "\n"
        a = a + E + "[34;1m" + "       -osssssssssssssssssssssso-" + R + "\n"
        a = a + E + "[34;1m" + "        `osssssssssssssssssssso`" + R + "\n"
        emit a
    }
    if startsWith(dn, "sunos") {
        a = a + E + "[33;1m" + E + "[33;1m" + "                 `-     `" + R + "\n"
        a = a + E + "[33;1m" + "          `--    `+-    .:" + R + "\n"
        a = a + E + "[33;1m" + "           .+:  `++:  -/+-     ." + R + "\n"
        a = a + E + "[33;1m" + "    `.::`  -++/``:::`./+/  `.-/." + R + "\n"
        a = a + E + "[33;1m" + "      `++/-`.`          ` /++:`" + R + "\n"
        a = a + E + "[33;1m" + "  ``   ./:`                .: `..`.-" + R + "\n"
        a = a + E + "[33;1m" + "``./+/:-                     -+++:-" + R + "\n"
        a = a + E + "[33;1m" + "    -/+`                      :." + R + "\n"
        emit a
    }
    if startsWith(dn, "hash") {
        a = a + E + "[38;5;123m" + E + "[38;5;123m" + R + "\n"
        a = a + E + "[38;5;123m" + R + "\n"
        a = a + E + "[38;5;123m" + "      +   ######   +" + R + "\n"
        a = a + E + "[38;5;123m" + "    ###   ######   ###" + R + "\n"
        a = a + E + "[38;5;123m" + "  #####   ######   #####" + R + "\n"
        a = a + E + "[38;5;123m" + " ######   ######   ######" + R + "\n"
        a = a + E + "[38;5;123m" + R + "\n"
        a = a + E + "[38;5;123m" + "####### '\"###### '\"########" + R + "\n"
        a = a + E + "[38;5;123m" + "#######   ######   ########" + R + "\n"
        a = a + E + "[38;5;123m" + "#######   ######   ########" + R + "\n"
        a = a + E + "[38;5;123m" + R + "\n"
        a = a + E + "[38;5;123m" + " ###### '\"###### '\"######" + R + "\n"
        a = a + E + "[38;5;123m" + "  #####   ######   #####" + R + "\n"
        a = a + E + "[38;5;123m" + "    ###   ######   ###" + R + "\n"
        a = a + E + "[38;5;123m" + "      ~   ######   ~" + R + "\n"
        a = a + E + "[38;5;123m" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_20(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "arch") {
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
    if startsWith(dn, "arya") {
        a = a + E + "[32;1m" + E + "[32;1m" + "                `oyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "               -syyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "              .syyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "              :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "           `/ :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "          .+s :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "         .oys :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "        -oyys :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "       :syyys :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "      /syyyys :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "     +yyyyyys :yyyyyy/" + E + "[31;1m" + "-yyyyyy+" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "   .oyyyyyyo. :yyyyyy/" + E + "[31;1m" + "-yyyyyy+ ---------" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + "  .syyyyyy+`  :yyyyyy/" + E + "[31;1m" + "-yyyyy+-+syyyyyyyy" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + " -syyyyyy/    :yyyyyy/" + E + "[31;1m" + "-yyys:.syyyyyyyyyy" + R + "\n"
        a = a + E + "[31;1m" + E + "[32;1m" + ":syyyyyy/     :yyyyyy/" + E + "[31;1m" + "-yyo.:syyyyyyyyyyy" + R + "\n"
        emit a
    }
    if startsWith(dn, "blag") {
        a = a + E + "[35;1m" + E + "[35;1m" + "             d" + R + "\n"
        a = a + E + "[35;1m" + "            ,MK:" + R + "\n"
        a = a + E + "[35;1m" + "            xMMMX:" + R + "\n"
        a = a + E + "[35;1m" + "           .NMMMMMX;" + R + "\n"
        a = a + E + "[35;1m" + "           lMMMMMMMM0clodkO0KXWW:" + R + "\n"
        a = a + E + "[35;1m" + "           KMMMMMMMMMMMMMMMMMMX'" + R + "\n"
        a = a + E + "[35;1m" + "      .;d0NMMMMMMMMMMMMMMMMMMK." + R + "\n"
        a = a + E + "[35;1m" + " .;dONMMMMMMMMMMMMMMMMMMMMMMx" + R + "\n"
        a = a + E + "[35;1m" + "'dKMMMMMMMMMMMMMMMMMMMMMMMMl" + R + "\n"
        a = a + E + "[35;1m" + "   .:xKWMMMMMMMMMMMMMMMMMMM0." + R + "\n"
        a = a + E + "[35;1m" + "       .:xNMMMMMMMMMMMMMMMMMK." + R + "\n"
        a = a + E + "[35;1m" + "          lMMMMMMMMMMMMMMMMMMK." + R + "\n"
        a = a + E + "[35;1m" + "          ,MMMMMMMMWkOXWMMMMMM0" + R + "\n"
        a = a + E + "[35;1m" + "          .NMMMMMNd.     `':ldko" + R + "\n"
        a = a + E + "[35;1m" + "           OMMMK:" + R + "\n"
        a = a + E + "[35;1m" + "           oWk," + R + "\n"
        a = a + E + "[35;1m" + "           ;:" + R + "\n"
        emit a
    }
    if startsWith(dn, "crux") {
        a = a + E + "[34;1m" + E + "[34;1m" + "         odddd" + R + "\n"
        a = a + E + "[34;1m" + "      oddxkkkxxdoo" + R + "\n"
        a = a + E + "[34;1m" + "     ddcoddxxxdoool" + R + "\n"
        a = a + E + "[34;1m" + "     xdclodod  olol" + R + "\n"
        a = a + E + "[34;1m" + "     xoc  xdd  olol" + R + "\n"
        a = a + E + "[34;1m" + "     xdc  " + E + "[35;1m" + "k00" + E + "[34;1m" + "Okdlol" + R + "\n"
        a = a + E + "[34;1m" + "     xxd" + E + "[35;1m" + "kOKKKOkd" + E + "[34;1m" + "ldd" + R + "\n"
        a = a + E + "[34;1m" + "     xdco" + E + "[35;1m" + "xOkdlo" + E + "[34;1m" + "dldd" + R + "\n"
        a = a + E + "[34;1m" + "     ddc:cl" + E + "[35;1m" + "lll" + E + "[34;1m" + "oooodo" + R + "\n"
        a = a + E + "[34;1m" + "   odxxdd" + E + "[37;1m" + "xkO000kx" + E + "[34;1m" + "ooxdo" + R + "\n"
        a = a + E + "[34;1m" + "  oxdd" + E + "[37;1m" + "x0NMMMMMMWW0od" + E + "[34;1m" + "kkxo" + R + "\n"
        a = a + E + "[34;1m" + " oooxd" + E + "[37;1m" + "0WMMMMMMMMMW0o" + E + "[34;1m" + "dxkx" + R + "\n"
        a = a + E + "[34;1m" + "docldkXW" + E + "[37;1m" + "MMMMMMMWWN" + E + "[34;1m" + "Odolco" + R + "\n"
        a = a + E + "[34;1m" + "xx" + E + "[35;1m" + "dx" + E + "[34;1m" + "kxxOKN" + E + "[37;1m" + "WMMWN" + E + "[34;1m" + "0xdoxo::c" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "xOkkO" + E + "[34;1m" + "0oo" + E + "[37;1m" + "odOW" + E + "[35;1m" + "WW" + E + "[34;1m" + "XkdodOxc:l" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "dkkkxkkk" + E + "[37;1m" + "OKX" + E + "[35;1m" + "NNNX0Oxx" + E + "[34;1m" + "xc:cd" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + " odxxdx" + E + "[37;1m" + "xllod" + E + "[35;1m" + "ddooxx" + E + "[34;1m" + "dc:ldo" + R + "\n"
        a = a + E + "[34;1m" + E + "[35;1m" + "   lodd" + E + "[34;1m" + "dolccc" + E + "[35;1m" + "ccox" + E + "[34;1m" + "xoloo" + R + "\n"
        emit a
    }
    if startsWith(dn, "guix") {
        a = a + E + "[33;1m" + E + "[33;1m" + " ..                             `." + R + "\n"
        a = a + E + "[33;1m" + " `--..```..`           `..```..--`" + R + "\n"
        a = a + E + "[33;1m" + "   .-:///-:::.       `-:::///:-." + R + "\n"
        a = a + E + "[33;1m" + "      ````.:::`     `:::.````" + R + "\n"
        a = a + E + "[33;1m" + "           -//:`    -::-" + R + "\n"
        a = a + E + "[33;1m" + "            ://:   -::-" + R + "\n"
        a = a + E + "[33;1m" + "            `///- .:::`" + R + "\n"
        a = a + E + "[33;1m" + "             -+++-:::." + R + "\n"
        a = a + E + "[33;1m" + "              :+/:::-" + R + "\n"
        a = a + E + "[33;1m" + "              `-....`" + R + "\n"
        emit a
    }
    if startsWith(dn, "kali") {
        a = a + E + "[34;1m" + E + "[34;1m" + ".............." + R + "\n"
        a = a + E + "[34;1m" + "            ..,;:ccc,." + R + "\n"
        a = a + E + "[34;1m" + "          ......''';lxO." + R + "\n"
        a = a + E + "[34;1m" + ".....''''..........,:ld;" + R + "\n"
        a = a + E + "[34;1m" + "           .';;;:::;,,.x," + R + "\n"
        a = a + E + "[34;1m" + "      ..'''.            0Xxoc:,.  ..." + R + "\n"
        a = a + E + "[34;1m" + "  ....                ,ONkc;,;cokOdc',." + R + "\n"
        a = a + E + "[34;1m" + " .                   OMo           ':" + E + "[38;5;8m" + "dd" + E + "[34;1m" + "o." + R + "\n"
        a = a + E + "[34;1m" + "                    dMc               :OO;" + R + "\n"
        a = a + E + "[34;1m" + "                    0M.                 .:o." + R + "\n"
        a = a + E + "[34;1m" + "                    ;Wd" + R + "\n"
        a = a + E + "[34;1m" + "                     ;XO," + R + "\n"
        a = a + E + "[34;1m" + "                       ,d0Odlc;,.." + R + "\n"
        a = a + E + "[34;1m" + "                           ..',;:cdOOd::,." + R + "\n"
        a = a + E + "[34;1m" + "                                    .:d;.':;." + R + "\n"
        a = a + E + "[34;1m" + "                                       'd,  .'" + R + "\n"
        a = a + E + "[34;1m" + "                                         ;l   .." + R + "\n"
        a = a + E + "[34;1m" + "                                          .o" + R + "\n"
        a = a + E + "[34;1m" + "                                            c" + R + "\n"
        a = a + E + "[34;1m" + "                                            .'" + R + "\n"
        a = a + E + "[34;1m" + "                                             ." + R + "\n"
        emit a
    }
    if startsWith(dn, "kaos") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                     .." + R + "\n"
        a = a + E + "[34;1m" + "  .....         ..OSSAAAAAAA.." + R + "\n"
        a = a + E + "[34;1m" + " .KKKKSS.     .SSAAAAAAAAAAA." + R + "\n"
        a = a + E + "[34;1m" + ".KKKKKSO.    .SAAAAAAAAAA..." + R + "\n"
        a = a + E + "[34;1m" + "KKKKKKS.   .OAAAAAAAA." + R + "\n"
        a = a + E + "[34;1m" + "KKKKKKS.  .OAAAAAA." + R + "\n"
        a = a + E + "[34;1m" + "KKKKKKS. .SSAA.." + R + "\n"
        a = a + E + "[34;1m" + ".KKKKKS..OAAAAAAAAAAAA........" + R + "\n"
        a = a + E + "[34;1m" + " DKKKKO.=AA=========A===AASSSO.." + R + "\n"
        a = a + E + "[34;1m" + "  AKKKS.==========AASSSSAAAAAASS." + R + "\n"
        a = a + E + "[34;1m" + "  .=KKO..========ASS.....SSSSASSSS." + R + "\n"
        a = a + E + "[34;1m" + "    .KK.       .ASS..O.. =SSSSAOSS:" + R + "\n"
        a = a + E + "[34;1m" + "     .OK.      .ASSSSSSSO...=A.SSA." + R + "\n"
        a = a + E + "[34;1m" + "       .K      ..SSSASSSS.. ..SSA." + R + "\n"
        a = a + E + "[34;1m" + "                 .SSS.AAKAKSSKA." + R + "\n"
        a = a + E + "[34;1m" + "                    .SSS....S.." + R + "\n"
        emit a
    }
    if startsWith(dn, "lede") {
        a = a + E + "[34;1m" + "    " + E + "[34;1m" + " _________" + R + "\n"
        a = a + E + "[34;1m" + "    /        /\\" + R + "\n"
        a = a + E + "[34;1m" + "   /  LE    /  \\" + R + "\n"
        a = a + E + "[34;1m" + "  /    DE  /    \\" + R + "\n"
        a = a + E + "[34;1m" + " /________/  LE  \\" + R + "\n"
        a = a + E + "[34;1m" + " \\        \\   DE /" + R + "\n"
        a = a + E + "[34;1m" + "  \\    LE  \\    /" + R + "\n"
        a = a + E + "[34;1m" + "   \\  DE    \\  /" + R + "\n"
        a = a + E + "[34;1m" + "    \\________\\/" + R + "\n"
        emit a
    }
    if startsWith(dn, "lmde") {
        a = a + E + "[32;1m" + "         " + E + "[37;1m" + "`.-::---.." + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + "      .:++++ooooosssoo:." + R + "\n"
        a = a + E + "[32;1m" + "    .+o++::.      `.:oos+." + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "   :oo:.`             -+oo" + E + "[37;1m" + ":" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + " " + E + "[37;1m" + "`" + E + "[32;1m" + "+o/`    ." + E + "[37;1m" + "::::::" + E + "[32;1m" + "-.    .++-" + E + "[37;1m" + "`" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + E + "[37;1m" + "`" + E + "[32;1m" + "/s/    .yyyyyyyyyyo:   +o-" + E + "[37;1m" + "`" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + E + "[37;1m" + "`" + E + "[32;1m" + "so     .ss       ohyo` :s-" + E + "[37;1m" + ":" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + E + "[37;1m" + "`" + E + "[32;1m" + "s/     .ss  h  m  myy/ /s`" + E + "[37;1m" + "`" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + "`s:     `oo  s  m  Myy+-o:`" + R + "\n"
        a = a + E + "[32;1m" + "`oo      :+sdoohyoydyso/." + R + "\n"
        a = a + E + "[32;1m" + " :o.      .:////////++:" + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + " `/++        " + E + "[37;1m" + "-:::::-" + R + "\n"
        a = a + E + "[37;1m" + E + "[32;1m" + "  " + E + "[37;1m" + "`" + E + "[32;1m" + "++-" + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "   " + E + "[37;1m" + "`" + E + "[32;1m" + "/+-" + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "     " + E + "[37;1m" + "." + E + "[32;1m" + "+/." + R + "\n"
        a = a + E + "[32;1m" + E + "[32;1m" + "       " + E + "[37;1m" + "." + E + "[32;1m" + ":+-." + R + "\n"
        a = a + E + "[32;1m" + "          `--.``" + R + "\n"
        emit a
    }
    if startsWith(dn, "maui") {
        a = a + E + "[36;1m" + E + "[36;1m" + "             `.-://////:--`" + R + "\n"
        a = a + E + "[36;1m" + "         .:/oooooooooooooooo+:." + R + "\n"
        a = a + E + "[36;1m" + "      `:+ooooooooooooooooooooooo:`" + R + "\n"
        a = a + E + "[36;1m" + "    `:oooooooooooooooooooooooooooo/`" + R + "\n"
        a = a + E + "[36;1m" + "    ..```-oooooo/-`` `:oooooo+:.` `--" + R + "\n"
        a = a + E + "[36;1m" + "  :.      +oo+-`       /ooo/`       -/" + R + "\n"
        a = a + E + "[36;1m" + " -o.     `o+-          +o/`         -o:" + R + "\n"
        a = a + E + "[36;1m" + "`oo`     ::`  :o/     `+.  .+o`     /oo." + R + "\n"
        a = a + E + "[36;1m" + "/o+      .  -+oo-     `   /oo/     `ooo/" + R + "\n"
        a = a + E + "[36;1m" + "+o-        /ooo+`       .+ooo.     :ooo+" + R + "\n"
        a = a + E + "[36;1m" + "++       .+oooo:       -oooo+     `oooo+" + R + "\n"
        a = a + E + "[36;1m" + ":.      .oooooo`      :ooooo-     :oooo:" + R + "\n"
        a = a + E + "[36;1m" + "`      .oooooo:      :ooooo+     `ooo+-`" + R + "\n"
        a = a + E + "[36;1m" + "      .+oooooo`     -oooooo:     `o/-" + R + "\n"
        a = a + E + "[36;1m" + "      +oooooo:     .ooooooo." + R + "\n"
        a = a + E + "[36;1m" + "     /ooooooo`     /ooooooo/       .." + R + "\n"
        a = a + E + "[36;1m" + "    `:oooooooo/:::/ooooooooo+:--:/:`" + R + "\n"
        a = a + E + "[36;1m" + "      `:+oooooooooooooooooooooo+:`" + R + "\n"
        a = a + E + "[36;1m" + "         .:+oooooooooooooooo+:." + R + "\n"
        a = a + E + "[36;1m" + "             `.-://////:-.`" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_21(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "pisi") {
        a = a + E + "[38;5;12m" + E + "[38;5;12m" + "   \\Fv/!-                      `:?lzC" + R + "\n"
        a = a + E + "[38;5;12m" + E + "[38;5;12m" + "   Q!::=zFx!  " + E + "[37;1m" + "`;v6WBCicl;`  " + E + "[38;5;12m" + ",vCC\\!::#." + R + "\n"
        a = a + E + "[38;5;12m" + E + "[38;5;12m" + "  ,%:::,'` " + E + "[37;1m" + "+#%@@FQ@@.   ,cF%i" + E + "[38;5;12m" + "``-',::a?" + R + "\n"
        a = a + E + "[38;5;12m" + E + "[38;5;12m" + "  +m:,'```" + E + "[37;1m" + "}3,/@@Q\\@@       \"af-" + E + "[38;5;12m" + " `-'\"7f" + R + "\n"
        a = a + E + "[38;5;12m" + "  =o'.` " + E + "[37;1m" + "/m'   :Q@:Qg         ,kl" + E + "[38;5;12m" + "  `.|o" + R + "\n"
        a = a + E + "[38;5;12m" + "  :k` '" + E + "[37;1m" + "$+      'Narm           >d," + E + "[38;5;12m" + "  ii" + R + "\n"
        a = a + E + "[38;5;12m" + "   #`" + E + "[37;1m" + "!p.        `C ,            'd+" + E + "[38;5;12m" + " %'" + R + "\n"
        a = a + E + "[38;5;12m" + E + "[37;1m" + "   !0m                           `6Kv" + R + "\n"
        a = a + E + "[37;1m" + "   =a                              m+" + R + "\n"
        a = a + E + "[37;1m" + "  !A     !\\L|:            :|L\\!     $:" + R + "\n"
        a = a + E + "[37;1m" + " .8`     Q''%Q#'        '#Q%''Q     `0-" + R + "\n"
        a = a + E + "[37;1m" + " :6      E|.6QQu        uQQ6.|E      p:" + R + "\n"
        a = a + E + "[37;1m" + "  i{      \\jts9?        ?9stj\\      u\\" + R + "\n"
        a = a + E + "[37;1m" + "   |a`            -''.            `e>" + R + "\n"
        a = a + E + "[37;1m" + "    ,m+     " + E + "[38;5;12m" + "'^ !`" + E + "[37;1m" + "s@@@@a" + E + "[38;5;12m" + "'\"`+`" + E + "[37;1m" + "     >e'" + R + "\n"
        a = a + E + "[37;1m" + "      !3|" + E + "[38;5;12m" + "`|=>>r-  " + E + "[37;1m" + "'U%:" + E + "[38;5;12m" + "  '>>>=:`\\3!" + R + "\n"
        a = a + E + "[38;5;12m" + "       'xopE|      " + E + "[37;1m" + "`'" + E + "[38;5;12m" + "     `ledoz-" + R + "\n"
        a = a + E + "[38;5;12m" + "    `;=>>+`" + E + "[37;1m" + "`^llci/|==|/iclc;`" + E + "[38;5;12m" + "'>>>>:" + R + "\n"
        a = a + E + "[38;5;12m" + "   `^`+~          " + E + "[37;1m" + "````" + E + "[38;5;12m" + "          !!-^" + R + "\n"
        emit a
    }
    if startsWith(dn, "rosa") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           ROSAROSAROSAROSAR" + R + "\n"
        a = a + E + "[34;1m" + "        ROSA               AROS" + R + "\n"
        a = a + E + "[34;1m" + "      ROS   SAROSAROSAROSAR   AROS" + R + "\n"
        a = a + E + "[34;1m" + "    RO   ROSAROSAROSAROSAROSAR   RO" + R + "\n"
        a = a + E + "[34;1m" + "  ARO  AROSAROSAROSARO      AROS  ROS" + R + "\n"
        a = a + E + "[34;1m" + " ARO  ROSAROS         OSAR   ROSA  ROS" + R + "\n"
        a = a + E + "[34;1m" + " RO  AROSA   ROSAROSAROSA    ROSAR  RO" + R + "\n"
        a = a + E + "[34;1m" + "RO  ROSAR  ROSAROSAROSAR  R  ROSARO  RO" + R + "\n"
        a = a + E + "[34;1m" + "RO  ROSA  AROSAROSAROSA  AR  ROSARO  AR" + R + "\n"
        a = a + E + "[34;1m" + "RO AROS  ROSAROSAROSA   ROS  AROSARO AR" + R + "\n"
        a = a + E + "[34;1m" + "RO AROS  ROSAROSARO   ROSARO  ROSARO AR" + R + "\n"
        a = a + E + "[34;1m" + "RO  ROS  AROSAROS   ROSAROSA AROSAR  AR" + R + "\n"
        a = a + E + "[34;1m" + "RO  ROSA  ROS     ROSAROSAR  ROSARO  RO" + R + "\n"
        a = a + E + "[34;1m" + " RO  ROS     AROSAROSAROSA  ROSARO  AR" + R + "\n"
        a = a + E + "[34;1m" + " ARO  ROSA   ROSAROSAROS   AROSAR  ARO" + R + "\n"
        a = a + E + "[34;1m" + "  ARO  OROSA      R      ROSAROS  ROS" + R + "\n"
        a = a + E + "[34;1m" + "    RO   AROSAROS   AROSAROSAR   RO" + R + "\n"
        a = a + E + "[34;1m" + "     AROS   AROSAROSAROSARO   AROS" + R + "\n"
        a = a + E + "[34;1m" + "        ROSA               SARO" + R + "\n"
        a = a + E + "[34;1m" + "           ROSAROSAROSAROSAR" + R + "\n"
        emit a
    }
    if startsWith(dn, "star") {
        a = a + E + "[37;1m" + E + "[37;1m" + "                   ./" + R + "\n"
        a = a + E + "[37;1m" + "                  `yy-" + R + "\n"
        a = a + E + "[37;1m" + "                 `y.`y`" + R + "\n"
        a = a + E + "[37;1m" + "    ``           s-  .y            `" + R + "\n"
        a = a + E + "[37;1m" + "    +h//:..`    +/    /o    ``..:/so" + R + "\n"
        a = a + E + "[37;1m" + "     /o``.-::/:/+      o/://::-.`+o`" + R + "\n"
        a = a + E + "[37;1m" + "      :s`     `.        .`     `s/" + R + "\n"
        a = a + E + "[37;1m" + "       .y.                    .s-" + R + "\n"
        a = a + E + "[37;1m" + "        `y-                  :s`" + R + "\n"
        a = a + E + "[37;1m" + "      .-//.                  /+:." + R + "\n"
        a = a + E + "[37;1m" + "   .:/:.                       .:/:." + R + "\n"
        a = a + E + "[37;1m" + "-+o:.                             .:+:." + R + "\n"
        a = a + E + "[37;1m" + "-///++///:::`              .-::::///+so-" + R + "\n"
        a = a + E + "[37;1m" + "       ``..o/              d-....```" + R + "\n"
        a = a + E + "[37;1m" + "           s.     `/.      d" + R + "\n"
        a = a + E + "[37;1m" + "           h    .+o-+o-    h." + R + "\n"
        a = a + E + "[37;1m" + "           h  -o/`   `/o:  s:" + R + "\n"
        a = a + E + "[37;1m" + "          -s/o:`       `:o/+/" + R + "\n"
        a = a + E + "[37;1m" + "          /s-             -yo" + R + "\n"
        emit a
    }
    if startsWith(dn, "void") {
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
    if startsWith(dn, "vnux") {
        a = a + E + "[38;5;11m" + E + "[38;5;11m" + "              `" + R + "\n"
        a = a + E + "[38;5;11m" + "           ^[XOx~." + R + "\n"
        a = a + E + "[38;5;11m" + "        ^_nwdbbkp0ti'" + R + "\n"
        a = a + E + "[38;5;11m" + "        <vJCZw0LQ0Uj>" + R + "\n"
        a = a + E + "[38;5;11m" + E + "[38;5;8m" + "          _j>!vC1,," + R + "\n"
        a = a + E + "[38;5;8m" + "     " + E + "[31;1m" + "," + E + "[38;5;8m" + "   ,CY" + E + "[38;5;15m" + "O" + E + "[38;5;8m" + "t" + E + "[38;5;15m" + "O" + E + "[38;5;8m" + "1(l;\"" + R + "\n"
        a = a + E + "[38;5;8m" + "`" + E + "[31;1m" + "~-{r(1I" + E + "[38;5;8m" + " ^" + E + "[38;5;11m" + "/zmwJuc:" + E + "[38;5;8m" + "I^" + R + "\n"
        a = a + E + "[38;5;8m" + "'" + E + "[31;1m" + "?)|" + E + "[38;5;11m" + "U" + E + "[31;1m" + "/}-" + E + "[38;5;8m" + " ^" + E + "[38;5;15m" + "f" + E + "[38;5;11m" + "OCLLOw" + E + "[38;5;15m" + "_" + E + "[38;5;8m" + ",;" + R + "\n"
        a = a + E + "[38;5;8m" + " ," + E + "[31;1m" + "i,``. " + E + "[38;5;8m" + "\"," + E + "[38;5;15m" + "k%ooW@$d\"" + E + "[38;5;8m" + "I,'" + R + "\n"
        a = a + E + "[38;5;8m" + "  '    ;^" + E + "[38;5;15m" + "u$$$$$$$$^<" + E + "[38;5;8m" + ":^" + R + "\n"
        a = a + E + "[38;5;8m" + "   ` .>>" + E + "[38;5;15m" + "($$" + E + "[37;1m" + "$@@@@$$" + E + "[38;5;15m" + "$nl" + E + "[38;5;8m" + "[::" + R + "\n"
        a = a + E + "[38;5;8m" + "    `!}?" + E + "[38;5;15m" + "B$" + E + "[37;1m" + "%&WMMW&%$" + E + "[38;5;15m" + "$1}-" + E + "[38;5;8m" + "}\":" + R + "\n"
        a = a + E + "[38;5;8m" + "    ^?j" + E + "[38;5;15m" + "Z$" + E + "[37;1m" + "WMMWWWWMMW$" + E + "[38;5;15m" + "ofc" + E + "[38;5;8m" + ";;`" + R + "\n"
        a = a + E + "[38;5;8m" + "    <~x&" + E + "[38;5;15m" + "$" + E + "[37;1m" + "&MWWWWWWWWp" + E + "[38;5;15m" + "-" + E + "[37;1m" + "l>[<" + R + "\n"
        a = a + E + "[37;1m" + E + "[38;5;11m" + " 'ljmwn" + E + "[38;5;8m" + "~tk8" + E + "[37;1m" + "MWWWWM8O" + E + "[38;5;8m" + "X" + E + "[38;5;11m" + "r" + E + "[38;5;8m" + "+]nC" + E + "[38;5;11m" + "[" + R + "\n"
        a = a + E + "[38;5;11m" + "!JZqwwdX" + E + "[38;5;8m" + ":^C8" + E + "[37;1m" + "#MMMM@" + E + "[38;5;8m" + "X" + E + "[38;5;11m" + "Odpdpq0<" + R + "\n"
        a = a + E + "[38;5;11m" + "<wwwwmmpO" + E + "[38;5;8m" + "1" + E + "[38;5;15m" + "0@%%%%8" + E + "[38;5;8m" + "d" + E + "[38;5;11m" + "nqmwmqqqJl" + R + "\n"
        a = a + E + "[38;5;11m" + "?QOZmqqqpb" + E + "[38;5;8m" + "t[run/?!" + E + "[38;5;11m" + "0pwqqQj-," + R + "\n"
        a = a + E + "[38;5;11m" + " ^:l<{nUUv>      ^x00J(\"" + R + "\n"
        a = a + E + "[38;5;11m" + "                   ^\"" + R + "\n"
        emit a
    }
    if startsWith(dn, "semc") {
        a = a + E + "[32;1m" + E + "[32;1m" + "            /\\" + R + "\n"
        a = a + E + "[32;1m" + "     ______/  \\" + R + "\n"
        a = a + E + "[32;1m" + "    /      |()| " + E + "[38;5;8m" + "E M C" + R + "\n"
        a = a + E + "[38;5;8m" + E + "[32;1m" + "   |   (-- |  |" + R + "\n"
        a = a + E + "[32;1m" + "    \\   \\  |  |" + R + "\n"
        a = a + E + "[32;1m" + ".----)   | |__|" + R + "\n"
        a = a + E + "[32;1m" + "|_______/ / " + E + "[31;1m" + "\"" + E + "[32;1m" + "  \\" + R + "\n"
        a = a + E + "[32;1m" + "              " + E + "[31;1m" + "\"" + R + "\n"
        a = a + E + "[31;1m" + "            \"" + R + "\n"
        emit a
    }
    if startsWith(dn, "irix") {
        a = a + E + "[34;1m" + E + "[34;1m" + "           ./ohmNd/  +dNmho/-" + R + "\n"
        a = a + E + "[34;1m" + "     `:+ydNMMMMMMMM.-MMMMMMMMMdyo:." + R + "\n"
        a = a + E + "[34;1m" + "   `hMMMMMMNhs/sMMM-:MMM+/shNMMMMMMh`" + R + "\n"
        a = a + E + "[34;1m" + "   -NMMMMMmo-` /MMM-/MMM- `-omMMMMMN." + R + "\n"
        a = a + E + "[34;1m" + " `.`-+hNMMMMMNhyMMM-/MMMshmMMMMMmy+...`" + R + "\n"
        a = a + E + "[34;1m" + "+mMNds:-:sdNMMMMMMMyyMMMMMMMNdo:.:sdMMm+" + R + "\n"
        a = a + E + "[34;1m" + "dMMMMMMmy+.-/ymNMMMMMMMMNmy/-.+hmMMMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "oMMMMmMMMMNds:.+MMMmmMMN/.-odNMMMMmMMMM+" + R + "\n"
        a = a + E + "[34;1m" + ".MMMM-/ymMMMMMmNMMy..hMMNmMMMMMmy/-MMMM." + R + "\n"
        a = a + E + "[34;1m" + " hMMM/ `/dMMMMMMMN////NMMMMMMMd/. /MMMh" + R + "\n"
        a = a + E + "[34;1m" + " /MMMdhmMMMmyyMMMMMMMMMMMMhymMMMmhdMMM:" + R + "\n"
        a = a + E + "[34;1m" + " `mMMMMNho//sdMMMMM//NMMMMms//ohNMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "  `/so/:+ymMMMNMMMM` mMMMMMMMmh+::+o/`" + R + "\n"
        a = a + E + "[34;1m" + "     `yNMMNho-yMMMM` NMMMm.+hNMMNh`" + R + "\n"
        a = a + E + "[34;1m" + "     -MMMMd:  oMMMM. NMMMh  :hMMMM-" + R + "\n"
        a = a + E + "[34;1m" + "      -yNMMMmooMMMM- NMMMyomMMMNy-" + R + "\n"
        a = a + E + "[34;1m" + "        .omMMMMMMMM-`NMMMMMMMmo." + R + "\n"
        a = a + E + "[34;1m" + "          `:hMMMMMM. NMMMMMh/`" + R + "\n"
        a = a + E + "[34;1m" + "             .odNm+  /dNms." + R + "\n"
        emit a
    }
    if startsWith(dn, "aix") {
        a = a + E + "[32;1m" + E + "[32;1m" + "           `:+ssssossossss+-`" + R + "\n"
        a = a + E + "[32;1m" + "        .oys///oyhddddhyo///sy+." + R + "\n"
        a = a + E + "[32;1m" + "      /yo:+hNNNNNNNNNNNNNNNNh+:oy/" + R + "\n"
        a = a + E + "[32;1m" + "    :h/:yNNNNNNNNNNNNNNNNNNNNNNy-+h:" + R + "\n"
        a = a + E + "[32;1m" + "  `ys.yNNNNNNNNNNNNNNNNNNNNNNNNNNy.ys" + R + "\n"
        a = a + E + "[32;1m" + " `h+-mNNNNNNNNNNNNNNNNNNNNNNNNNNNNm-oh" + R + "\n"
        a = a + E + "[32;1m" + " h+-NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN.oy" + R + "\n"
        a = a + E + "[32;1m" + "/d`mNNNNNNN/::mNNNd::m+:/dNNNo::dNNNd`m:" + R + "\n"
        a = a + E + "[32;1m" + "h//NNNNNNN: . .NNNh  mNo  od. -dNNNNN:+y" + R + "\n"
        a = a + E + "[32;1m" + "N.sNNNNNN+ -N/ -NNh  mNNd.   sNNNNNNNo-m" + R + "\n"
        a = a + E + "[32;1m" + "N.sNNNNNs  +oo  /Nh  mNNs` ` /mNNNNNNo-m" + R + "\n"
        a = a + E + "[32;1m" + "h//NNNNh  ossss` +h  md- .hm/ `sNNNNN:+y" + R + "\n"
        a = a + E + "[32;1m" + ":d`mNNN+/yNNNNNd//y//h//oNNNNy//sNNNd`m-" + R + "\n"
        a = a + E + "[32;1m" + " yo-NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNm.ss" + R + "\n"
        a = a + E + "[32;1m" + " `h+-mNNNNNNNNNNNNNNNNNNNNNNNNNNNNm-oy" + R + "\n"
        a = a + E + "[32;1m" + "   sy.yNNNNNNNNNNNNNNNNNNNNNNNNNNs.yo" + R + "\n"
        a = a + E + "[32;1m" + "    :h+-yNNNNNNNNNNNNNNNNNNNNNNs-oh-" + R + "\n"
        a = a + E + "[32;1m" + "      :ys:/yNNNNNNNNNNNNNNNmy/:sy:" + R + "\n"
        a = a + E + "[32;1m" + "        .+ys///osyhhhhys+///sy+." + R + "\n"
        a = a + E + "[32;1m" + "            -/osssossossso/-" + R + "\n"
        emit a
    }
    if startsWith(dn, "bsd") {
        a = a + E + "[31;1m" + E + "[31;1m" + "             ,        ," + R + "\n"
        a = a + E + "[31;1m" + "            /(        )`" + R + "\n"
        a = a + E + "[31;1m" + "            \\ \\___   / |" + R + "\n"
        a = a + E + "[31;1m" + "            /- _  `-/  '" + R + "\n"
        a = a + E + "[31;1m" + "           (" + E + "[37;1m" + "/\\/ \\ " + E + "[31;1m" + "\\   /\\" + R + "\n"
        a = a + E + "[31;1m" + "           " + E + "[37;1m" + "/ /   | `    " + E + "[31;1m" + "\\" + R + "\n"
        a = a + E + "[31;1m" + "           " + E + "[34;1m" + "O O   " + E + "[37;1m" + ") " + E + "[31;1m" + "/    |" + R + "\n"
        a = a + E + "[31;1m" + "           " + E + "[37;1m" + "`-^--'" + E + "[31;1m" + "`<     '" + R + "\n"
        a = a + E + "[31;1m" + "          (_.)  _  )   /" + R + "\n"
        a = a + E + "[31;1m" + "           `.___/`    /" + R + "\n"
        a = a + E + "[31;1m" + "             `-----' /" + R + "\n"
        a = a + E + "[31;1m" + E + "[33;1m" + "<----.     __ / __   \\" + R + "\n"
        a = a + E + "[33;1m" + E + "[33;1m" + "<----|====" + E + "[31;1m" + "O)))" + E + "[33;1m" + "==" + E + "[31;1m" + ") \\) /" + E + "[33;1m" + "====|" + R + "\n"
        a = a + E + "[33;1m" + "<----'    " + E + "[31;1m" + "`--' `.__,' \\" + R + "\n"
        a = a + E + "[31;1m" + "             |        |" + R + "\n"
        a = a + E + "[31;1m" + "              \\       /       /\\" + R + "\n"
        a = a + E + "[31;1m" + "         " + E + "[36;1m" + "______" + E + "[31;1m" + "( (_  / \\______/" + R + "\n"
        a = a + E + "[31;1m" + "       " + E + "[36;1m" + ",'  ,-----'   |" + R + "\n"
        a = a + E + "[36;1m" + "       `--{__________)" + R + "\n"
        emit a
    }
    if startsWith(dn, "itc") {
        a = a + E + "[31;1m" + E + "[31;1m" + "....................-==============+..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "....................-==============:..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "...:===========-....-==============:..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "...-===========:....-==============-..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "....*==========+........-::********-..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "....*===========+.:*====**==*+-.-......" + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "....:============*+-..--:+**====*---..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "......::--........................::..." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "..+-:+-.+::*:+::+:-++::++-.:-.*.:++:++." + R + "\n"
        a = a + E + "[31;1m" + E + "[31;1m" + "..:-:-++++:-::--:+::-::.:++-++:++--:-:.    ⠀⠀⠀⠀⠀" + R + "\n"
        a = a + E + "[31;1m" + "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀" + R + "\n"
        emit a
    }
    emit ""
}
func distroArt_22(dn, E) {
    let R = E + "[0m"
    let a = ""
    if startsWith(dn, "gnu") {
        a = a + E + "[37;1m" + E + "[37;1m" + "    _-`````-,           ,- '- ." + R + "\n"
        a = a + E + "[37;1m" + "  .'   .- - |          | - -.  `." + R + "\n"
        a = a + E + "[37;1m" + " /.'  /                     `.   \\" + R + "\n"
        a = a + E + "[37;1m" + ":/   :      _...   ..._      ``   :" + R + "\n"
        a = a + E + "[37;1m" + "::   :     /._ .`:'_.._\\.    ||   :" + R + "\n"
        a = a + E + "[37;1m" + "::    `._ ./  ,`  :    \\ . _.''   ." + R + "\n"
        a = a + E + "[37;1m" + "`:.      /   |  -.  \\-. \\\\_      /" + R + "\n"
        a = a + E + "[37;1m" + "  \\:._ _/  .'   .@)  \\@) ` `\\ ,.'" + R + "\n"
        a = a + E + "[37;1m" + "     _/,--'       .- .\\,-.`--`." + R + "\n"
        a = a + E + "[37;1m" + "       ,'/''     (( \\ `  )" + R + "\n"
        a = a + E + "[37;1m" + "        /'/'  \\    `-'  (" + R + "\n"
        a = a + E + "[37;1m" + "         '/''  `._,-----'" + R + "\n"
        a = a + E + "[37;1m" + "          ''/'    .,---'" + R + "\n"
        a = a + E + "[37;1m" + "           ''/'      ;:" + R + "\n"
        a = a + E + "[37;1m" + "             ''/''  ''/" + R + "\n"
        a = a + E + "[37;1m" + "               ''/''/''" + R + "\n"
        a = a + E + "[37;1m" + "                 '/'/'" + R + "\n"
        a = a + E + "[37;1m" + "                  `;" + R + "\n"
        emit a
    }
    if startsWith(dn, "kde") {
        a = a + E + "[32;1m" + E + "[32;1m" + "             `..---+/---..`" + R + "\n"
        a = a + E + "[32;1m" + "         `---.``   ``   `.---.`" + R + "\n"
        a = a + E + "[32;1m" + "      .--.`        ``        `-:-." + R + "\n"
        a = a + E + "[32;1m" + "    `:/:     `.----//----.`     :/-" + R + "\n"
        a = a + E + "[32;1m" + "   .:.    `---`          `--.`    .:`" + R + "\n"
        a = a + E + "[32;1m" + "  .:`   `--`                .:-    `:." + R + "\n"
        a = a + E + "[32;1m" + " `/    `:.      `.-::-.`      -:`   `/`" + R + "\n"
        a = a + E + "[32;1m" + " /.    /.     `:++++++++:`     .:    .:" + R + "\n"
        a = a + E + "[32;1m" + "`/    .:     `+++++++++++/      /`   `+`" + R + "\n"
        a = a + E + "[32;1m" + "/+`   --     .++++++++++++`     :.   .+:" + R + "\n"
        a = a + E + "[32;1m" + "`/    .:     `+++++++++++/      /`   `+`" + R + "\n"
        a = a + E + "[32;1m" + " /`    /.     `:++++++++:`     .:    .:" + R + "\n"
        a = a + E + "[32;1m" + " ./    `:.      `.:::-.`      -:`   `/`" + R + "\n"
        a = a + E + "[32;1m" + "  .:`   `--`                .:-    `:." + R + "\n"
        a = a + E + "[32;1m" + "   .:.    `---`          `--.`    .:`" + R + "\n"
        a = a + E + "[32;1m" + "    `:/:     `.----//----.`     :/-" + R + "\n"
        a = a + E + "[32;1m" + "      .-:.`        ``        `-:-." + R + "\n"
        a = a + E + "[32;1m" + "         `---.``   ``   `.---.`" + R + "\n"
        a = a + E + "[32;1m" + "             `..---+/---..`" + R + "\n"
        emit a
    }
    if startsWith(dn, "mer") {
        a = a + E + "[34;1m" + E + "[34;1m" + "                         dMs" + R + "\n"
        a = a + E + "[34;1m" + "                         .-`" + R + "\n"
        a = a + E + "[34;1m" + "                       `y`-o+`" + R + "\n"
        a = a + E + "[34;1m" + "                        ``NMMy" + R + "\n"
        a = a + E + "[34;1m" + "                      .--`:++." + R + "\n"
        a = a + E + "[34;1m" + "                    .hNNNNs" + R + "\n"
        a = a + E + "[34;1m" + "                    /MMMMMN" + R + "\n"
        a = a + E + "[34;1m" + "                    `ommmd/ +/" + R + "\n"
        a = a + E + "[34;1m" + "                      ````  +/" + R + "\n"
        a = a + E + "[34;1m" + "                     `:+sssso/-`" + R + "\n"
        a = a + E + "[34;1m" + "  .-::. `-::-`     `smNMNmdmNMNd/      .://-`" + R + "\n"
        a = a + E + "[34;1m" + ".ymNMNNdmNMMNm+`  -dMMh:.....+dMMs   `sNNMMNo" + R + "\n"
        a = a + E + "[34;1m" + "dMN+::NMMy::hMM+  mMMo `ohhy/ `dMM+  yMMy::-" + R + "\n"
        a = a + E + "[34;1m" + "MMm   yMM-  :MMs  NMN` `:::::--sMMh  dMM`" + R + "\n"
        a = a + E + "[34;1m" + "MMm   yMM-  -MMs  mMM+ `ymmdsymMMMs  dMM`" + R + "\n"
        a = a + E + "[34;1m" + "NNd   sNN-  -NNs  -mMNs-.--..:dMMh`  dNN" + R + "\n"
        a = a + E + "[34;1m" + "---   .--`  `--.   .smMMmdddmMNdo`   .--" + R + "\n"
        a = a + E + "[34;1m" + "                     ./ohddds+:`" + R + "\n"
        a = a + E + "[34;1m" + "                     +h- `.:-." + R + "\n"
        a = a + E + "[34;1m" + "                     ./`.dMMMN+" + R + "\n"
        a = a + E + "[34;1m" + "                        +MMMMMd" + R + "\n"
        a = a + E + "[34;1m" + "                        `+dmmy-" + R + "\n"
        a = a + E + "[34;1m" + "                      ``` .+`" + R + "\n"
        a = a + E + "[34;1m" + "                     .dMNo-y." + R + "\n"
        a = a + E + "[34;1m" + "                     `hmm/" + R + "\n"
        a = a + E + "[34;1m" + "                         .:`" + R + "\n"
        a = a + E + "[34;1m" + "                         dMs" + R + "\n"
        emit a
    }
    if startsWith(dn, "mx") {
        a = a + E + "[34;1m" + E + "[37;1m" + "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMNs..yMMMMMMMMMMMMMm: +NMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMN+    :mMMMMMMMMMNo` -dMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMs.   `oNMMMMMMh- `sNMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMN/    -hMMMN+  :dMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMh-    +ms. .sMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMMN+`   `  +NMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMNMMd:    .dMMMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMm/-hMd-     `sNMMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMNo`   -` :h/    -dMMMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMd:       /NMMh-   `+NMMMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMNo`         :mMMN+`   `-hMMMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMh.            `oNMMd:    `/mMMMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMm/                -hMd-      `sNMMMM" + R + "\n"
        a = a + E + "[37;1m" + "MMNs`                   -          :dMMM" + R + "\n"
        a = a + E + "[37;1m" + "Mm:                                 `oMM" + R + "\n"
        a = a + E + "[37;1m" + "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM" + R + "\n"
        emit a
    }
    if startsWith(dn, "t2") {
        a = a + E + "[37;1m" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "TTTTTTTTTT" + R + "\n"
        a = a + E + "[34;1m" + "    tt   " + E + "[37;1m" + "222" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "    tt  " + E + "[37;1m" + "2   2" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "    tt     " + E + "[37;1m" + "2" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "    tt    " + E + "[37;1m" + "2" + E + "[34;1m" + R + "\n"
        a = a + E + "[34;1m" + "    tt  " + E + "[37;1m" + "22222" + E + "[34;1m" + R + "\n"
        emit a
    }
    emit ""
}
func distroArtTux(E) {
    let R = E + "[0m"
    let W = E + "[37;1m"
    let Y = E + "[33;1m"
    let a = ""
    a = a + W + "         a8888b." + R + "\n"
    a = a + W + "        d888888b." + R + "\n"
    a = a + W + "        8P\"YP\"Y88" + R + "\n"
    a = a + W + "        8|o||o|88" + R + "\n"
    a = a + W + "        8'    .88" + R + "\n"
    a = a + W + "        8`._.' Y8." + R + "\n"
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
func distroArt(dn, E) {
    let r = ""
    r = distroArt_0(dn, E)  if r != "" { emit r }
    r = distroArt_1(dn, E)  if r != "" { emit r }
    r = distroArt_2(dn, E)  if r != "" { emit r }
    r = distroArt_3(dn, E)  if r != "" { emit r }
    r = distroArt_4(dn, E)  if r != "" { emit r }
    r = distroArt_5(dn, E)  if r != "" { emit r }
    r = distroArt_6(dn, E)  if r != "" { emit r }
    r = distroArt_7(dn, E)  if r != "" { emit r }
    r = distroArt_8(dn, E)  if r != "" { emit r }
    r = distroArt_9(dn, E)  if r != "" { emit r }
    r = distroArt_10(dn, E)  if r != "" { emit r }
    r = distroArt_11(dn, E)  if r != "" { emit r }
    r = distroArt_12(dn, E)  if r != "" { emit r }
    r = distroArt_13(dn, E)  if r != "" { emit r }
    r = distroArt_14(dn, E)  if r != "" { emit r }
    r = distroArt_15(dn, E)  if r != "" { emit r }
    r = distroArt_16(dn, E)  if r != "" { emit r }
    r = distroArt_17(dn, E)  if r != "" { emit r }
    r = distroArt_18(dn, E)  if r != "" { emit r }
    r = distroArt_19(dn, E)  if r != "" { emit r }
    r = distroArt_20(dn, E)  if r != "" { emit r }
    r = distroArt_21(dn, E)  if r != "" { emit r }
    r = distroArt_22(dn, E)  if r != "" { emit r }
    emit distroArtTux(E)
}

func run() {
    kfcls()

    let E   = fromCharCode(27)
    let GRN = E + "[32;1m"
    let CYN = E + "[36;1m"
    let RST = E + "[0m"
    let YEL = E + "[33;1m"
    let WHT = E + "[37;1m"

    // Distro-specific ASCII logo (neofetch-derived), chosen by /etc/os-release.
    let art = distroArt(distroName(), E)
    // logo column width = widest logo line (+gap), so any distro aligns.
    let LW = "20"
    let lwk = "0"
    let lwn = linecount(art)
    while toInt(lwk) < toInt(lwn) {
        let lww = toInt(vislen(getLine(art, toInt(lwk))))
        if lww + 3 > toInt(LW) { LW = lww + 3 + "" }
        lwk = toInt(lwk) + 1 + ""
    }

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
