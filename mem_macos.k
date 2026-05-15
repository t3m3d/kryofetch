import "utils_macos.k"

func raminfo() {
    let totalBytes = exec("sysctl -n hw.memsize 2>/dev/null")
    if totalBytes == "" { emit "0,0" }
    let totalMB = div64(totalBytes, "1048576")

    // pageKB = pagesize / 1024 (16 on Apple Silicon, 4 on Intel)
    let psStr  = exec("sysctl -n hw.pagesize 2>/dev/null")
    let pageKB = toInt(psStr) / 1024
    if pageKB == 0 { pageKB = 16 }

    // free + speculative pages are usable by apps
    let freeStr = exec("vm_stat | awk '/Pages free:/{gsub(/\\.$/,\"\",$3);f=$3} /Pages speculative:/{gsub(/\\.$/,\"\",$3);s=$3} END{print f+s}'")
    let freePages = toInt(freeStr)
    let freeMB    = freePages * pageKB / 1024

    emit totalMB + "," + freeMB + ""
}
