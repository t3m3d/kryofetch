import "headers/windows.krh"

// -----------------------------
// Console color helpers
// -----------------------------
//func set_color(attr) {
//    let h = GetStdHandle(STD_OUTPUT_HANDLE)
//    SetConsoleTextAttribute(h, toInt(attr))
//    emit
//}

//func reset_color() {
//    set_color(FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE)
//    emit
//}

// -----------------------------
// Simple VRAM bar (no loops)
// -----------------------------
func make_vram_bar(usedGB, totalGB) {
    if toFloat(totalGB) <= 0.0 {
        emit "[--------------------] 0.0 / 0.0 GB"
    }

    // Compute percentage
    let pct = (toFloat(usedGB) / toFloat(totalGB)) * 100.0
    let blocks = toInt(pct / 5.0)   // 20 blocks total

    let bar = ""
    let i = "0"

    // Add used blocks
    while toInt(i) < blocks {
        bar = bar + "#"
        i = toInt(i) + 1 + ""
    }

    // Add remaining blocks
    while toInt(i) < 20 {
        bar = bar + "-"
        i = toInt(i) + 1 + ""
    }

    emit "[" + bar + "] " + usedGB + " / " + totalGB + " GB"
}

// -----------------------------
// Print padded text (no ANSI detection)
// -----------------------------
func print_padded_ansi(s, totalWidth) {
    kp(s)

    let pad = toInt(totalWidth) - len(s)
    if pad < 0 { pad = 0 }

    let i = "0"
    while toInt(i) < pad {
        kp(" ")
        i = toInt(i) + 1 + ""
    }

    emit
}

// -----------------------------
// Username / Computer name
// -----------------------------
//func get_username() {
//    let buf = buffer(256)
//    let len = 256

//    if !GetUserNameA(buf, &len) {
//        emit "Unknown"
//    }

//    emit buf
//}

//func get_computername() {
//    let buf = buffer(256)
//    let len = 256

    if !GetComputerNameA(buf, &len) {
        emit "Unknown"
    }

    emit buf
}

// -----------------------------
// Console size (SAFE VERSION)
// -----------------------------
func get_console_size() {
    // Instead of using CONSOLE_SCREEN_BUFFER_INFO,
    // use GetSystemMetrics which your compiler CAN handle.

    let cols = GetSystemMetrics(0) + ""   // SM_CXSCREEN
    let rows = GetSystemMetrics(1) + ""   // SM_CYSCREEN

    emit cols + "," + rows
}