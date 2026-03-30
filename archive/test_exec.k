func run() {
    let r = exec("echo test123")
    kp(r)
    emit
}

just run {
    run()
}
