import "utils_macos.k"
import "cpu_macos.k"
import "os_macos.k"
import "mem_macos.k"
import "disk_macos.k"
import "gpu_macos.k"
import "config_macos.k"

func kfcls() {
    let E = fromCharCode(27)
    kp(E + "[2J" + E + "[H")
    emit ""
}

func kfinit() {
    emit ""
}

func kfconsize() {
    let cols = trim(exec("tput cols 2>/dev/null"))    let rows = trim(exec("tput lines 2>/dev/null"))    if cols == "" { emit "0,0" }
    emit trim(cols) + "," + trim(rows)
}

func kfshell() {
    let sh = environ("SHELL")
    if contains(sh, "zsh") {
        let v = trim(exec("zsh --version 2>/dev/null | awk '{print $2}'"))
        if v != "" { emit "zsh " + v }
        emit "zsh"
    }
    if contains(sh, "bash") {
        let v = trim(exec("bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+'"))
        if v != "" { emit "bash " + v }
        emit "bash"
    }
    if contains(sh, "fish") {
        let v = trim(exec("fish --version 2>/dev/null | awk '{print $NF}'"))
        if v != "" { emit "fish " + v }
        emit "fish"
    }
    if contains(sh, "nu") { emit "nushell" }
    if sh != "" { emit sh }
    emit "unknown"
}

