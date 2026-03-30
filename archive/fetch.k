func run() {
    kfinit()
    kfcls()

    let E     = fromCharCode(27)
    let GRN   = E + "[32;1m"
    let CYN   = E + "[36;1m"
    let RST   = E + "[0m"
    let LW    = "40"

    let l0  = ansi("\x1b[34m        ,.=:!!t3Z3z.,\x1b[0m")
    let l1  = ansi("\x1b[34m       :tt:::tt333EE3\x1b[0m")
    let l2  = ansi("\x1b[34m       Et:::ztt33EEEL\x1b[36m @Ee.,      ..,\x1b[0m")
    let l3  = ansi("\x1b[34m      ;tt:::tt333EE7\x1b[36m ;EEEEEEttttt33#\x1b[0m")
    let l4  = ansi("\x1b[34m     :Et:::zt333EEQ\x1b[36m  SEEEEEttttt33QL\x1b[0m")
    let l5  = ansi("\x1b[34m     it::::tt333EEF\x1b[36m @EEEEttttt33F\x1b[0m")
    let l6  = ansi("\x1b[34m    ;3=*^   \"*4EEV\x1b[36m :EEEEttttt33@.\x1b[0m")
    let l7  = ansi("\x1b[36m    ,.=::::!t=.,\x1b[34m  @EEEEtttz33QF\x1b[0m")
    let l8  = ansi("\x1b[36m   ;::::::::zt33)\x1b[34m   \"4EEEtttji\x1b[0m")
    let l9  = ansi("\x1b[36m  :t::::::::tt33.\x1b[34m :Z3z..    \x1b[0m")
    let l10 = ansi("\x1b[36m  i::::::::zt33F\x1b[34m AEEEtttt::::ztF\x1b[0m")
    let l11 = ansi("\x1b[36m ;:::::::::t33V\x1b[34m ;EEEttttt::::t3\x1b[0m")
    let l12 = ansi("\x1b[36m E::::::::zt33L\x1b[34m @EEEtttt::::z3F\x1b[0m")
    let l13 = ansi("\x1b[36m{3=*^   \"*4E3)\x1b[34m ;EEEtttt:::::tZ\x1b[0m")
    let l14 = ansi("\x1b[36m            \x1b[34m :EEEEtttt::::z7\x1b[0m")
    let l15 = ansi("\x1b[34m                 \"VEzjt:;;z>*\x1b[0m")

    let usr  = sysuser()
    let host = syshost()
    let arch = sysarch()
    let os   = osver()
    let cpu  = cpubrand()
    let ci   = cpucores()
    let cn   = firstpart(ci, ",")
    let tn   = afterpart(ci, ",")

    let mi   = raminfo()
    let tmb  = firstpart(mi, ",")
    let fmb  = afterpart(mi, ",")
    let umb  = toInt(tmb) - toInt(fmb) + ""
    let tgb  = toInt(tmb) / 1024 + ""
    let ugb  = toInt(umb) / 1024 + ""

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

    let tc   = kfconsize()
    let cols = firstpart(tc, ",")
    let rows = afterpart(tc, ",")
    let up   = uptime()

    let lb0  = "User"
    let v0   = usr + "@" + host
    let lb1  = "OS"
    let v1   = os + " " + arch
    let lb2  = "CPU"
    let v2   = cpu + " (" + cn + "c / " + tn + "t)"
    let lb3  = "RAM"
    let v3   = ugb + " GB / " + tgb + " GB"
    let lb4  = "Disk"
    let v4   = d1
    let lb5  = ""
    let v5   = d2
    let lb6  = ""
    let v6   = d3
    let lb7  = "GPU"
    let v7   = g1
    let lb8  = "GPU2"
    let v8   = g2
    let lb9  = "Term"
    let v9   = cols + "x" + rows
    let lb10 = "Uptime"
    let v10  = up

    let idx = "0"
    while toInt(idx) < 16 {
        let logo = ""
        if idx == "0"  { logo = l0  }
        if idx == "1"  { logo = l1  }
        if idx == "2"  { logo = l2  }
        if idx == "3"  { logo = l3  }
        if idx == "4"  { logo = l4  }
        if idx == "5"  { logo = l5  }
        if idx == "6"  { logo = l6  }
        if idx == "7"  { logo = l7  }
        if idx == "8"  { logo = l8  }
        if idx == "9"  { logo = l9  }
        if idx == "10" { logo = l10 }
        if idx == "11" { logo = l11 }
        if idx == "12" { logo = l12 }
        if idx == "13" { logo = l13 }
        if idx == "14" { logo = l14 }
        if idx == "15" { logo = l15 }

        let lb = ""
        let v  = ""
        if idx == "0"  { lb = lb0;  v = v0  }
        if idx == "1"  { lb = lb1;  v = v1  }
        if idx == "2"  { lb = lb2;  v = v2  }
        if idx == "3"  { lb = lb3;  v = v3  }
        if idx == "4"  { lb = lb4;  v = v4  }
        if idx == "5"  { lb = lb5;  v = v5  }
        if idx == "6"  { lb = lb6;  v = v6  }
        if idx == "7"  { lb = lb7;  v = v7  }
        if idx == "8"  { lb = lb8;  v = v8  }
        if idx == "9"  { lb = lb9;  v = v9  }
        if idx == "10" { lb = lb10; v = v10 }

        let info = ""
        if lb != "" {
            info = GRN + lb + ":" + RST + " " + v
        } else {
            if v != "" { info = "       " + v }
        }

        kp(padansi(logo, toInt(LW)) + "  " + info)
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    kp(CYN + "  KryptonFetch" + RST + " by KryptonBytes")
    kp("")
    emit
}
