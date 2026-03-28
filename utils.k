import "headers/windows.krh"
import "headers/advapi32.krh"
import "headers/user32.krh"

// -----------------------------
// Console color helpers
// -----------------------------
func set_color(attr) {
    let h = GetStdHandle(STD_OUTPUT_HANDLE)
    SetConsoleTextAttribute(h, toInt(attr))
    emit
}

func reset_color() {
    // Default Windows console color = white (RGB)
    set_color(FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE)
    emit
}

// -----------------------------
// VRAM bar builder
// -----------------------------
func make_vram_bar(usedGB, totalGB) {
    let barWidth = "20"

    if toFloat(totalGB) <= 0.0 {
        emit "[" + repeat(" ", toInt(barWidth)) + "] 0.0 / 0.0 GB"
    }

    let freeGB = toFloat(totalGB) - toFloat(usedGB)
    if freeGB < 0.0 { freeGB = 0.0 }

    let usedBlocks = (toFloat(usedGB) / toFloat(totalGB) * toInt(barWidth)) + ""
    let ub = toInt(usedBlocks)
    if ub < 0 { ub = 0 }
    if ub > toInt(barWidth) { ub = toInt(barWidth) }

    let freeBlocks = toInt(barWidth) - ub

    let bar = ""
    let i = "0"
    while toInt(i) < ub {
        bar = bar + "▓"
        i = toInt(i) + 1 + ""
    }

    i = "0"
    while toInt(i) < freeBlocks {
        bar = bar + "█"
        i = toInt(i) + 1 + ""
    }

    emit "[" + bar + "] " +
         format_float(usedGB, "1") + " / " +
         format_float(totalGB, "1") + " GB"
}

// -----------------------------
// ANSI width calculation
// -----------------------------
func visible_width(s) {
    let width = "0"
    let inEsc = "0"

    let i = "0"
    while charAt(s, i) != "" {
        let c = charAt(s, i)

        if c == "\x1b" {
            inEsc = "1"
        } else if inEsc == "1" && c == "m" {
            inEsc = "0"
        } else if inEsc == "0" {
            width = toInt(width) + 1 + ""
        }

        i = toInt(i) + 1 + ""
    }

    emit width
}

// -----------------------------
// Print padded ANSI text
// -----------------------------
func print_padded_ansi(s, totalWidth) {
    let w = visible_width(s)
    let pad = toInt(totalWidth) - toInt(w)
    if pad < 0 { pad = 0 }

    kp(s)

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
func get_username() {
    let buf = buffer(256)
    let len = 256

    if !GetUserNameA(buf, &len) {
        emit "Unknown"
    }

    emit buf
}

func get_computername() {
    let buf = buffer(256)
    let len = 256

    if !GetComputerNameA(buf, &len) {
        emit "Unknown"
    }

    emit buf
}

// -----------------------------
// Console size
// -----------------------------
func get_console_size() {
    let csbi = CONSOLE_SCREEN_BUFFER_INFO {}
    let h = GetStdHandle(STD_OUTPUT_HANDLE)

    if GetConsoleScreenBufferInfo(h, &csbi) {
        let cols = (csbi.srWindow.Right - csbi.srWindow.Left + 1) + ""
        let rows = (csbi.srWindow.Bottom - csbi.srWindow.Top + 1) + ""
        emit cols + "," + rows
    }

    emit "0,0"
}