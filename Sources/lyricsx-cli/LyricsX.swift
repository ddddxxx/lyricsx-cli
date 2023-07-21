import ArgumentParser
import LyricsService
import Termbox

enum LyricsFormat: String, EnumerableFlag {
    case lrcx
    case lrc
}

struct LyricsSearch: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "search", abstract: "Search lyrics from the internet.")

    @Argument
    var keyword: String

    @Flag
    var format: LyricsFormat = .lrcx

    func run() throws {
        let provider = LyricsProviders.Group()
        let req = LyricsSearchRequest(searchTerm: .keyword(keyword), duration: 0)
        guard let lrc = provider.lyricsPublisher(request: req).blocking().next() else {
            print("lyrics not found")
            return
        }
        print(format == .lrcx ? lrc.description : lrc.legacyDescription)
    }
}

struct LyricsTick: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "tick",
        abstract: "Tick lyrics to stdout with playing music.")

    func run() throws { tick() }
}

extension Attributes: ExpressibleByArgument {

    static let attrs: [String: Attributes] = [
        "black": .black, "white": .white, "red": .red, "green": .green, "yellow": .yellow,
        "blue": .blue, "magenta": .magenta, "cyan": .cyan,
    ]

    public init?(argument: String) {
        guard let attr = Self.attrs[argument] else { return nil }
        self = attr
    }

    public var defaultValueDescription: String { "cyan" }

    public static var allValueStrings: [String] { Array(attrs.keys) }
}

struct LyricsPlay: ParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "play",
        abstract: "Play lyrics with playing music.")

    @Option(name: .shortAndLong, help: "The hightcolor for the current line.")
    var color: Attributes = .cyan

    @Flag(help: "Disable font bold.")
    var noBold: Bool = false

    func run() throws { play(foreground: noBold ? color : [color, .bold]) }
}

@main
struct LyricsX: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "lyricsx-cli",
        abstract: "LyricsX command line interface.",
        subcommands: [LyricsSearch.self, LyricsTick.self, LyricsPlay.self])
}
