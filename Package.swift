// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "lyricsx-cli",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.0.1")),
        .package(url: "https://github.com/ddddxxx/LyricsKit", .upToNextMinor(from: "0.8.3")),
        .package(url: "https://github.com/cx-org/CXExtensions", .upToNextMinor(from: "0.2.2")),
    ],
    targets: [
        .target(
            name: "lyricsx-cli",
            dependencies: ["ArgumentParser", "LyricsKit", "CXExtensions"]),
        .testTarget(
            name: "lyricsx-cliTests",
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
