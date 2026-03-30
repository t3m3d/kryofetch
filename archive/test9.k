jxt {
    c "./kfetch_api.h"
}

func run() {
    kfinit()
    kfcls()
    let m = kfmem()
    kp(m)
    emit
}

just run {
    run()
}
