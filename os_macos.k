import "utils_macos.k"

func osver() {
    let v     = trim(exec("sw_vers -productVersion 2>/dev/null"))    let build = trim(exec("sw_vers -buildVersion 2>/dev/null"))    if v == "" { emit "macOS" }
    let major = firstpart(v, ".")
    let name  = ""
    if major == "26" { name = "Tahoe" }
    if major == "15" { name = "Sequoia" }
    if major == "14" { name = "Sonoma" }
    if major == "13" { name = "Ventura" }
    if major == "12" { name = "Monterey" }
    if major == "11" { name = "Big Sur" }
    if name == "" { emit "macOS " + v + " (" + build + ")" }
    emit "macOS " + name + " " + v + " (" + build + ")"
}

func _plur(n, w) {
    if toInt(n) == 1 { emit n + " " + w }
    emit n + " " + w + "s"
}

func uptime() {
    let boot = trim(exec("sysctl -n kern.boottime 2>/dev/null | grep -oE 'sec = [0-9]+' | head -1 | grep -oE '[0-9]+'"))
    if boot == "" { emit "unknown" }
    let secs = toInt(trim(exec("date +%s"))) - toInt(boot)
    if secs < 0 { secs = 0 }
    let days = secs / 86400 + ""
    let rem  = secs - toInt(days) * 86400
    let hrs  = rem / 3600 + ""
    let mins = (rem - toInt(hrs) * 3600) / 60 + ""
    let fmt = kfconfigget("uptime_format", "pretty")
    if fmt == "tiny" { fmt = "short" }
    if fmt == "seconds" { emit secs + "s" }
    if fmt == "short" {
        let o = ""
        if toInt(days) > 0 { o = days + "d" }
        if toInt(hrs) > 0  { if o != "" { o = o + " " }  o = o + hrs + "h" }
        if o != "" { o = o + " " }
        emit o + mins + "m"
    }
    if fmt == "pretty" {
        let hh = hrs
        let mm = mins
        if toInt(hrs) < 10  { hh = "0" + hrs }
        if toInt(mins) < 10 { mm = "0" + mins }
        if toInt(days) > 0 { emit _plur(days, "day") + ", " + hh + ":" + mm }
        emit hh + ":" + mm
    }
    let o = ""
    if toInt(days) > 0 { o = _plur(days, "day") }
    if toInt(hrs) > 0  { if o != "" { o = o + ", " }  o = o + _plur(hrs, "hour") }
    if o != "" { o = o + ", " }
    emit o + _plur(mins, "min")
}

func kfresolution() {
    let res = trim(exec("system_profiler SPDisplaysDataType 2>/dev/null | grep 'Resolution:' | head -1 | sed 's/.*Resolution: //' | sed 's/ @ .*//'"))    if res == "" { emit "unknown" }
    emit trim(res)
}

func kfterminal() {
    let tp = environ("TERM_PROGRAM")
    if tp == "" { emit "" }
    let ver = environ("TERM_PROGRAM_VERSION")
    if ver != "" { emit tp + " " + ver }
    emit tp
}

func kftheme() {
    let style = trim(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))    if style == "Dark" { emit "Dark" }
    emit "Light"
}

func kfbattraw() {
    let raw = trim(exec("ioreg -r -n AppleSmartBattery 2>/dev/null | awk '/\"DeviceName\"/{gsub(/.*= \"/,\"\");gsub(/\".*/,\"\");chip=$0} /\"CurrentCapacity\" =/{pct=$NF} /\"TimeRemaining\" =/{mins=$NF} /\"IsCharging\" =/{chrg=$NF} /\"FullyCharged\" =/{full=$NF} END{print chip;print pct;print mins;print chrg;print full}'"))    emit raw
}

func kfkernel() {
    let k = trim(exec("uname -sr 2>/dev/null"))    if k == "" { emit "unknown" }
    emit trim(k)
}

