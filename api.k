// api.k — declares C wrappers from kfetch_api.h

jxt {
    c "./kfetch_api.h"
    func exec(cmd)
    func kf_init()
    func kf_cls()
    func kf_get_memory()
    func kf_get_disk_info()
    func kf_get_console_size()
    func kf_get_console_cp()
    func kf_get_tick_ms()
}
