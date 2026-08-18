import ApplicationServices
import Darwin
import Foundation

func elements(_ element: AXUIElement, attribute: CFString) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func string(_ element: AXUIElement, attribute: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
    return value as? String ?? ""
}

func value(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
}

func frame(_ element: AXUIElement) -> CGRect {
    guard let rawPosition = value(element, attribute: kAXPositionAttribute as CFString),
          let rawSize = value(element, attribute: kAXSizeAttribute as CFString),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else {
        return .null
    }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &dimensions) else {
        return .null
    }
    return CGRect(origin: point, size: dimensions)
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

func frameJSON(_ frame: CGRect) -> [String: Double] {
    [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.width,
        "height": frame.height
    ]
}

func printJSON(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func descendant(in root: AXUIElement, identifier: String) -> AXUIElement? {
    var stack = [root]
    var visited = Set<CFHashCode>()
    while let element = stack.popLast() {
        guard visited.insert(CFHash(element)).inserted else { continue }
        if string(element, attribute: kAXIdentifierAttribute as CFString) == identifier {
            return element
        }
        let children = [
            kAXChildrenAttribute as CFString,
            "AXChildrenInNavigationOrder" as CFString,
            kAXContentsAttribute as CFString
        ].flatMap { elements(element, attribute: $0) }
        stack.append(contentsOf: children.reversed())
    }
    return nil
}

guard AXIsProcessTrusted() else {
    fputs("accessibility trust is not granted to the external AX client\n", stderr)
    exit(77)
}

let operation: String
let processID: pid_t
let windowIdentifier: String?
let elementIdentifier: String?
if CommandLine.arguments.count == 4, let legacyPID = pid_t(CommandLine.arguments[1]) {
    operation = "press"
    processID = legacyPID
    windowIdentifier = CommandLine.arguments[2]
    elementIdentifier = CommandLine.arguments[3]
} else if CommandLine.arguments.count == 3,
          CommandLine.arguments[1] == "windows",
          let requestedPID = pid_t(CommandLine.arguments[2]) {
    operation = "windows"
    processID = requestedPID
    windowIdentifier = nil
    elementIdentifier = nil
} else if CommandLine.arguments.count == 5,
          ["inspect", "press"].contains(CommandLine.arguments[1]),
          let requestedPID = pid_t(CommandLine.arguments[2]) {
    operation = CommandLine.arguments[1]
    processID = requestedPID
    windowIdentifier = CommandLine.arguments[3]
    elementIdentifier = CommandLine.arguments[4]
} else {
    fputs("usage: NativeAXClient <pid> <window-identifier> <element-identifier> | windows <pid> | inspect|press <pid> <window-identifier> <element-identifier>\n", stderr)
    exit(64)
}

let application = AXUIElementCreateApplication(processID)
let applicationWindows = elements(application, attribute: kAXWindowsAttribute as CFString)

if operation == "windows" {
    do {
        try printJSON([
            "operation": operation,
            "processID": Int(processID),
            "windows": applicationWindows.map { window in
                [
                    "identifier": string(window, attribute: kAXIdentifierAttribute as CFString),
                    "title": string(window, attribute: kAXTitleAttribute as CFString),
                    "frame": frameJSON(frame(window))
                ]
            }
        ])
        exit(0)
    } catch {
        fputs("JSON encoding failed: \(error)\n", stderr)
        exit(65)
    }
}

let requestedWindowIdentifier = windowIdentifier!
let requestedElementIdentifier = elementIdentifier!
let matchingWindows = applicationWindows.filter {
    string($0, attribute: kAXIdentifierAttribute as CFString) == requestedWindowIdentifier
        || string($0, attribute: kAXTitleAttribute as CFString) == requestedWindowIdentifier
}
let located: (window: AXUIElement, target: AXUIElement)? = {
    if let window = matchingWindows.first,
       let target = descendant(in: window, identifier: requestedElementIdentifier) {
        return (window, target)
    }
    guard let target = descendant(in: application, identifier: requestedElementIdentifier),
          let rawWindow = value(target, attribute: kAXWindowAttribute as CFString),
          CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
        return nil
    }
    return (rawWindow as! AXUIElement, target)
}()
guard let located else {
    fputs("target element was absent from the live AX window\n", stderr)
    exit(2)
}
let window = located.window
let target = located.target

if operation == "inspect" {
    do {
        try printJSON([
            "operation": operation,
            "processID": Int(processID),
            "windowIdentifier": requestedWindowIdentifier,
            "matchingWindowCount": matchingWindows.count,
            "windowFrame": frameJSON(frame(window)),
            "elementIdentifier": requestedElementIdentifier,
            "elementFrame": frameJSON(frame(target)),
            "role": string(target, attribute: kAXRoleAttribute as CFString),
            "label": string(target, attribute: kAXDescriptionAttribute as CFString),
            "help": string(target, attribute: kAXHelpAttribute as CFString),
            "enabled": (value(target, attribute: kAXEnabledAttribute as CFString) as? Bool) ?? false,
            "actions": actions(target)
        ])
        exit(0)
    } catch {
        fputs("JSON encoding failed: \(error)\n", stderr)
        exit(65)
    }
}

let error = AXUIElementPerformAction(target, kAXPressAction as CFString)
guard error == .success else {
    fputs("AXPress failed with \(error.rawValue)\n", stderr)
    exit(Int32(error.rawValue))
}
print("AXPress|\(processID)|\(requestedWindowIdentifier)|\(requestedElementIdentifier)")
