jxt {
    c "./kfetch_api.h"
    func exec(cmd)
    func kfinit()
}

func run() {
    kp("hello")
    emit
}

just run {
    run()
}
