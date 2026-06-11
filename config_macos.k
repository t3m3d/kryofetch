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
                if out != "" { out = out + "\n" }
                out = out + toLower(t)
            }
        }
    }
    if out == "" { emit defaultFieldList() }
    emit out
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
