import Foundation
import CoreGraphics
import AppKit

func number(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? -1 }
let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
switch args[1] {
case "cursor":
    let p = CGEvent(source: nil)?.location ?? .zero
    print("cursor x=\(p.x) y=\(p.y)")
case "move":
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else { exit(2) }
    let p = CGPoint(x: x, y: y)
    CGWarpMouseCursorPosition(p)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    print("moved x=\(x) y=\(y)")
case "windows":
    guard args.count >= 3, let pid = Int32(args[2]) else { exit(2) }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? ?? []
    for case let w as NSDictionary in list where number(w[kCGWindowOwnerPID]) == Int(pid) {
        print("id=\(number(w[kCGWindowNumber])) layer=\(number(w[kCGWindowLayer])) name=\(w[kCGWindowName] ?? "") bounds=\(w[kCGWindowBounds] ?? "")")
    }
case "capture":
    guard args.count >= 4, let wid = UInt32(args[2]) else { exit(2) }
    guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]) else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! data.write(to: URL(fileURLWithPath: args[3]))
    print("captured id=\(wid) width=\(image.width) height=\(image.height) path=\(args[3])")
default: exit(2)
}
