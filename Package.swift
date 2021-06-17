// swift-tools-version:5.2

import PackageDescription

var targetDependences: [Target.Dependency] = [
    "LyricsKit",
    "CXExtensions",
    .product(name: "ArgumentParser", package: "swift-argument-parser"),
]

#if os(macOS)
targetDependences.append("MusicPlayer")
#elseif os(Linux)
targetDependences.append("playerctl")
#endif

var targets: [Target] = [
    .target(
        name: "lyricsx-cli",
        dependencies: targetDependences),
    .testTarget(
        name: "lyricsx-cli-tests",
        dependencies: ["lyricsx-cli"]),
]

#if os(Linux)
targets.append(.systemLibrary(name: "playerctl", pkgConfig: "playerctl"))
#endif

let package = Package(
    name: "lyricsx-cli",
    products: [
        .executable(name: "lyricsx-cli", targets: ["lyricsx-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/ddddxxx/LyricsKit", .upToNextMinor(from: "0.9.1")),
        .package(url: "https://github.com/cx-org/CXExtensions", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/ddddxxx/MusicPlayer", .upToNextMinor(from: "0.7.1")),
    ],
    targets: targets
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
        case "combine":     self = .combine
        case "combinex":    self = .combineX
        case "opencombine": self = .openCombine
        default:            return nil
        }
    }
}

extension ProcessInfo {

    var combineImplementation: CombineImplementation {
        return environment["CX_COMBINE_IMPLEMENTATION"].flatMap(CombineImplementation.init) ?? .default
    }
}

import Foundation

let info = ProcessInfo.processInfo
if info.combineImplementation == .combine {
    package.platforms = [.macOS("10.15"), .iOS("13.0"), .tvOS("13.0"), .watchOS("6.0")]
}
