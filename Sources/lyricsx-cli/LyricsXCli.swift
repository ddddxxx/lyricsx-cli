import Foundation
import ArgumentParser
import LyricsService
import CXExtensions
import MusicPlayer

enum LyricsFormat: String, EnumerableFlag {
    case lrcx
    case lrc
}

struct LyricsSearch: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "search", abstract: "search lyrics from the internet")
    
    @Argument
    var keyword: String
    
    @Flag
    var format: LyricsFormat = .lrcx
    
    func run() throws {
        let provider = LyricsProviders.Group()
        let req = LyricsSearchRequest(searchTerm: .keyword(keyword), title: "", artist: "", duration: 0)
        guard let lrc = provider.lyricsPublisher(request: req).blocking().next() else {
            print("lyrics not found")
            return
        }
        print(format == .lrcx ? lrc.description : lrc.legacyDescription)
    }
}

#if os(macOS)
typealias PlayingPlayer = MusicPlayers.SystemMedia
#elseif os(Linux)
typealias PlayingPlayer = MusicPlayers.MPRISNowPlaying
#endif

struct LyricsTick: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "tick",
                                                    abstract: "tick lyrics to stdout from the internet, with playing music")
    
    func run() throws {
        let ticker = LyricTicker(player: PlayingPlayer()!) { line in
            print(line.content)
        }
        ticker.start()
        
        #if os(Linux)
        GRunLoop.main.run()
        #else
        RunLoop.main.run()
        #endif
    }
}

struct LyricsX: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "lyricsx-cli",
                                                    abstract: "LyricsX command line interface",
                                                    subcommands: [LyricsSearch.self, LyricsTick.self])
}
