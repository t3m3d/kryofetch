// kfetch.k — KryptonFetch main display (imports handled by run.k)

func run_kfetch() {
    kf_init()
    kf_cls()

    let ESC    = fromCharCode(27)
    let BLUE   = ESC + "[34;1m"
    let CYAN   = ESC + "[36;1m"
    let GREEN  = ESC + "[32;1m"
    let RESET  = ESC + "[0m"

    let LOGO_WIDTH = "40"

    // Logo lines — ansi() converts literal \x1b to real ESC at runtime
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

    // Gather system info
    let username = get_username()
    let computer = get_computername()
    let osver    = get_os_version()
    let arch     = get_arch()
    let cpuName  = get_cpu_brand()

    let coreInfo   = get_cpu_core_info()
    let cpuCores   = split_first(coreInfo, ",")
    let cpuThreads = split_second(coreInfo, ",")

    let memInfo  = get_memory_info()
    let totalMB  = split_first(memInfo, ",")
    let freeMB   = split_second(memInfo, ",")
    let usedMB   = toInt(totalMB) - toInt(freeMB) + ""
    let totalGB  = toInt(totalMB) / 1024 + ""
    let usedGB   = toInt(usedMB) / 1024 + ""

    let diskInfo = get_disk_info()
    let disk1 = line_at(diskInfo, "0")
    let disk2 = line_at(diskInfo, "1")
    let disk3 = line_at(diskInfo, "2")

    let gpuNames = get_gpus()
    let gpuCount = count_lines(gpuNames)
    let gpu1 = ""
    let gpu2 = ""
    if gpuCount == "1" { gpu1 = gpuNames }
    if toInt(gpuCount) >= 2 {
        gpu1 = line_at(gpuNames, "0")
        gpu2 = line_at(gpuNames, "1")
    }
    if gpu1 == "" { gpu1 = "None detected" }

    let termInfo = kf_get_console_size()
    let termCols = split_first(termInfo, ",")
    let termRows = split_second(termInfo, ",")
    let uptime = get_uptime()

    // Build info lines
    let lbl0  = "User"
    let val0  = username + "@" + computer
    let lbl1  = "OS"
    let val1  = osver + " " + arch
    let lbl2  = "CPU"
    let val2  = cpuName + " (" + cpuCores + "c / " + cpuThreads + "t)"
    let lbl3  = "RAM"
    let val3  = usedGB + " GB / " + totalGB + " GB"
    let lbl4  = "Disk"
    let val4  = disk1
    let lbl5  = ""
    let val5  = disk2
    let lbl6  = ""
    let val6  = disk3
    let lbl7  = "GPU"
    let val7  = gpu1
    let lbl8  = "GPU2"
    let val8  = gpu2
    let lbl9  = "Term"
    let val9  = termCols + "x" + termRows
    let lbl10 = "Uptime"
    let val10 = uptime

    let totalLines = "16"
    let idx = "0"
    while toInt(idx) < toInt(totalLines) {

        let logoLine = ""
        if idx == "0"  { logoLine = l0  }
        if idx == "1"  { logoLine = l1  }
        if idx == "2"  { logoLine = l2  }
        if idx == "3"  { logoLine = l3  }
        if idx == "4"  { logoLine = l4  }
        if idx == "5"  { logoLine = l5  }
        if idx == "6"  { logoLine = l6  }
        if idx == "7"  { logoLine = l7  }
        if idx == "8"  { logoLine = l8  }
        if idx == "9"  { logoLine = l9  }
        if idx == "10" { logoLine = l10 }
        if idx == "11" { logoLine = l11 }
        if idx == "12" { logoLine = l12 }
        if idx == "13" { logoLine = l13 }
        if idx == "14" { logoLine = l14 }
        if idx == "15" { logoLine = l15 }

        let lbl = ""
        let val = ""
        if idx == "0"  { lbl = lbl0;  val = val0  }
        if idx == "1"  { lbl = lbl1;  val = val1  }
        if idx == "2"  { lbl = lbl2;  val = val2  }
        if idx == "3"  { lbl = lbl3;  val = val3  }
        if idx == "4"  { lbl = lbl4;  val = val4  }
        if idx == "5"  { lbl = lbl5;  val = val5  }
        if idx == "6"  { lbl = lbl6;  val = val6  }
        if idx == "7"  { lbl = lbl7;  val = val7  }
        if idx == "8"  { lbl = lbl8;  val = val8  }
        if idx == "9"  { lbl = lbl9;  val = val9  }
        if idx == "10" { lbl = lbl10; val = val10 }

        let infoStr = ""
        if lbl != "" {
            infoStr = GREEN + lbl + ":" + RESET + " " + val
        } else {
            if val != "" { infoStr = "       " + val }
        }

        kp(pad_ansi(logoLine, toInt(LOGO_WIDTH)) + "  " + infoStr)
        idx = toInt(idx) + 1 + ""
    }

    kp("")
    kp(CYAN + "  KryptonFetch" + RESET + " by KryptonBytes")
    kp("")

    emit
}
