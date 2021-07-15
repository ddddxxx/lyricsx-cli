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
        let req = LyricsSearchRequest(searchTerm: .keyword(keyword), duration: 0)
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
                                                    abstract: "tick lyrics to stdout with playing music")
    
    func run() throws {
        let ticker = LyricTicker(player: PlayingPlayer()!)
        ticker.onTrack = { track in
            guard let track = track else { return }
            print("\nPlaying:")
            print("Title: \(track.title ?? "")\nArtist: \(track.artist ?? "")\nAlbum: \(track.album ?? "")\n")
        }
        ticker.onLyrics = { lyric in
            guard let lrc = lyric else { return }
            print("Matched:")
            print("Source: \(lrc.metadata.service?.rawValue ?? "Unknown")\n")
        }
        ticker.onSeek = { [unowned ticker] old, new in
            ticker.lines.prefix(new + 1).dropFirst(old < new && old > 0 ? old : 0).forEach { print($0.content) }
        }
        ticker.onLine = { print($0.content) }
        ticker.start()
        
        #if os(Linux)
        GRunLoop.main.run()
        #else
        RunLoop.main.run()
        #endif
        
        ticker.stop()
    }
}

import Termbox

struct LyricsPlay: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "play",
                                                    abstract: "play lyrics with playing music")
    
    func run() throws {
        try Termbox.initialize()
        #if os(Linux)
        Thread.detachNewThread {
            Thread.current.name = "GMainLoop"
            GRunLoop.main.run()
        }
        #endif
        
        let player = LyricPlayer(player: PlayingPlayer()!)
        player.start()
        loop: while true {
            guard let event = Termbox.pollEvent() else {
                continue
            }
            switch event {
            case .character(modifier: .none, value: "q"):
                break loop
            case .character(modifier: .none, value: "r"):
                player.reloadLyric()
                break
            case .resize(width: _, height: _):
                player.forceUpdate()
                break
            default:
                break
            }
        }
        player.stop()
        Termbox.shutdown()
    }
}

struct LyricsX: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "lyricsx-cli",
                                                    abstract: "LyricsX command line interface",
                                                    subcommands: [LyricsSearch.self, LyricsTick.self, LyricsPlay.self])
}
