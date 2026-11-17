import Cocoa

let application = NSApplication.shared
let appController = AppController()
application.delegate = appController
application.setActivationPolicy(.accessory)
application.run()
