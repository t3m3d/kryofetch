import "headers/windows.krh"

func getCpuCoreInfo() {
    // We'll return "cores,threads" as a single string.
    let cores = "0"
    let threads = "0"

    // Low-level buffer dance still happens in C after transpile.
    let len = "0"
    GetLogicalProcessorInformationEx(RelationProcessorCore, 0, &len)

    let buffer = malloc(len)
    if buffer == "0" {
        emit cores + "," + threads
    }

    if GetLogicalProcessorInformationEx(RelationProcessorCore, buffer, &len) == "0" {
        free(buffer)
        emit cores + "," + threads
    }

    let ptr = buffer
    let end = buffer + len

    while ptr < end {
        let info = (SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*)ptr

        if info.Relationship == RelationProcessorCore {
            cores = toInt(cores) + 1 + ""

            let mask = info.Processor.GroupMask[0].Mask
            let count = "0"

            while mask != 0 {
                count = toInt(count) + (mask & 1) + ""
                mask = mask >> 1
            }

            threads = toInt(threads) + toInt(count) + ""
        }

        ptr = ptr + info.Size
    }

    free(buffer)

    emit cores + "," + threads
}

func getArch() {
    let si = SYSTEM_INFO {}
    GetNativeSystemInfo(&si)

    let arch = "Unknown"

    if si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 {
        arch = "x64"
    } else if si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_INTEL {
        arch = "x86"
    } else if si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM {
        arch = "ARM"
    } else if si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM64 {
        arch = "ARM64"
    }

    emit arch
}

func getCpuBrand() {
    let buf = "                                                                                                                                "
    let size = "256"

    let hKey = 0
    let status = RegOpenKeyExA(
        HKEY_LOCAL_MACHINE,
        "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        0,
        KEY_READ,
        &hKey
    )

    if status != ERROR_SUCCESS {
        emit "Unknown CPU"
    }

    let type = "0"
    let dataSize = size

    status = RegQueryValueExA(
        hKey,
        "ProcessorNameString",
        0,
        &type,
        (LPBYTE)buf,
        &dataSize
    )

    RegCloseKey(hKey)

    if status != ERROR_SUCCESS || type != REG_SZ {
        emit "Unknown CPU"
    }

    // Krypton strings are null-terminated in C, so just emit buf.
    emit buf
}