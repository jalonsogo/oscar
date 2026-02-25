import AppKit

NSLog("[OScar] main.swift starting")
let app = NSApplication.shared
NSLog("[OScar] got NSApplication.shared, delegate=%@", String(describing: app.delegate))
let delegate = AppDelegate()
app.delegate = delegate
NSLog("[OScar] delegate set, calling app.run()")
app.run()
