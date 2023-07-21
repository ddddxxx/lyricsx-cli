// swift-tools-version:5.6

import Foundation
import PackageDescription

let package = Package(
    name: "lyricsx-cli",
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.2.2")),
        .package(url: "https://github.com/ddddxxx/LyricsKit", .upToNextMinor(from: "0.11.3")),
        .package(url: "https://github.com/cx-org/CXExtensions", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/ddddxxx/MusicPlayer", .upToNextMinor(from: "0.8.3")),
        .package(url: "https://github.com/suransea/Termbox", .upToNextMinor(from: "1.0.2")),
    ],
    targets: [
        .executableTarget(
            name: "lyricsx-cli",
            dependencies: [
                "LyricsKit",
                "CXExtensions",
                "MusicPlayer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Termbox",
            ]),
        .testTarget(
            name: "lyricsx-cli-tests",
            dependencies: ["lyricsx-cli"]),
    ]
)

enum CombineImplementation {

    case combine
    case combineX
    case openCombine

    static var `default`: CombineImplementation {
        #if canImport(Combine)
            return .combine
        #else
            return .combineX
        #endif
    }

    init?(_ description: String) {
        let desc = description.lowercased().filter { $0.isLetter }
        switch desc {
        case "combine": self = .combine
        case "combinex": self = .combineX
        case "opencombine": self = .openCombine
        default: return nil
        }
    }
}

extension ProcessInfo {

    var combineImplementation: CombineImplementation {
        return environment["CX_COMBINE_IMPLEMENTATION"].flatMap(CombineImplementation.init)
            ?? .default
    }
}

let info = ProcessInfo.processInfo
if info.combineImplementation == .combine {
    package.platforms = [.macOS("10.15"), .iOS("13.0"), .tvOS("13.0"), .watchOS("6.0")]
}
