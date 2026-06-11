import "utils_macos.k"

func raminfo() {
    let totalBytes = trim(exec("sysctl -n hw.memsize 2>/dev/null"))    if totalBytes == "" { emit "0,0" }
    let totalMB = "" + (toInt(totalBytes) / 1048576)   // div64 is a C-path-only builtin (udf native)

    // pageKB = pagesize / 1024 (16 on Apple Silicon, 4 on Intel)
    let psStr  = trim(exec("sysctl -n hw.pagesize 2>/dev/null"))    let pageKB = toInt(psStr) / 1024
    if pageKB == 0 { pageKB = 16 }

    // free + speculative pages are usable by apps
    let freeStr = trim(exec("vm_stat | awk '/Pages free:/{gsub(/\\.$/,\"\",$3);f=$3} /Pages speculative:/{gsub(/\\.$/,\"\",$3);s=$3} END{print f+s}'"))    let freePages = toInt(freeStr)
    let freeMB    = freePages * pageKB / 1024

    emit totalMB + "," + freeMB + ""
}

func swapinfo() {
    let ut = trim(exec("sysctl vm.swapusage 2>/dev/null | awk '{z=($7+0==0)?1:0; print $7 \"|\" $4 \"|\" z}'"))
    if ut == "" { emit "Unused" }
    let used  = firstpart(ut, "|")
    let rest  = afterpart(ut, "|")
    let total = firstpart(rest, "|")
    let zero  = afterpart(rest, "|")
    if zero == "1" { emit "Unused" }
    // config `swap_format = full|used|fraction|percent`. Default full.
    let fmt = kfconfigget("swap_format", "full")
    if fmt == "used"     { emit used + " used" }
    if fmt == "fraction" { emit used + " / " + total }
    if fmt == "percent"  { emit trim(exec("sysctl vm.swapusage 2>/dev/null | awk '{u=$7;t=$4;gsub(/M/,\"\",u);gsub(/M/,\"\",t);if(t>0)printf \"%.0f%%\",u*100/t; else printf \"0%%\"}'")) }
    emit used + " used / " + total + " total"
}
