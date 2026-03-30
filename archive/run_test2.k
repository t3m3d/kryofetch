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

import "utils.k"
import "cpu.k"
import "os.k"
import "mem.k"
import "disk.k"
import "fetch_test.k"

just run {
    run()
}
