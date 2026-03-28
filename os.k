import "headers/windows.krh"
import "headers/advapi32.krh"

func get_os_version() {
    let vi = OSVERSIONINFOEXA {}
    vi.dwOSVersionInfoSize = sizeof(OSVERSIONINFOEXA)

    if !GetVersionExA(&vi) {
        emit "Windows (version unknown)"
    }

    let build = vi.dwBuildNumber + ""

    let edition = "Unknown Edition"
    let editionBuf = buffer(128)
    let type = REG_SZ
    let dataSize = sizeof(editionBuf)

    let hKey = 0
    if RegOpenKeyExA(
        HKEY_LOCAL_MACHINE,
        "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
        0,
        KEY_READ,
        &hKey
    ) == ERROR_SUCCESS {

        if RegQueryValueExA(
            hKey,
            "EditionID",
            0,
            &type,
            (LPBYTE)editionBuf,
            &dataSize
        ) == ERROR_SUCCESS {
            edition = editionBuf
        }

        RegCloseKey(hKey)
    }

    // Map edition names
    if edition == "Professional"            { edition = "Pro" }
    else if edition == "Core"               { edition = "Home" }
    else if edition == "Enterprise"         { edition = "Enterprise" }
    else if edition == "Education"          { edition = "Education" }
    else if edition == "ProfessionalWorkstation" { edition = "Pro Workstation" }
    else if edition == "IoTEnterprise"      { edition = "IoT Enterprise" }
    else if edition == "ProfessionalN"      { edition = "Pro N" }
    else if edition == "CoreN"              { edition = "Home N" }
    else if edition == "CoreSingleLanguage" { edition = "Home Single Language" }

    // Determine Windows version by build number
    let b = toInt(build)
    let version = "Windows"

    if      b >= 26100 { version = "Windows 11" }
    else if b >= 22631 { version = "Windows 11" }
    else if b >= 22621 { version = "Windows 11" }
    else if b >= 22000 { version = "Windows 11" }
    else if b >= 19045 { version = "Windows 10" }
    else if b >= 19044 { version = "Windows 10" }
    else if b >= 19043 { version = "Windows 10" }
    else if b >= 19042 { version = "Windows 10" }
    else if b >= 19041 { version = "Windows 10" }
    else if b >= 18363 { version = "Windows 10" }
    else if b >= 18362 { version = "Windows 10" }
    else if b >= 17763 { version = "Windows 10" }
    else if b >= 17134 { version = "Windows 10" }
    else if b >= 16299 { version = "Windows 10" }
    else if b >= 15063 { version = "Windows 10" }
    else if b >= 14393 { version = "Windows 10" }
    else if b >= 10586 { version = "Windows 10" }
    else if b >= 10240 { version = "Windows 10" }
    else               { version = "Windows (legacy version)" }

    emit version + " " + edition + " (build " + build + ")"
}

func get_uptime() {
    let ms = GetTickCount64()
    let totalSec = ms / 1000
    let minutes  = totalSec / 60
    let hours    = minutes / 60
    let days     = hours / 24

    let h = hours % 24
    let m = minutes % 60

    if days > 0 {
        emit days + " days, " + h + " hrs, " + m + " mins"
    } else if hours > 0 {
        emit h + " hrs, " + m + " mins"
    } else {
        emit m + " mins"
    }
}