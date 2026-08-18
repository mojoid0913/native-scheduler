// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeScheduler",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NativeScheduler",
            path: "Sources/NativeScheduler",
            // Info.plist must NOT be listed as a regular resource (SPM forbids it at the
            // bundle root). It is excluded here and embedded as a Mach-O section instead.
            // See linkerSettings below for the -sectcreate __TEXT __info_plist invocation.
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"])
            ],
            linkerSettings: [
                // Embed Info.plist in the __TEXT,__info_plist Mach-O section.
                // macOS reads this section for all process metadata:
                //   LSUIElement  — hides from Dock/Cmd+Tab
                //   CFBundle*    — bundle identifier, version strings
                //   LSMinimumSystemVersion — enforces macOS 14 floor
                // Path is relative to the package root (where `swift build` runs).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/NativeScheduler/Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "NativeSchedulerTests",
            dependencies: ["NativeScheduler"],
            path: "Tests/NativeSchedulerTests"
        )
    ]
)
