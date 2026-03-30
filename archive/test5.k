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

just run {
    run()
}
