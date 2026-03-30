jxt {
    c "./kfetch_api.h"
    func kfinit()
}

func run() {
    let r = exec("echo hello")
    kp(r)
    emit
}

just run {
    run()
}
