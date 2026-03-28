import "headers/windows.krh"
import "headers/setupapi.krh"
import "headers/advapi32.krh"
import "headers/devguid.krh"
import "headers/regstr.krh"

// init_nvapi -> emit "1" on success, "0" on failure
func initNvapi() {
    let h = LoadLibraryA("nvapi64.dll")
    if h == "0" {
        emit "0"
    }

    let q = GetProcAddress(h, "nvapi_QueryInterface")
    if q == "0" {
        emit "0"
    }

    // These symbols/types come from the NVAPI headers you include in C.
    NvAPI_QueryInterface = (NvAPI_QueryInterface_t)q
    NvAPI_Initialize      = (NvAPI_Initialize_t)(uintptr_t)NvAPI_QueryInterface(0x0150E828)
    NvAPI_EnumPhysicalGPUs = (NvAPI_EnumPhysicalGPUs_t)(uintptr_t)NvAPI_QueryInterface(0xE5AC921F)
    NvAPI_GPU_GetMemoryInfo = (NvAPI_GPU_GetMemoryInfo_t)(uintptr_t)NvAPI_QueryInterface(0x0703F2E2)

    if NvAPI_Initialize == 0 || NvAPI_EnumPhysicalGPUs == 0 || NvAPI_GPU_GetMemoryInfo == 0 {
        emit "0"
    }

    if NvAPI_Initialize() != NVAPI_OK {
        emit "0"
    }

    emit "1"
}

// get_vram_usage_nvapi(gpuIndex) -> "usedBytes,totalBytes"
func getVramUsageNvapi(gpuIndex) {
    let used  = "0"
    let total = "0"

    if initNvapi() == "0" {
        emit used + "," + total
    }

    let gpuHandles = gpuHandleArray(16)  // conceptual: array of 16 handles
    let count = "0"

    if NvAPI_EnumPhysicalGPUs(gpuHandles, &count) != NVAPI_OK {
        emit used + "," + total
    }

    if gpuIndex >= toInt(count) {
        emit used + "," + total
    }

    let info = NV_DISPLAY_DRIVER_MEMORY_INFO {}
    memset(&info, 0, sizeof(info))
    info.version = NV_DISPLAY_DRIVER_MEMORY_INFO_VER

    if NvAPI_GPU_GetMemoryInfo(gpuHandles[gpuIndex], &info) != NVAPI_OK {
        emit used + "," + total
    }

    let totalBytes = (toULongLong(info.dedicatedVideoMemory) * 1024 * 1024) + ""
    let freeBytes  = (toULongLong(info.availableDedicatedVideoMemory) * 1024 * 1024) + ""
    let usedBytes  = (toULongLong(totalBytes) - toULongLong(freeBytes)) + ""

    used  = usedBytes
    total = totalBytes

    emit used + "," + total
}

// get_gpus() -> "GPU0\nGPU1" (up to 2 GPUs)
func getGpus() {
    let gpuCount = "0"
    let result = ""

    let hDevInfo = SetupDiGetClassDevsA(
        &GUID_DEVCLASS_DISPLAY,
        0,
        0,
        DIGCF_PRESENT
    )

    if hDevInfo == INVALID_HANDLE_VALUE {
        emit result
    }

    let devInfo = SP_DEVINFO_DATA {}
    devInfo.cbSize = sizeof(SP_DEVINFO_DATA)

    let i = "0"
    while toInt(i) < 10 && toInt(gpuCount) < 2 {
        if SetupDiEnumDeviceInfo(hDevInfo, toInt(i), &devInfo) == 0 {
            break
        }

        let name = buffer(256)
        let size = sizeof(name) + ""
        let type = "0"

        if SetupDiGetDeviceRegistryPropertyA(
                hDevInfo,
                &devInfo,
                SPDRP_DEVICEDESC,
                &type,
                (BYTE*)name,
                toInt(size),
                &size) == 0 {
            i = toInt(i) + 1 + ""
            continue
        }

        if strstr(name, "Microsoft Basic Render") != 0 {
            i = toInt(i) + 1 + ""
            continue
        }

        if gpuCount == "0" {
            result = name
        } else {
            result = result + "\n" + name
        }

        gpuCount = toInt(gpuCount) + 1 + ""
        i = toInt(i) + 1 + ""
    }

    SetupDiDestroyDeviceInfoList(hDevInfo)

    emit result
}

// get_vram_registry(gpuIndex) -> "bytes"
func getVramRegistry(gpuIndex) {
    let memStr = "0"

    let path = "SYSTEM\\CurrentControlSet\\Control\\Video"
    let hKey = 0

    if RegOpenKeyExA(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &hKey) != ERROR_SUCCESS {
        emit memStr
    }

    let subkeyName = buffer(256)
    let subkeyLen = sizeof(subkeyName) + ""
    let index = "0"

    while RegEnumKeyExA(
            hKey,
            toInt(index),
            subkeyName,
            &subkeyLen,
            0,
            0,
            0,
            0) == ERROR_SUCCESS {

        let fullPath =
            "SYSTEM\\CurrentControlSet\\Control\\Video\\" +
            subkeyName +
            "\\0000"

        let hSub = 0
        if RegOpenKeyExA(HKEY_LOCAL_MACHINE, fullPath, 0, KEY_READ, &hSub) == ERROR_SUCCESS {

            let mem = toULongLong("0")
            let memSize = sizeof(mem) + ""

            // modern key
            if RegQueryValueExA(
                    hSub,
                    "HardwareInformation.MemorySize",
                    0,
                    0,
                    (LPBYTE)&mem,
                    &memSize) == ERROR_SUCCESS && mem > 0 {

                if gpuIndex == 0 {
                    RegCloseKey(hSub)
                    RegCloseKey(hKey)
                    emit mem + ""
                }
                gpuIndex = gpuIndex - 1
            }

            mem = 0
            memSize = sizeof(mem) + ""
            if RegQueryValueExA(
                    hSub,
                    "HardwareInformation.MemorySizeLegacy",
                    0,
                    0,
                    (LPBYTE)&mem,
                    &memSize) == ERROR_SUCCESS && mem > 0 {

                if gpuIndex == 0 {
                    RegCloseKey(hSub)
                    RegCloseKey(hKey)
                    emit mem + ""
                }
                gpuIndex = gpuIndex - 1
            }

            mem = 0
            memSize = sizeof(mem) + ""
            if RegQueryValueExA(
                    hSub,
                    "HardwareInformation.qwMemorySize",
                    0,
                    0,
                    (LPBYTE)&mem,
                    &memSize) == ERROR_SUCCESS && mem > 0 {

                if gpuIndex == 0 {
                    RegCloseKey(hSub)
                    RegCloseKey(hKey)
                    emit mem + ""
                }
                gpuIndex = gpuIndex - 1
            }

            RegCloseKey(hSub)
        }

        subkeyLen = sizeof(subkeyName) + ""
        index = toInt(index) + 1 + ""
    }

    RegCloseKey(hKey)
    emit memStr
}