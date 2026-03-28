import "headers/windows.krh"

func getDiskInfo() {
    let out = ""

    let drives = GetLogicalDrives()

    // Iterate letters A..Z
    let letter = "65"   // 'A'
    while toInt(letter) <= 90 {
        let bit = 1 << (toInt(letter) - toInt("65"))
        if (drives & bit) == 0 {
            letter = toInt(letter) + 1 + ""
            continue
        }

        let root = fromCharCode(letter) + ":\\"

        let freeBytes = ULARGE_INTEGER {}
        let totalBytes = ULARGE_INTEGER {}
        let totalFreeBytes = ULARGE_INTEGER {}

        if GetDiskFreeSpaceExA(root, &freeBytes, &totalBytes, &totalFreeBytes) == "0" {
            let line = root + "  (access denied)\n"
            out = out + line
            letter = toInt(letter) + 1 + ""
            continue
        }

        let totalGB = (totalBytes.QuadPart / (1024 * 1024 * 1024)) + ""
        let freeGB  = (totalFreeBytes.QuadPart / (1024 * 1024 * 1024)) + ""
        let usedGB  = (toInt(totalGB) - toInt(freeGB)) + ""

        let percent = "0"
        if toInt(totalGB) > 0 {
            // crude integer percent
            percent = (toInt(usedGB) * 100 / toInt(totalGB)) + ""
        }

        let width = "20"
        let used = (toInt(percent) * toInt(width) / 100) + ""
        let free = (toInt(width) - toInt(used)) + ""

        let bar = ""
        let i = "0"
        while toInt(i) < toInt(used) {
            bar = bar + "▓"
            i = toInt(i) + 1 + ""
        }

        i = "0"
        while toInt(i) < toInt(free) {
            bar = bar + "█"
            i = toInt(i) + 1 + ""
        }

        let line =
            root + "  " +
            usedGB + "GB / " +
            totalGB + "GB  " +
            percent + "%  [" +
            bar + "]\n"

        out = out + line

        letter = toInt(letter) + 1 + ""
    }

    emit out
}