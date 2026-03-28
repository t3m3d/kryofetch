import "headers/windows.krh"
import "cpu.k"
import "gpu.k"
import "mem.k"
import "os.k"
import "disk.k"
import "utils.k"
import "version.k"

func run_kfetch() {
    SetConsoleOutputCP(CP_UTF8)

    // TODO: if you expose argv/argc in Krypton, you can mirror the --help/--version logic here.

    let LOGO_WIDTH = "36"

    let windows_logo_0  = "\x1b[34m        ,.=:!!t3Z3z.,\x1b[0m"
    let windows_logo_1  = "\x1b[34m       :tt:::tt333EE3\x1b[0m"
    let windows_logo_2  = "\x1b[34m       Et:::ztt33EEEL\x1b[36m @Ee.,      ..,\x1b[0m"
    let windows_logo_3  = "\x1b[34m      ;tt:::tt333EE7\x1b[36m ;EEEEEEttttt33#\x1b[0m"
    let windows_logo_4  = "\x1b[34m     :Et:::zt333EEQ\x1b[36m  SEEEEEttttt33QL\x1b[0m"
    let windows_logo_5  = "\x1b[34m     it::::tt333EEF\x1b[36m @EEEEttttt33F\x1b[0m"
    let windows_logo_6  = "\x1b[34m    ;3=*^```\"*4EEV\x1b[36m :EEEEttttt33@.\x1b[0m"
    let windows_logo_7  = "\x1b[36m    ,.=::::!t=.,\x1b[34m  @EEEEtttz33QF\x1b[0m"
    let windows_logo_8  = "\x1b[36m   ;::::::::zt33)\x1b[34m   \"4EEEtttji\x1b[0m"
    let windows_logo_9  = "\x1b[36m  :t::::::::tt33.\x1b[34m :Z3z..  ``\x1b[0m"
    let windows_logo_10 = "\x1b[36m  i::::::::zt33F\x1b[34m AEEEtttt::::ztF\x1b[0m"
    let windows_logo_11 = "\x1b[36m ;:::::::::t33V\x1b[34m ;EEEttttt::::t3\x1b[0m"
    let windows_logo_12 = "\x1b[36m E::::::::zt33L\x1b[34m @EEEtttt::::z3F\x1b[0m"
    let windows_logo_13 = "\x1b[36m{3=*^```\"*4E3)\x1b[34m ;EEEtttt:::::tZ`\x1b[0m"
    let windows_logo_14 = "\x1b[36m             `\x1b[34m :EEEEtttt::::z7\x1b[0m"
    let windows_logo_15 = "\x1b[34m                 \"VEzjt:;;z>*`\x1b[0m"
    let windows_logo_lines = "16"

    // Basic info
    let uptime   = get_uptime()
    let username = get_username()
    let computer = get_computername()
    let osver    = get_os_version()
    let arch     = get_arch()
    let cpu      = get_cpu_brand()

    let cpuInfo  = get_cpu_core_info()      // "cores,threads"
    let cpuCores = split_first(cpuInfo, ",")
    let cpuThreads = split_second(cpuInfo, ",")

    let memInfo  = get_memory_info()        // "totalMB,freeMB"
    let totalMB  = split_first(memInfo, ",")
    let freeMB   = split_second(memInfo, ",")

    let usedMB   = (toInt(totalMB) - toInt(freeMB)) + ""

    let ramPercent = "0"
    if toInt(totalMB) > 0 {
        ramPercent = (toInt(usedMB) * 100 / toInt(totalMB)) + ""
    }

    let barWidth   = "20"
    let usedFilled = (toInt(ramPercent) * toInt(barWidth) / 100) + ""
    let freeFilled = (toInt(barWidth) - toInt(usedFilled)) + ""

    let bar = ""
    let i = "0"
    while toInt(i) < toInt(freeFilled) {
        bar = bar + "▓"
        i = toInt(i) + 1 + ""
    }
    i = "0"
    while toInt(i) < toInt(usedFilled) {
        bar = bar + "█"
        i = toInt(i) + 1 + ""
    }

    let ramBar = "[" + bar + "]"

    let termInfo = get_console_size()       // "cols,rows"
    let cols = split_first(termInfo, ",")
    let rows = split_second(termInfo, ",")

    let cp = GetConsoleOutputCP() + ""

    let gpuNames = get_gpus()              // "gpu0\ngpu1" or fewer
    let gpu1 = ""
    let gpu2 = ""
    let gpu1_vram = ""
    let gpu2_vram = ""

    let gpuCount = count_lines(gpuNames)

    if gpuCount == "0" {
        gpu1 = "None detected"
    } else if gpuCount == "1" {
        let g0 = line_at(gpuNames, "0")

        let used0 = "0"
        let total0 = "0"
        let printed = "0"

        if contains(g0, "NVIDIA") || contains(g0, "GeForce") {
            let vramInfo0 = get_vram_usage_nvapi(0)   // "used,total"
            used0  = split_first(vramInfo0, ",")
            total0 = split_second(vramInfo0, ",")

            if total0 != "0" {
                let usedGB  = toInt(used0)  / (1024 * 1024 * 1024) + ""
                let totalGB = toInt(total0) / (1024 * 1024 * 1024) + ""

                gpu1 = g0 + " (" + format_float(totalGB, "1") + " GB VRAM)"
                gpu1_vram = make_vram_bar(usedGB, totalGB)
                printed = "1"
            }
        }

        if printed == "0" {
            let vram0 = get_vram_registry(0)
            let totalGB = toInt(vram0) / (1024 * 1024 * 1024) + ""
            gpu1 = g0 + " (" + format_float(totalGB, "1") + " GB VRAM)"
            gpu1_vram = "[VRAM usage unavailable]"
        }
    } else {
        let g0 = line_at(gpuNames, "0")
        let g1 = line_at(gpuNames, "1")

        let printed0 = "0"
        let printed1 = "0"

        if contains(g0, "NVIDIA") || contains(g0, "GeForce") {
            let vramInfo0 = get_vram_usage_nvapi(0)
            let used0  = split_first(vramInfo0, ",")
            let total0 = split_second(vramInfo0, ",")

            if total0 != "0" {
                let usedGB0  = toInt(used0)  / (1024 * 1024 * 1024) + ""
                let totalGB0 = toInt(total0) / (1024 * 1024 * 1024) + ""

                gpu1 = g0 + " (" + format_float(totalGB0, "1") + " GB VRAM)"
                gpu1_vram = make_vram_bar(usedGB0, totalGB0)
                printed0 = "1"
            }
        }

        if contains(g1, "NVIDIA") || contains(g1, "GeForce") {
            let vramInfo1 = get_vram_usage_nvapi(1)
            let used1  = split_first(vramInfo1, ",")
            let total1 = split_second(vramInfo1, ",")

            if total1 != "0" {
                let usedGB1  = toInt(used1)  / (1024 * 1024 * 1024) + ""
                let totalGB1 = toInt(total1) / (1024 * 1024 * 1024) + ""

                gpu2 = g1 + " (" + format_float(totalGB1, "1") + " GB VRAM)"
                gpu2_vram = make_vram_bar(usedGB1, totalGB1)
                printed1 = "1"
            }
        }

        if printed0 == "0" {
            let vram0 = get_vram_registry(0)
            let totalGB0 = toInt(vram0) / (1024 * 1024 * 1024) + ""
            gpu1 = g0 + " (" + format_float(totalGB0, "1") + " GB VRAM)"
            gpu1_vram = "[VRAM usage unavailable]"
        }

        if printed1 == "0" {
            let vram1 = get_vram_registry(1)
            let totalGB1 = toInt(vram1) / (1024 * 1024 * 1024) + ""
            gpu2 = g1 + " (" + format_float(totalGB1, "1") + " GB VRAM)"
            gpu2_vram = "[VRAM usage unavailable]"
        }
    }

    let diskInfo = get_disk_info()
    let disk1 = line_at(diskInfo, "0")
    let disk2 = line_at(diskInfo, "1")
    let disk3 = line_at(diskInfo, "2")

    system("cls")

    set_color(FOREGROUND_BLUE | FOREGROUND_INTENSITY)
    kp("KryptonFetch")
    reset_color()
    kp("")

    let line1 = username + "@" + computer
    let line2 = osver + " (" + arch + ")"
    let line3 = cpu + " (" + cpuCores + " cores / " + cpuThreads + " threads)"

    let memLine =
        "RAM: " + usedMB + "MB used / " + totalMB + "MB total " +
        ramPercent + "%  " + ramBar

    let termLine =
        "Terminal: " + cols + "x" + rows + "  CP " + cp

    let line4 = memLine
    let line5 = termLine

    let info0  = line1
    let info1  = line2
    let info2  = line3
    let info3  = gpu1
    let info4  = gpu1_vram
    let info5  = gpu2
    let info6  = gpu2_vram
    let info7  = line5
    let info8  = disk1
    let info9  = disk2
    let info10 = disk3
    let info11 = line4
    let info12 = uptime

    let label0  = "User"
    let label1  = "OS"
    let label2  = "CPU"
    let label3  = "GPU1"
    let label4  = ""
    let label5  = "GPU2"
    let label6  = ""
    let label7  = "Term"
    let label8  = "Disk 1"
    let label9  = "Disk 2"
    let label10 = "Disk 3"
    let label11 = "Memory"
    let label12 = "Uptime"

    let maxLines = "13"
    let totalLines = max(toInt(maxLines), toInt(windows_logo_lines)) + ""

    let idx = "0"
    while toInt(idx) < toInt(totalLines) {
        if toInt(idx) < toInt(windows_logo_lines) {
            if idx == "0"  { print_padded_ansi(windows_logo_0,  toInt(LOGO_WIDTH)) }
            if idx == "1"  { print_padded_ansi(windows_logo_1,  toInt(LOGO_WIDTH)) }
            if idx == "2"  { print_padded_ansi(windows_logo_2,  toInt(LOGO_WIDTH)) }
            if idx == "3"  { print_padded_ansi(windows_logo_3,  toInt(LOGO_WIDTH)) }
            if idx == "4"  { print_padded_ansi(windows_logo_4,  toInt(LOGO_WIDTH)) }
            if idx == "5"  { print_padded_ansi(windows_logo_5,  toInt(LOGO_WIDTH)) }
            if idx == "6"  { print_padded_ansi(windows_logo_6,  toInt(LOGO_WIDTH)) }
            if idx == "7"  { print_padded_ansi(windows_logo_7,  toInt(LOGO_WIDTH)) }
            if idx == "8"  { print_padded_ansi(windows_logo_8,  toInt(LOGO_WIDTH)) }
            if idx == "9"  { print_padded_ansi(windows_logo_9,  toInt(LOGO_WIDTH)) }
            if idx == "10" { print_padded_ansi(windows_logo_10, toInt(LOGO_WIDTH)) }
            if idx == "11" { print_padded_ansi(windows_logo_11, toInt(LOGO_WIDTH)) }
            if idx == "12" { print_padded_ansi(windows_logo_12, toInt(LOGO_WIDTH)) }
            if idx == "13" { print_padded_ansi(windows_logo_13, toInt(LOGO_WIDTH)) }
            if idx == "14" { print_padded_ansi(windows_logo_14, toInt(LOGO_WIDTH)) }
            if idx == "15" { print_padded_ansi(windows_logo_15, toInt(LOGO_WIDTH)) }
        } else {
            print_padded_ansi("", toInt(LOGO_WIDTH))
        }

        kp("    ")

        if toInt(idx) < toInt(maxLines) {
            let label = ""
            let info  = ""

            if idx == "0"  { label = label0;  info = info0  }
            if idx == "1"  { label = label1;  info = info1  }
            if idx == "2"  { label = label2;  info = info2  }
            if idx == "3"  { label = label3;  info = info3  }
            if idx == "4"  { label = label4;  info = info4  }
            if idx == "5"  { label = label5;  info = info5  }
            if idx == "6"  { label = label6;  info = info6  }
            if idx == "7"  { label = label7;  info = info7  }
            if idx == "8"  { label = label8;  info = info8  }
            if idx == "9"  { label = label9;  info = info9  }
            if idx == "10" { label = label10; info = info10 }
            if idx == "11" { label = label11; info = info11 }
            if idx == "12" { label = label12; info = info12 }

            if label != "" {
                set_color(FOREGROUND_GREEN | FOREGROUND_INTENSITY)
                kp(label + ": ")
                reset_color()
            } else {
                kp("      ")
            }

            kp(info)
        } else {
            kp("")
        }

        idx = toInt(idx) + 1 + ""
    }

    kp("")
    set_color(FOREGROUND_GREEN | FOREGROUND_INTENSITY)
    kp("====[ KryptonFetch ]====")
    kp("===[ By KryptonBytes ]===")
    reset_color()
    kp("")

    emit
}

just run {
    run_kfetch()
    emit
}