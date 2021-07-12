import LyricsService
import MusicPlayer
import Termbox

private let NO_CONTENT = "-"
private let UNKNOWN = "Unknown"
private let SPACE: Int32 = 2

class LyricPlayer {
    
    private let ticker: LyricTicker
    private let player: MusicPlayerProtocol
    
    private var lyric: Lyrics?
    
    init(player: MusicPlayerProtocol) {
        self.player = player
        self.ticker = LyricTicker(player: player)
        ticker.onTrack = { [unowned self] in updateTrack(track: $0) }
        ticker.onState = { [unowned self] in updateState(state: $0) }
        ticker.onLyrics = { [unowned self] in updateLyrics(lyric: $0) }
        ticker.onLine = { [unowned self] in updateLine(line: $0) }
        ticker.onSeek = { [unowned self] _, _ in updateLine(line: ticker.current) }
    }
    
    func start() {
        ticker.start()
    }
    
    func stop() {
        ticker.stop()
        Termbox.clear()
    }
    
    func forceUpdate() {
        updateTrack(track: player.currentTrack)
        updateLyrics(lyric: lyric)
    }
    
    func reloadLyric() {
        updateBottomBar(state: player.playbackState, source: "Reloading...")
        Termbox.present()
        ticker.updateLyric()
    }
    
    private func updateTrack(track: MusicTrack?) {
        if let track = track {
            updateTopBar(title: track.title ?? UNKNOWN, artist: track.artist, album: track.album)
        } else {
            updateTopBar(title: NO_CONTENT, artist: NO_CONTENT, album: NO_CONTENT)
        }
        clearLyricArea()
        Termbox.present()
    }
    
    private func updateState(state: PlaybackState) {
        updateLyrics(lyric: lyric)
    }
    
    private func updateLyrics(lyric: Lyrics?) {
        self.lyric = lyric
        let source: String
        if let lyric = lyric {
            source = lyric.metadata.service?.rawValue ?? UNKNOWN
        } else {
            source = NO_CONTENT
        }
        updateBottomBar(state: player.playbackState, source: source)
        updateLine(line: ticker.current)
        Termbox.present()
    }
    
    private func updateLine(line: LyricsLine?) {
        clearLyricArea()
        let middle = Termbox.height / 2
        if let line = line { printAt(x: SPACE, y: middle, text: line.content, foreground: .cyan) }
        for (line, pos) in zip(ticker.past.reversed(), (SPACE..<middle).reversed()) {
            printAt(x: SPACE, y: pos, text: line.content)
        }
        let peek = ticker.peek(Int(Termbox.height - middle))
        for (line, pos) in zip(peek, middle + 1..<Termbox.height - SPACE) {
            printAt(x: SPACE, y: pos, text: line.content)
        }
        Termbox.present()
    }
    
    private func clearTopBar() {
        for i in 0..<Termbox.width { Termbox.put(x: i, y: 0, character: " ", background: .white) }
    }
    
    private func clearBottomBar() {
        for i in 0..<Termbox.width { Termbox.put(x: i, y: Termbox.height - 1, character: " ", background: .white) }
    }
    
    private func clearLyricArea() {
        for i in 0..<Termbox.width {
            for j in 1..<Termbox.height - 1 {
                Termbox.put(x: i, y: j, character: " ")
            }
        }
    }
    
    private func updateTopBar(title: String, artist: String?, album: String?) {
        clearTopBar()
        var bar = "Title: \(title)"
        if let artist = artist { bar += " | Artist: \(artist)" }
        if let album = album { bar += " | Album: \(album)" }
        printAt(x: SPACE, y: 0, text: bar, foreground: .black, background: .white)
    }
    
    private func updateBottomBar(state: PlaybackState, source: String) {
        clearBottomBar()
        let status: String = {
            switch state {
            case .playing: return "Playing"
            case .paused: return "Paused"
            case .stopped: return "Stopped"
            default: return "Stopped"
            }
        }()
        let bar = "State: \(status) | Lyric Source: \(source) | Press Q to quit, R to reload a lyric"
        printAt(x: SPACE, y: Termbox.height - 1, text: bar, foreground: .black, background: .white)
    }
}

func printAt(x: Int32, y: Int32, text: String, foreground: Attributes = .default, background: Attributes = .default) {
    for (c, xi) in zip(text.unicodeScalars, x ..< Termbox.width) {
        Termbox.put(x: xi, y: y, character: c, foreground: foreground, background: background)
    }
}
