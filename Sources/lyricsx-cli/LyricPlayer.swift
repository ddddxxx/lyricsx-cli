import LyricsService
import MusicPlayer
import Termbox

private let NO_CONTENT = "-"
private let UNKNOWN = "Unknown"
private let SPACE: Int32 = 2

class LyricPlayer {
    
    private let ticker: LyricTicker
    private let player: MusicPlayerProtocol
    private let foreground: Attributes
    
    private var lyric: Lyrics?
    
    init(player: MusicPlayerProtocol, foreground: Attributes) {
        self.player = player
        self.ticker = LyricTicker(player: player)
        self.foreground = foreground
        ticker.onTrack = { [unowned self] in
            updateTopBar(track: $0)
            clearLyricArea()
            updateBottomBar(lyric: nil)
            Termbox.present()
        }
        ticker.onState = { [unowned self] _ in
            updateBottomBar(lyric: lyric)
            Termbox.present()
        }
        ticker.onLyrics = { [unowned self] in
            updateLyricArea(current: ticker.current)
            updateBottomBar(lyric: $0)
            Termbox.present()
        }
        ticker.onLine = { [unowned self] in
            updateLyricArea(current: $0)
            Termbox.present()
        }
        ticker.onSeek = { [unowned self] _, _ in
            updateLyricArea(current: ticker.current)
            Termbox.present()
        }
    }
    
    func start() {
        ticker.start()
    }
    
    func stop() {
        ticker.stop()
        Termbox.clear()
    }
    
    func forceUpdate() {
        updateTopBar(track: player.currentTrack)
        updateLyricArea(current: ticker.current)
        updateBottomBar(lyric: lyric)
        Termbox.present()
    }
    
    func reloadLyric() {
        updateBottomBar(state: player.playbackState, source: "Reloading...")
        Termbox.present()
        ticker.updateLyric()
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
    
    private func updateTopBar(track: MusicTrack?) {
        if let track = track {
            updateTopBar(title: track.title ?? UNKNOWN, artist: track.artist, album: track.album)
        } else {
            updateTopBar(title: NO_CONTENT, artist: NO_CONTENT, album: NO_CONTENT)
        }
    }
    
    private func updateTopBar(title: String, artist: String?, album: String?) {
        clearTopBar()
        var bar = "Title: \(title)"
        if let artist = artist { bar += " | Artist: \(artist)" }
        if let album = album { bar += " | Album: \(album)" }
        printAt(x: SPACE, y: 0, text: bar, foreground: .black, background: .white)
    }
    
    private func updateBottomBar(lyric: Lyrics?) {
        self.lyric = lyric
        let source: String
        if let lyric = lyric {
            source = lyric.metadata.service?.rawValue ?? UNKNOWN
        } else {
            source = NO_CONTENT
        }
        updateBottomBar(state: player.playbackState, source: source)
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
    
    private func updateLyricArea(current: LyricsLine?) {
        clearLyricArea()
        let middle = Termbox.height / 2
        if let line = current { printAt(x: SPACE, y: middle, text: line.content, foreground: foreground) }
        for (line, pos) in zip(ticker.past.reversed(), (SPACE..<middle).reversed()) {
            printAt(x: SPACE, y: pos, text: line.content)
        }
        let peek = ticker.peek(Int(Termbox.height - middle))
        for (line, pos) in zip(peek, middle + 1..<Termbox.height - SPACE) {
            printAt(x: SPACE, y: pos, text: line.content)
        }
    }
}

func printAt(x: Int32, y: Int32, text: String, foreground: Attributes = .default, background: Attributes = .default) {
    for (c, xi) in zip(text.unicodeScalars, x ..< Termbox.width) {
        Termbox.put(x: xi, y: y, character: c, foreground: foreground, background: background)
    }
}
