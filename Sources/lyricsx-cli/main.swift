import ArgumentParser
import LyricsService
import CXExtensions

struct LyricsX: ParsableCommand {
    
    static var configuration = CommandConfiguration(commandName: "lyricsx-cli", abstract: "LyricsX command line interface", subcommands: [LyricsSearch.self])
}

LyricsX.main()
