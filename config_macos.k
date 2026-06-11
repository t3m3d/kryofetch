// kryofetch config — neofetch-style field selection.
// ~/.config/kryofetch/config lists the field keys to show, one per line, in
// order. Comment (#) or delete a line to hide a field. Created on first run.

func kfconfigpath() { emit environ("HOME") + "/.config/kryofetch/config" }

func defaultFieldList() {
    emit "user\nos\nhost\nkernel\ncpu\ngpu\nram\nswap\ndisk\nshell\nterm\ntermfont\nres\ndisplay\nwm\nwmtheme\ntheme\nuptime\npkgs\nip\nbattery"
}

func writeDefaultConfig() {
    exec("mkdir -p \"$HOME/.config/kryofetch\" 2>/dev/null")
    let c = "# kryofetch config\n"
    c = c + "# List the fields to show, one per line, in the order you want them.\n"
    c = c + "# Comment out (#) or delete a line to hide that field. Reorder freely.\n"
    c = c + "#\n"
    c = c + "# available fields:\n"
    c = c + "#   user os host kernel cpu gpu ram swap disk shell term termfont\n"
    c = c + "#   res display wm wmtheme theme uptime pkgs ip battery\n"
    c = c + "#\n"
    c = c + "# logo: 'apple' (default), a built-in OS logo ('tux'/'linux', 'windows'),\n"
    c = c + "# 'none' (hide it), or a path to your own ASCII art file. Uncomment + edit:\n"
    c = c + "# logo = apple\n"
    c = c + "#\n"
    c = c + "# logo_color: 'rainbow' (default multicolor) or a single name/0-255\n"
    c = c + "# to paint the whole logo one color. Uncomment + edit:\n"
    c = c + "# logo_color = rainbow\n"
    c = c + "#\n"
    c = c + "# palette: 'blocks' (default color squares), 'apple' (a row of little\n"
    c = c + "# Apple logos in color), or 'none'. Uncomment + edit:\n"
    c = c + "# palette = blocks\n"
    c = c + "#\n"
    c = c + "# label_color: color of the info labels (User:, OS:, ...). A name\n"
    c = c + "# (green red yellow blue magenta cyan white) or a 0-255 256-color\n"
    c = c + "# number. Uncomment + edit:\n"
    c = c + "# label_color = green\n"
    c = c + "#\n"
    c = c + "# value_color: color of the values (after each label). A name or a\n"
    c = c + "# 0-255 number; default = terminal foreground. Uncomment + edit:\n"
    c = c + "# value_color = white\n"
    c = c + "#\n"
    c = c + "# bars: show the RAM/Disk usage bars ('on', default) or hide them\n"
    c = c + "# ('off' = numbers only). Uncomment + edit:\n"
    c = c + "# bars = on\n"
    c = c + "#\n"
    c = c + "# separator: char(s) between each label and its value (default ':').\n"
    c = c + "# A single char keeps alignment. Examples: '->'  '|'  '='  '' (none).\n"
    c = c + "# separator = :\n"
    c = c + "#\n"
    c = c + "# palette_width: width of each color swatch (spaces), default 3.\n"
    c = c + "# palette_width = 3\n"
    c = c + "#\n"
    c = c + "# title: the bottom title/branding line (default 'KryoFetch by\n"
    c = c + "# KryptonBytes'). Set your own text. Uncomment + edit:\n"
    c = c + "# title = KryoFetch by KryptonBytes\n"
    c = c + "#\n"
    c = c + "# title_color: color of the title line. A name or 0-255 number;\n"
    c = c + "# default cyan. Uncomment + edit:\n"
    c = c + "# title_color = cyan\n"
    c = c + "\n"
    c = c + "user\nos\nhost\nkernel\ncpu\ngpu\nram\nswap\ndisk\nshell\nterm\ntermfont\n"
    c = c + "res\ndisplay\nwm\nwmtheme\ntheme\nuptime\npkgs\nip\nbattery\n"
    writeFile(kfconfigpath(), c)
    emit ""
}

// Returns the ordered field keys (\n-joined). Reads the config; writes a default
// + returns the default order on first run. Skips blank lines and # comments.
func readFields() {
    let path = kfconfigpath()
    let txt = exec("cat \"" + path + "\" 2>/dev/null")
    if trim(txt) == "" {
        writeDefaultConfig()
        emit defaultFieldList()
    }
    let out = ""
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(txt, toInt(start), len(txt))
        let nlPos = indexOf(rest, "\n")
        let line = ""
        if nlPos < 0 { line = rest  done = "1" }
        else {
            line = substring(rest, 0, toInt(nlPos))
            start = toInt(start) + toInt(nlPos) + 1 + ""
        }
        let t = trim(line)
        if t != "" {
            if substring(t, 0, 1) != "#" {
                // lines with '=' are settings (e.g. logo = apple), not fields
                if indexOf(t, "=") < 0 {
                    if out != "" { out = out + "\n" }
                    out = out + toLower(t)
                }
            }
        }
    }
    if out == "" { emit defaultFieldList() }
    emit out
}

// Read a `key = value` setting from the config. Returns dflt if not set.
func kfconfigget(key, dflt) {
    let txt = exec("cat \"" + kfconfigpath() + "\" 2>/dev/null")
    let start = "0"
    let done = "0"
    while done == "0" {
        let rest = substring(txt, toInt(start), len(txt))
        let nlPos = indexOf(rest, "\n")
        let line = ""
        if nlPos < 0 { line = rest  done = "1" }
        else {
            line = substring(rest, 0, toInt(nlPos))
            start = toInt(start) + toInt(nlPos) + 1 + ""
        }
        let t = trim(line)
        if t != "" {
            if substring(t, 0, 1) != "#" {
                let eq = indexOf(t, "=")
                if eq >= 0 {
                    if toLower(trim(substring(t, 0, toInt(eq)))) == key {
                        emit trim(substring(t, toInt(eq) + 1, len(t)))
                    }
                }
            }
        }
    }
    emit dflt
}

// Look up a field's rendered line(s) in the keyed registry REG. Entries are
// SEP(30) + key + US(31) + value; value may span lines (sub-lines). "" if absent.
func regGet(reg, key) {
    let SEP = fromCharCode(30)
    let US = fromCharCode(31)
    let needle = SEP + key + US
    let pos = indexOf(reg, needle)
    if pos < 0 { emit "" }
    let begin = toInt(pos) + len(needle)
    let rest = substring(reg, begin, len(reg))
    let endPos = indexOf(rest, SEP)
    if endPos < 0 { emit rest }
    emit substring(rest, 0, toInt(endPos))
}