func sysmodel() {
    let mid = trim(exec("sysctl -n hw.model 2>/dev/null"))
    // M1
    if mid == "MacBookAir10,1"  { emit "MacBook Air (M1, 2020)" }
    if mid == "MacBookPro17,1"  { emit "MacBook Pro (13-inch, M1, 2020)" }
    if mid == "Macmini9,1"      { emit "Mac mini (M1, 2020)" }
    if mid == "iMac21,1"        { emit "iMac (24-inch, M1, 2021)" }
    if mid == "iMac21,2"        { emit "iMac (24-inch, M1, 2021)" }
    if mid == "MacBookPro18,1"  { emit "MacBook Pro (16-inch, M1 Pro, 2021)" }
    if mid == "MacBookPro18,2"  { emit "MacBook Pro (16-inch, M1 Max, 2021)" }
    if mid == "MacBookPro18,3"  { emit "MacBook Pro (14-inch, M1 Pro, 2021)" }
    if mid == "MacBookPro18,4"  { emit "MacBook Pro (14-inch, M1 Max, 2021)" }
    if mid == "Mac13,1"         { emit "Mac Studio (M1 Max, 2022)" }
    if mid == "Mac13,2"         { emit "Mac Studio (M1 Ultra, 2022)" }
    // M2
    if mid == "Mac14,2"         { emit "MacBook Air (M2, 2022)" }
    if mid == "Mac14,7"         { emit "MacBook Pro (13-inch, M2, 2022)" }
    if mid == "Mac14,3"         { emit "Mac mini (M2, 2023)" }
    if mid == "Mac14,12"        { emit "Mac mini (M2 Pro, 2023)" }
    if mid == "Mac14,5"         { emit "MacBook Pro (14-inch, M2 Max, 2023)" }
    if mid == "Mac14,6"         { emit "MacBook Pro (16-inch, M2 Max, 2023)" }
    if mid == "Mac14,9"         { emit "MacBook Pro (14-inch, M2 Pro, 2023)" }
    if mid == "Mac14,10"        { emit "MacBook Pro (16-inch, M2 Pro, 2023)" }
    if mid == "Mac14,8"         { emit "Mac Pro (M2 Ultra, 2023)" }
    if mid == "Mac14,13"        { emit "Mac Studio (M2 Max, 2023)" }
    if mid == "Mac14,14"        { emit "Mac Studio (M2 Ultra, 2023)" }
    if mid == "Mac14,15"        { emit "MacBook Air (15-inch, M2, 2023)" }
    // M3
    if mid == "Mac15,3"         { emit "MacBook Pro (14-inch, M3, 2023)" }
    if mid == "Mac15,6"         { emit "MacBook Pro (14-inch, M3 Pro, 2023)" }
    if mid == "Mac15,7"         { emit "MacBook Pro (14-inch, M3 Max, 2023)" }
    if mid == "Mac15,9"         { emit "MacBook Pro (14-inch, M3 Pro, 2023)" }
    if mid == "Mac15,8"         { emit "MacBook Pro (16-inch, M3 Pro, 2023)" }
    if mid == "Mac15,10"        { emit "MacBook Pro (16-inch, M3 Pro, 2023)" }
    if mid == "Mac15,11"        { emit "MacBook Pro (16-inch, M3 Max, 2023)" }
    if mid == "Mac15,4"         { emit "iMac (24-inch, M3, 2023)" }
    if mid == "Mac15,5"         { emit "iMac (24-inch, M3, 2023)" }
    if mid == "Mac15,12"        { emit "MacBook Air (15-inch, M3, 2024)" }
    if mid == "Mac15,13"        { emit "MacBook Air (13-inch, M3, 2024)" }
    // M4
    if mid == "Mac16,1"         { emit "MacBook Pro (14-inch, M4, 2024)" }
    if mid == "Mac16,5"         { emit "MacBook Pro (16-inch, M4 Pro, 2024)" }
    if mid == "Mac16,6"         { emit "MacBook Pro (14-inch, M4 Pro, 2024)" }
    if mid == "Mac16,7"         { emit "MacBook Pro (14-inch, M4 Max, 2024)" }
    if mid == "Mac16,8"         { emit "MacBook Pro (16-inch, M4 Max, 2024)" }
    if mid == "Mac16,10"        { emit "iMac (24-inch, M4, 2024)" }
    if mid == "Mac16,11"        { emit "Mac mini (M4, 2024)" }
    if mid == "Mac16,15"        { emit "Mac mini (M4 Pro, 2024)" }
    if mid == "Mac16,12"        { emit "MacBook Air (13-inch, M4, 2025)" }
    if mid == "Mac16,13"        { emit "MacBook Air (15-inch, M4, 2025)" }
    if mid == "Mac16,14"        { emit "Mac Studio (M4 Max, 2025)" }
    if mid == "Mac16,16"        { emit "Mac Studio (M4 Ultra, 2025)" }
    // fallback to machine name
    let name = trim(exec("system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2}'"))    if name != "" { emit trim(name) }
    emit "unknown"
}

