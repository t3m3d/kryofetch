jxt {
    c "./kfetch_api.h"
    func exec(cmd)
    func kfinit()
    func kfcls()
    func kfmem()
    func kfdisk()
    func kfconsize()
    func kfticks()
}

func run() {
    kp("hello")
    emit
}

import "utils.k"
import "cpu.k"
import "os.k"
import "mem.k"
import "disk.k"
import "gpu.k"

just run {
    run()
}
