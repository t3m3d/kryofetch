jxt {
    c "./kfetch_api.h"
    func exec(cmd)
    func kfinit()
    func kfcls()
}

func run() {
    kp("hello")
    emit
}

just run {
    run()
}
