import AppKit
import ScreenCaptureKit
import Foundation

_ = NSApplication.shared
let args = CommandLine.arguments
guard args.count >= 6 else { exit(2) }
let out = args[1]
let x = Double(args[2])!
let y = Double(args[3])!
let w = Double(args[4])!
let h = Double(args[5])!
let sem = DispatchSemaphore(value: 0)
Task {
  do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else { throw NSError(domain:"qa", code:1) }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let cfg = SCStreamConfiguration()
    cfg.width = Int(display.width); cfg.height = Int(display.height); cfg.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    let crop = CGRect(x: x, y: y, width: w, height: h)
    guard let cg = image.cropping(to: crop) else { throw NSError(domain:"qa", code:2) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain:"qa", code:3) }
    try data.write(to: URL(fileURLWithPath: out))
    print("captured \(out) \(Int(crop.width))x\(Int(crop.height))")
  } catch { fputs("capture error: \(error)\n", stderr); exit(1) }
  sem.signal()
}
sem.wait()