func run() {
    kfcls()
    kfinit()

    let E     = fromCharCode(27)
    // info label color — config `label_color = green|red|yellow|blue|magenta|
    // cyan|white` (bold ANSI) or a 0-255 number (256-color). Default green.
    let lcOpt = kfconfigget("label_color", "green")
    let GRN   = E + "[32;1m"
    if lcOpt == "black"   { GRN = E + "[30;1m" }
    if lcOpt == "red"     { GRN = E + "[31;1m" }
    if lcOpt == "green"   { GRN = E + "[32;1m" }
    if lcOpt == "yellow"  { GRN = E + "[33;1m" }
    if lcOpt == "blue"    { GRN = E + "[34;1m" }
    if lcOpt == "magenta" { GRN = E + "[35;1m" }
    if lcOpt == "cyan"    { GRN = E + "[36;1m" }
    if lcOpt == "white"   { GRN = E + "[37;1m" }
    if toInt(lcOpt) > 0   { GRN = E + "[38;5;" + lcOpt + "m" }
    // title color — config `title_color = <name>|0-255`. Default cyan.
    let tcOpt = kfconfigget("title_color", "cyan")
    let CYN   = E + "[36;1m"
    if tcOpt == "black"   { CYN = E + "[30;1m" }
    if tcOpt == "red"     { CYN = E + "[31;1m" }
    if tcOpt == "green"   { CYN = E + "[32;1m" }
    if tcOpt == "yellow"  { CYN = E + "[33;1m" }
    if tcOpt == "blue"    { CYN = E + "[34;1m" }
    if tcOpt == "magenta" { CYN = E + "[35;1m" }
    if tcOpt == "cyan"    { CYN = E + "[36;1m" }
    if tcOpt == "white"   { CYN = E + "[37;1m" }
    if toInt(tcOpt) > 0   { CYN = E + "[38;5;" + tcOpt + "m" }
    let RST   = E + "[0m"
    let BLU   = E + "[34m"
    let CY    = E + "[36m"
    let LW    = "40"

    let GR2 = E + "[32m"
    let YEL = E + "[33m"
    let ORG = E + "[33;1m"
    let RED = E + "[31m"
    let PUR = E + "[35m"
    // logo color — config `logo_color = rainbow` (default multicolor) or a
    // single name/0-255 to paint the whole logo one color.
    let lgcOpt = kfconfigget("logo_color", "rainbow")
    if lgcOpt != "rainbow" {
        let LC = ""
        if lgcOpt == "black"   { LC = E + "[30m" }
        if lgcOpt == "red"     { LC = E + "[31m" }
        if lgcOpt == "green"   { LC = E + "[32m" }
        if lgcOpt == "yellow"  { LC = E + "[33m" }
        if lgcOpt == "blue"    { LC = E + "[34m" }
        if lgcOpt == "magenta" { LC = E + "[35m" }
        if lgcOpt == "cyan"    { LC = E + "[36m" }
        if lgcOpt == "white"   { LC = E + "[37m" }
        if toInt(lgcOpt) > 0   { LC = E + "[38;5;" + lgcOpt + "m" }
        if LC != "" { GR2 = LC  YEL = LC  ORG = LC  RED = LC  PUR = LC  BLU = LC }
    }

    let l0  = GR2 + "                    'c." + RST
    let l1  = GR2 + "                 ,xNMM." + RST
    let l2  = YEL + "               .OMMMMo" + RST
    let l3  = YEL + "               OMMM0," + RST
    let l4  = ORG + "     .;loddo:' loolloddol;." + RST
    let l5  = ORG + "   cKMMMMMMMMMMNWMMMMMMMMMM0:" + RST
    let l6  = RED + " .KMMMMMMMMMMMMMMMMMMMMMMMWd." + RST
    let l7  = RED + " XMMMMMMMMMMMMMMMMMMMMMMMX." + RST
    let l8  = PUR + ";MMMMMMMMMMMMMMMMMMMMMMMM:" + RST
    let l9  = PUR + ":MMMMMMMMMMMMMMMMMMMMMMMM:" + RST
    let l10 = BLU + ".MMMMMMMMMMMMMMMMMMMMMMMMX." + RST
    let l11 = BLU + " kMMMMMMMMMMMMMMMMMMMMMMMMWd." + RST
    let l12 = BLU + " .XMMMMMMMMMMMMMMMMMMMMMMMMMMk" + RST
    let l13 = BLU + "  .XMMMMMMMMMMMMMMMMMMMMMMMMK." + RST
    let l14 = BLU + "    kMMMMMMMMMMMMMMMMMMMMMMd" + RST
    let l15 = BLU + "     ;KMMMMMMMWXXWMMMMMMMk." + RST

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let kern = kfkernel()
    let mdl  = sysmodel()
    let cpu  = cpubrand()
    let ci   = cpucores()
    let cn   = firstpart(ci, ",")
    let tn   = afterpart(ci, ",")

    let swp  = swapinfo()
    let mi   = raminfo()
    let tmb  = firstpart(mi, ",")
    let fmb  = afterpart(mi, ",")
    let umb  = toInt(tmb) - toInt(fmb) + ""
    let tgb  = toInt(tmb) / 1024 + ""
    let ugb  = toInt(umb) / 1024 + ""
    let rpct = toInt(umb) * 100 / toInt(tmb) + ""
    let rb   = rambar(umb, tmb)

    let di   = driveinfo()
    let d1 = nthline(di, "0")
    let d2 = nthline(di, "1")
    let d3 = nthline(di, "2")

    let gp   = gpunames()
    let ng   = linecount(gp)
    let g1 = ""
    let g2 = ""
    if ng == "1" { g1 = gp }
    if toInt(ng) >= 2 {
        g1 = nthline(gp, "0")
        g2 = nthline(gp, "1")
    }
    if g1 == "" { g1 = "None" }

    let vd  = gpuvram()
    let vn  = linecount(vd)
    let vr1 = ""
    let vr2 = ""
    if toInt(vn) >= 1 { vr1 = nthline(vd, "0") }
    if toInt(vn) >= 2 { vr2 = nthline(vd, "1") }

    let tc   = kfconsize()
    let cols = firstpart(tc, ",")
    let rows = afterpart(tc, ",")
    let up   = uptime()
    let sh   = kfshell()
    let tnm  = kfterminal()
    let tfnt = kftermfont()
    let res  = kfresolution()
    let diraw = kfdisplayinfo()
    let dinm  = firstpart(diraw, "|")
    let diraw2 = afterpart(diraw, "|")
    let dipx   = firstpart(diraw2, "|")
    let diraw3 = afterpart(diraw2, "|")
    let dihz   = firstpart(diraw3, "|")
    let diraw4 = afterpart(diraw3, "|")
    let dict   = firstpart(diraw4, "|")
    let discl  = afterpart(diraw4, "|")
    let paren_pos = indexOf(mdl, "(")
    let inch_pos  = indexOf(mdl, "-inch")
    let disize = ""
    if toInt(inch_pos) > 0 {
        if toInt(paren_pos) > 0 { disize = substring(mdl, toInt(paren_pos) + 1, toInt(inch_pos)) }
    }
    let wm   = kfwmver()
    let wmth = kfaccent()
    let thm  = kfthemename()
    let lip  = kflocalip()
    let batraw = kfbattraw()
    let bchip = nthline(batraw, "0")
    let bpct  = nthline(batraw, "1")
    let bmins = nthline(batraw, "2")
    let bchrg = nthline(batraw, "3")
    let bfull = nthline(batraw, "4")
    let bstat = "Discharging"
    if bchrg == "Yes" { bstat = "Charging" }
    if bfull == "Yes" { bstat = "Charged" }
    let bh  = toInt(bmins) / 60 + ""
    let brm = toInt(bmins) - toInt(bh) * 60 + ""
    let btimestr = ""
    if toInt(bmins) > 0 {
        if toInt(bmins) < 65535 { btimestr = bh + " hours, " + brm + " mins remaining" }
    }
    // battery display — config `battery_format = full|status|percent`. Default full.
    let bfmt = kfconfigget("battery_format", "full")
    let batval = bpct + "%"
    if bfmt == "full" {
        if btimestr != "" { batval = batval + " (" + btimestr + ")" }
        batval = batval + " [" + bstat + "]"
    }
    if bfmt == "status" { batval = batval + " [" + bstat + "]" }
    let batlbl = "Battery"

    // term + display values (used by the registry below).
    // config `term_format = full|name|size`. Default full (name + size).
    let tfmt = kfconfigget("term_format", "full")
    let tsize = ""
    if cols != "0" { tsize = cols + "x" + rows }
    let termv = ""
    if tfmt == "name" { termv = tnm }
    if tfmt == "size" { termv = tsize }
    if tfmt == "full" {
        termv = tnm
        if tsize != "" {
            if termv != "" { termv = termv + " " + tsize }
            if termv == "" { termv = tsize }
        }
    }
    let diline = dipx
    if discl != "" { diline = diline + " @ " + discl }
    if disize != "" { diline = diline + " in " + disize + "\"" }
    if dihz != "" { diline = diline + ", " + dihz }

    // keyed field registry — each entry: SEP(30) key US(31) value (may be
    // multi-line). Empty value = field not applicable -> skipped even if listed.
    let SEP = fromCharCode(30)
    let US  = fromCharCode(31)
    // value text color — config `value_color = <name>|0-255`. Default = terminal
    // default fg. VAL resets the label's bold, then applies the value color.
    let vcOpt = kfconfigget("value_color", "default")
    let VAL = RST
    if vcOpt == "black"   { VAL = RST + E + "[30m" }
    if vcOpt == "red"     { VAL = RST + E + "[31m" }
    if vcOpt == "green"   { VAL = RST + E + "[32m" }
    if vcOpt == "yellow"  { VAL = RST + E + "[33m" }
    if vcOpt == "blue"    { VAL = RST + E + "[34m" }
    if vcOpt == "magenta" { VAL = RST + E + "[35m" }
    if vcOpt == "cyan"    { VAL = RST + E + "[36m" }
    if vcOpt == "white"   { VAL = RST + E + "[37m" }
    if toInt(vcOpt) > 0   { VAL = RST + E + "[38;5;" + vcOpt + "m" }
    // usage bars (RAM/Disk) — config `bars = on|off`. Default on.
    let showbars = kfconfigget("bars", "on")
    let rampre = rb + "  "
    if showbars == "off" { rampre = "" }
    // memory display — config `memory_format = gb|mb|percent|fraction`. Default gb.
    let mfOpt = kfconfigget("memory_format", "gb")
    let ramstr = ugb + " GB / " + tgb + " GB  " + rpct + "%"
    if mfOpt == "mb"       { ramstr = umb + " MB / " + tmb + " MB  " + rpct + "%" }
    if mfOpt == "percent"  { ramstr = rpct + "%" }
    if mfOpt == "fraction" { ramstr = ugb + " GB / " + tgb + " GB" }
    // cpu display — config `cpu_format = full|brand|cores`. Default full.
    let cpfOpt = kfconfigget("cpu_format", "full")
    let cpustr = cpu + " (" + cn + "c / " + tn + "t)"
    if cpfOpt == "brand" { cpustr = cpu }
    if cpfOpt == "cores" { cpustr = cpu + " (" + cn + " cores)" }
    // gpu display — config `gpu_format = full|brand`. Default full (name + VRAM).
    let gpfOpt = kfconfigget("gpu_format", "full")
    let gpustr1 = fmtgpu(g1, vr1)
    let gpustr2 = fmtgpu(g2, vr2)
    if gpfOpt == "brand" { gpustr1 = g1  gpustr2 = g2 }
    if gpfOpt == "name"  { gpustr1 = g1  gpustr2 = g2 }
    // host display — config `host_format = full|short|id`. Default full.
    let hfOpt = kfconfigget("host_format", "full")
    let hoststr = mdl
    if hfOpt == "short" {
        let hp = indexOf(mdl, " (")
        if toInt(hp) > 0 { hoststr = substring(mdl, 0, toInt(hp)) }
    }
    if hfOpt == "id" { hoststr = trim(exec("sysctl -n hw.model 2>/dev/null")) }
    // resolution display — config `resolution_format = full|simple`. Default full.
    let rfOpt = kfconfigget("resolution_format", "full")
    let resstr = res
    if rfOpt == "simple" {
        resstr = replace(res, " Retina", "")
        resstr = replace(resstr, " x ", "x")
    }
    // kernel display — config `kernel_format = full|release|name`. Default full.
    let kfmt = kfconfigget("kernel_format", "full")
    let kernstr = kern
    if kfmt == "release" { kernstr = afterpart(kern, " ") }
    if kfmt == "name"    { kernstr = firstpart(kern, " ") }
    // os display — config `os_format = full|noarch|short`. Default full.
    let ofmt = kfconfigget("os_format", "full")
    let osnobuild = os
    let obp = indexOf(os, " (")
    if toInt(obp) > 0 { osnobuild = substring(os, 0, toInt(obp)) }
    let osstr = os + " " + arch
    if ofmt == "noarch" { osstr = os }
    if ofmt == "short"  { osstr = osnobuild }
    // WM theme display — config `theme_format = full|accent|mode`. Default full.
    // (the WMTheme field, e.g. "Graphite (Light)")
    let thfmt = kfconfigget("theme_format", "full")
    let wmthstr = wmth
    if thfmt == "accent" {
        let ap = indexOf(wmth, " (")
        if toInt(ap) > 0 { wmthstr = substring(wmth, 0, toInt(ap)) }
    }
    if thfmt == "mode" {
        let mp = indexOf(wmth, "(")
        if toInt(mp) >= 0 {
            let mq = indexOf(wmth, ")")
            if toInt(mq) > toInt(mp) { wmthstr = substring(wmth, toInt(mp) + 1, toInt(mq)) }
        }
    }
    // label/value separator — config `separator = ...` (default ":"). 1-char
    // keeps the value alignment; longer/empty shifts it slightly.
    let CO = kfconfigget("separator", ":")
    let REG = ""
    REG = REG + SEP + "user" + US + GRN + "User" + CO + "  " + VAL + usr + "@" + host + "\n"
    REG = REG + SEP + "os" + US + GRN + "OS" + CO + "    " + VAL + osstr + "\n"
    REG = REG + SEP + "host" + US + GRN + "Host" + CO + "  " + VAL + hoststr + "\n"
    REG = REG + SEP + "kernel" + US + GRN + "Kernel" + CO + "" + VAL + kernstr + "\n"
    REG = REG + SEP + "cpu" + US + GRN + "CPU" + CO + "   " + VAL + cpustr + "\n"
    let gpuline = GRN + "GPU" + CO + "   " + VAL + gpustr1 + "\n"
    if g2 != "" { gpuline = gpuline + GRN + "GPU2" + CO + "  " + VAL + gpustr2 + "\n" }
    REG = REG + SEP + "gpu" + US + gpuline
    REG = REG + SEP + "ram" + US + GRN + "RAM" + CO + "   " + VAL + rampre + ramstr + "\n"
    REG = REG + SEP + "swap" + US + GRN + "Swap" + CO + "  " + VAL + swp + "\n"
    let diskline = GRN + "Disk" + CO + "  " + VAL + d1 + "\n"
    if d2 != "" { diskline = diskline + "       " + d2 + "\n" }
    if d3 != "" { diskline = diskline + "       " + d3 + "\n" }
    REG = REG + SEP + "disk" + US + diskline
    REG = REG + SEP + "shell" + US + GRN + "Shell" + CO + " " + VAL + sh + "\n"
    let termline = ""
    if termv != "" { termline = GRN + "Term" + CO + "  " + VAL + termv + "\n" }
    REG = REG + SEP + "term" + US + termline
    let tfline = ""
    if tfnt != "" { tfline = GRN + "TermFont" + CO + "" + VAL + tfnt + "\n" }
    REG = REG + SEP + "termfont" + US + tfline
    REG = REG + SEP + "res" + US + GRN + "Res" + CO + "   " + VAL + resstr + "\n"
    let dline = ""
    if dinm != "" { dline = GRN + "Display" + CO + "" + VAL + diline + "\n" }
    REG = REG + SEP + "display" + US + dline
    REG = REG + SEP + "wm" + US + GRN + "WM" + CO + "    " + VAL + wm + "\n"
    REG = REG + SEP + "wmtheme" + US + GRN + "WMTheme" + CO + "" + VAL + wmthstr + "\n"
    REG = REG + SEP + "theme" + US + GRN + "Theme" + CO + " " + VAL + thm + "\n"
    REG = REG + SEP + "uptime" + US + GRN + "Uptime" + CO + "" + VAL + up + "\n"
    REG = REG + SEP + "pkgs" + US + GRN + "Pkgs" + CO + "  " + VAL + kfpkgs() + "\n"
    let ipline = ""
    if lip != "" { ipline = GRN + "IP(en0)" + CO + "" + VAL + lip + "\n" }
    REG = REG + SEP + "ip" + US + ipline
    let batline = ""
    if bchip != "" { batline = GRN + batlbl + CO + VAL + batval + "\n" }
    REG = REG + SEP + "battery" + US + batline

    // assemble the info list in the user's configured field order
    let fields = readFields()
    let IL = ""
    let fi = "0"
    let fcount = linecount(fields)
    while toInt(fi) < toInt(fcount) {
        IL = IL + regGet(REG, nthline(fields, fi))
        fi = toInt(fi) + 1 + ""
    }

    // logo: default apple art, packed \n-joined. Override via `logo =` config:
    // 'none'/'off' hides it; a /path reads ASCII art from a file.
    let LOGO = l0 + "\n" + l1 + "\n" + l2 + "\n" + l3 + "\n" + l4 + "\n" + l5 + "\n" + l6 + "\n" + l7 + "\n" + l8 + "\n" + l9 + "\n" + l10 + "\n" + l11 + "\n" + l12 + "\n" + l13 + "\n" + l14 + "\n" + l15
    let logoW = toInt(LW)
    let logoOpt = kfconfigget("logo", "apple")
    if logoOpt == "none" { LOGO = ""  logoW = 0 }
    if logoOpt == "off"  { LOGO = ""  logoW = 0 }
    // named built-in OS logos + custom file -> customart (width recomputed below)
    let WHT = E + "[37;1m"
    let customart = ""
    if lgcOpt == "rainbow" { } else { WHT = GR2 }
    if logoOpt == "tux" {
        customart = WHT + "    .--." + RST + "\n" + WHT + "   |o_o |" + RST + "\n" + WHT + "   |:_/ |" + RST + "\n" + WHT + "  //   \\ \\" + RST + "\n" + WHT + " (|     | )" + RST + "\n" + WHT + "/'\\_   _/`\\" + RST + "\n" + WHT + "\\___)=(___/" + RST
    }
    if logoOpt == "linux" {
        customart = WHT + "    .--." + RST + "\n" + WHT + "   |o_o |" + RST + "\n" + WHT + "   |:_/ |" + RST + "\n" + WHT + "  //   \\ \\" + RST + "\n" + WHT + " (|     | )" + RST + "\n" + WHT + "/'\\_   _/`\\" + RST + "\n" + WHT + "\\___)=(___/" + RST
    }
    if logoOpt == "windows" {
        let WB = E + "[34;1m"
        if lgcOpt != "rainbow" { WB = WHT }
        customart = WB + " ______  ______" + RST + "\n" + WB + "|      ||      |" + RST + "\n" + WB + "|______||______|" + RST + "\n" + WB + " ______  ______" + RST + "\n" + WB + "|      ||      |" + RST + "\n" + WB + "|______||______|" + RST
    }
    if substring(logoOpt, 0, 1) == "/" {
        let custom = exec("cat \"" + logoOpt + "\" 2>/dev/null")
        if trim(custom) != "" { customart = custom }
    }
    if customart != "" {
        LOGO = customart
        logoW = 0
        let li = "0"
        let lc = linecount(LOGO)
        while toInt(li) < toInt(lc) {
            let w = toInt(vislen(infoline(LOGO, li)))
            if w > logoW { logoW = w }
            li = toInt(li) + 1 + ""
        }
        logoW = logoW + 2
    }

    let idx = "0"
    let infolen = linecount(IL)
    let logolen = "0"
    if LOGO != "" { logolen = linecount(LOGO) }
    let maxidx = infolen
    if toInt(logolen) > toInt(infolen) { maxidx = logolen }
    while toInt(idx) < toInt(maxidx) {
        let logo = ""
        if toInt(idx) < toInt(logolen) { logo = infoline(LOGO, idx) }
        if logoW > 0 { kp(padansi(logo, logoW) + "  " + infoline(IL, idx)) }
        else { kp(infoline(IL, idx)) }
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    let titleOpt = kfconfigget("title", "")
    if titleOpt == "" { kp(CYN + "  KryoFetch" + RST + " by KryptonBytes") }
    else { kp(CYN + "  " + titleOpt + RST) }
    kp("")
    let palOpt = kfconfigget("palette", "blocks")
    if palOpt == "apple" { applepalette() }
    else { if palOpt != "none" { colorpalette() } }
    kp("")
    emit
}

just run {
    run()
}