func kftermfont() {
    let tp = environ("TERM_PROGRAM")
    if tp == "iTerm.app" {
        let f = trim(exec("defaults read com.googlecode.iterm2 \"Normal Font\" 2>/dev/null | awk '{n=split($0,a,\" \");sz=a[n];nm=\"\";for(i=1;i<n;i++){nm=nm a[i]\" \"};gsub(/-Regular|-Bold|-Light|-Medium|-Thin|-ExtraLight|-SemiBold/,\"\",nm);gsub(/^ | $/,\"\",nm);print nm \" (\" sz \"pt)\"}'"))
        if f != "" { emit f }
    }
    emit ""
}

func kfdisplayinfo() {
    let raw = trim(exec("system_profiler SPDisplaysDataType -json 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);[print(a.get('_name','')+'|'+a.get('_spdisplays_pixels','').replace(' x ','x')+'|'+(a.get('_spdisplays_resolution','').split('@')[1].strip().rstrip('Hz').split('.')[0]+'Hz' if '@' in a.get('_spdisplays_resolution','') else '')+'|'+('Built-in' if 'internal' in a.get('spdisplays_connection_type','') else 'External')+'|'+('2x' if 'Retina' in a.get('spdisplays_pixelresolution','') else '1x')) for arr in d.get('SPDisplaysDataType',[]) for a in arr.get('spdisplays_ndrvs',[])]\" 2>/dev/null | head -1"))    if raw == "" { emit "" }
    emit trim(raw)
}

func kfwmver() {
    let v = trim(exec("defaults read /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/version.plist CFBundleShortVersionString 2>/dev/null"))
    if v == "" { emit "Quartz Compositor" }
    emit "Quartz Compositor " + v
}

func kfaccent() {
    let ac = trim(exec("defaults read -g AppleAccentColor 2>/dev/null"))
    let name = "Multicolor"
    if ac == "-1" { name = "Graphite" }
    if ac == "0"  { name = "Red" }
    if ac == "1"  { name = "Orange" }
    if ac == "2"  { name = "Yellow" }
    if ac == "3"  { name = "Green" }
    if ac == "4"  { name = "Blue" }
    if ac == "5"  { name = "Purple" }
    if ac == "6"  { name = "Pink" }
    let style = trim(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if style == "" { style = "Light" }
    emit name + " (" + style + ")"
}

func kfthemename() {
    let v = trim(exec("sw_vers -productVersion 2>/dev/null"))    let major = firstpart(v, ".")
    if toInt(major) >= 26 { emit "Liquid Glass" }
    emit "Aqua"
}

func kflocalip() {
    let ip = trim(exec("ifconfig en0 2>/dev/null | awk 'BEGIN{b[\"0\"]=0;b[\"1\"]=1;b[\"2\"]=1;b[\"3\"]=2;b[\"4\"]=1;b[\"5\"]=2;b[\"6\"]=2;b[\"7\"]=3;b[\"8\"]=1;b[\"9\"]=2;b[\"a\"]=2;b[\"b\"]=3;b[\"c\"]=2;b[\"d\"]=3;b[\"e\"]=3;b[\"f\"]=4} /inet /{ip=$2;hex=$4;sub(/0x/,\"\",hex);bits=0;for(i=1;i<=8;i++)bits+=b[tolower(substr(hex,i,1))];print ip\"/\"bits}'"))    if ip == "" { emit "" }
    emit trim(ip)
}

func sysuser() {
    let u = environ("USER")
    if u != "" { emit u }
    emit trim(exec("whoami"))}

func syshost() {
    let h = trim(exec("hostname -s 2>/dev/null"))    if h == "" { emit "localhost" }
    emit h
}

func sysarch() {
    let a = trim(exec("uname -m"))    if a == "arm64"  { emit "arm64" }
    if a == "x86_64" { emit "x86_64" }
    if a == "" { emit "unknown" }
    emit a
}
