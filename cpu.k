import "headers/windows.krh"

// cpubrand: processor name from registry (no WMI/powershell)
func cpubrand() {
    let regPath = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"
    let name    = trim(regHklmStr(regPath, "ProcessorNameString"))
    if name == "" { emit "Unknown CPU" }
    emit name
}

// cpucores: physical + logical cores via SYSTEM_INFO (no WMI/powershell)
// Note: SYSTEM_INFO.dwNumberOfProcessors = logical processors
// Physical cores via registry VendorIdentifier count is complex; use SYSTEM_INFO
func cpucores() {
    let si      = structNew("SYSTEM_INFO")
    GetNativeSystemInfo(si)
    let logical = structGet(si, "SYSTEM_INFO", "dwNumberOfProcessors")
    // Read physical cores from registry
    let regPath = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"
    let physStr = trim(regHklmStr(regPath, "Identifier"))
    // Fallback: approximate physical = logical (SYSTEM_INFO doesn't expose physical count)
    let physical = logical
    emit physical + "," + logical
}
