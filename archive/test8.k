jxt {
    c "./kfetch_api.h"
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
