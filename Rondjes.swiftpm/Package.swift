// swift-tools-version: 5.9

// WARNING:
// This is generated code. Do not modify this file by hand unless you know
// what you are doing; Xcode / Swift Playgrounds keep it in sync.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Rondjes",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Rondjes",
            targets: ["AppModule"],
            bundleIdentifier: "nl.rondjes.app",
            teamIdentifier: "",
            displayVersion: "2.0",
            bundleVersion: "2",
            appIcon: .placeholder(icon: .map),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [
                .phone,
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight
            ],
            capabilities: [
                .locationWhenInUse(purposeString: "Rondjes gebruikt je locatie om je huis als start- en eindpunt van je hardlooprondjes in te stellen.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
