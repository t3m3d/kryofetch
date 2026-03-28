import "headers/windows.krh"

func get_memory_info() {
    let total = "0"
    let free  = "0"

    let ms = MEMORYSTATUSEX {}
    ms.dwLength = sizeof(MEMORYSTATUSEX)

    if GlobalMemoryStatusEx(&ms) {
        let t = ms.ullTotalPhys / (1024 * 1024)
        let f = ms.ullAvailPhys / (1024 * 1024)

        total = t + ""
        free  = f + ""
    }

    emit total + "," + free
}