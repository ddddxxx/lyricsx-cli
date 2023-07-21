import CXShim
import Dispatch
import Foundation
import LyricsService
import MusicPlayer
import Termbox

private let NO_CONTENT = "-"
private let UNKNOWN = "Unknown"
private let SPACE: Int32 = 2

func printAt(
    x: Int32, y: Int32, text: String, foreground: Attributes = .default,
    background: Attributes = .default
) {
    for (c, xi) in zip(text.unicodeScalars, x..<Termbox.width) {
        Termbox.put(x: xi, y: y, character: c, foreground: foreground, background: background)
    }
}

func clearTopBar() {
    for i in 0..<Termbox.width {
        Termbox.put(x: i, y: 0, character: " ", background: .white)
    }
}

func clearBottomBar() {
    for i in 0..<Termbox.width {
        Termbox.put(x: i, y: Termbox.height - 1, character: " ", background: .white)
    }
}

func clearLyricArea() {
    for i in 0..<Termbox.width {
        for j in 1..<Termbox.height - 1 {
            Termbox.put(x: i, y: j, character: " ")
        }
    }
}

func updateTopBar(track: MusicTrack?) {
    if let track = track {
        updateTopBar(title: track.title ?? UNKNOWN, artist: track.artist, album: track.album)
    } else {
        updateTopBar(title: NO_CONTENT, artist: NO_CONTENT, album: NO_CONTENT)
    }
}

func updateTopBar(title: String, artist: String?, album: String?) {
    clearTopBar()
    var bar = "Title: \(title)"
    if let artist = artist { bar += " | Artist: \(artist)" }
    if let album = album { bar += " | Album: \(album)" }
    printAt(x: SPACE, y: 0, text: bar, foreground: .black, background: .white)
}

func updateBottomBar(state: PlaybackState, lyric: Lyrics?) {
    let source: String
    if let lyric = lyric {
        source = lyric.metadata.service?.rawValue ?? UNKNOWN
    } else {
        source = NO_CONTENT
    }
    updateBottomBar(state: state, source: source)
}

func updateBottomBar(state: PlaybackState, source: String) {
    clearBottomBar()
    let status: String = {
        switch state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        default: return "Stopped"
        }
    }()
    let bar = "State: \(status) | Lyric Source: \(source)"
    printAt(x: SPACE, y: Termbox.height - 1, text: bar, foreground: .black, background: .white)
}

func updateLyricArea(lines: [LyricsLine], index: Int, foreground: Attributes) {
    clearLyricArea()
    let middle = Termbox.height / 2
    if lines.indices.contains(index) {
        printAt(x: SPACE, y: middle, text: lines[index].content, foreground: foreground)
    }
    for (line, pos) in zip(lines.prefix(max(index, 0)).reversed(), (SPACE..<middle).reversed()) {
        printAt(x: SPACE, y: pos, text: line.content)
    }
    for (line, pos) in zip(lines.dropFirst(index + 1), middle + 1..<Termbox.height - SPACE) {
        printAt(x: SPACE, y: pos, text: line.content)
    }
}

func terminalEvents(on queue: DispatchQueue) -> some Publisher<Event, Never> {
    let publisher = PassthroughSubject<Event, Never>()
    var active = true
    func publish() {
        if let event = Termbox.pollEvent(), active {
            publisher.send(event)
        }
        if active { queue.async { publish() } }
    }
    return publisher.handleEvents(
        receiveSubscription: { _ in queue.async { publish() } },
        receiveCancel: { active = false })
}

func play(foreground: Attributes) {
    guard let player = CurrentPlayer() else {
        fatalError("Unable to connect to the music player.")
    }
    do { try Termbox.initialize() } catch {
        fatalError("\(error)")
    }

    var cancelBag = [AnyCancellable]()
    let currentLyrics = CurrentValueSubject<Lyrics?, Never>(nil)
    var currentIndex = -1

    currentLyrics
        .combineLatest(player.playbackStateWillChange.prepend(.stopped))
        .map { lyrics, state in
            updateBottomBar(state: state, lyric: lyrics)
            if let lyrics = lyrics {
                currentIndex = index(of: state.time, of: lyrics.lines) - 1
                updateLyricArea(lines: lyrics.lines, index: currentIndex, foreground: foreground)
                if state.isPlaying {
                    Termbox.present()
                    return timedIndices(of: lyrics.lines, on: .main, with: player)
                        .eraseToAnyPublisher()
                }
            } else {
                currentIndex = -1
            }
            Termbox.present()
            return Empty().eraseToAnyPublisher()
        }
        .switchToLatest()
        .receive(on: DispatchQueue.main.cx)
        .sink { index in
            currentIndex = index
            guard let lyrics = currentLyrics.value else { return }
            updateLyricArea(lines: lyrics.lines, index: index, foreground: foreground)
            Termbox.present()
        }
        .store(in: &cancelBag)

    player.currentTrackWillChange
        .prepend(nil)
        .handleEvents(receiveOutput: { track in
            updateTopBar(track: track)
            clearLyricArea()
            updateBottomBar(state: player.playbackState, lyric: nil)
            Termbox.present()
        })
        .flatMap { track in
            track.map {
                lyrics(of: $0).map(Optional.some).prepend(nil).eraseToAnyPublisher()
            } ?? Just(nil).eraseToAnyPublisher()
        }
        .sink { currentLyrics.send($0) }
        .store(in: &cancelBag)

    let reloadLyrics = {
        guard let track = player.currentTrack else { return }
        updateBottomBar(state: player.playbackState, source: "Loading...")
        Termbox.present()
        lyrics(of: track)
            .handleEvents(receiveCompletion: { _ in
                updateBottomBar(state: player.playbackState, lyric: currentLyrics.value)
                Termbox.present()
            })
            .sink { currentLyrics.send($0) }
            .store(in: &cancelBag)
    }

    let forceUpdate = {
        updateTopBar(track: player.currentTrack)
        if let lyrics = currentLyrics.value {
            updateLyricArea(lines: lyrics.lines, index: currentIndex, foreground: foreground)
        } else {
            clearLyricArea()
        }
        updateBottomBar(state: player.playbackState, lyric: currentLyrics.value)
        Termbox.present()
    }

    terminalEvents(on: DispatchQueue(label: "TerminalEvents"))
        .receive(on: DispatchQueue.main.cx)
        .sink { event in
            switch event {
            case .character(modifier: .none, value: "q"):
                cancelBag = []
                Termbox.shutdown()
                exit(0)
                break
            case .character(modifier: .none, value: "r"):
                reloadLyrics()
                break
            case .resize(width: _, height: _):
                forceUpdate()
                break
            case .key(modifier: .none, value: .space):
                player.playPause()
                break
            case .character(modifier: .none, value: ","):
                player.skipToPreviousItem()
                break
            case .character(modifier: .none, value: "."):
                player.skipToNextItem()
                break
            default:
                break
            }
        }
        .store(in: &cancelBag)

    #if os(Linux)
        Thread.detachNewThread {
            Thread.current.name = "GMainLoop"
            GRunLoop.main.run()
        }
    #endif
    RunLoop.main.run()

    Termbox.shutdown()
}
