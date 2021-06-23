import Foundation
import LyricsService
import CXShim
import CXExtensions
import MusicPlayer
import Dispatch

class LyricTicker {
    
    private static var id = 0
    
    let player: MusicPlayerProtocol
    let onLine: (LyricsLine) -> Void
    
    var lines: [LyricsLine] = []
    var index = 0
    var track: MusicTrack?
    
    let queue = DispatchQueue(label: "LyricTicker\(LyricTicker.id)").cx
    var scheduledTick: DispatchWorkItem?
    var scheduledCheck: DispatchWorkItem?
    var cancelBag: [AnyCancellable] = []
    
    init(player: MusicPlayerProtocol, onLine: @escaping (LyricsLine) -> Void) {
        self.player = player
        self.onLine = onLine
    }
    
    deinit {
        stop()
    }
    
    func start() {
        checkTrack()
        scheduleCheck()
    }
    
    func stop() {
        cancelBag.forEach { $0.cancel() }
        cancelBag = []
        cancel(&scheduledTick)
        cancel(&scheduledCheck)
    }
    
    private func cancel(_ item: inout DispatchWorkItem?) {
        item?.cancel()
        item = nil
    }
    
    private func updateTrack(track: MusicTrack?) {
        cancel(&scheduledTick)
        self.track = track
        
        guard let track = track else {
            return
        }
        let (title, artist, album) = (track.title ?? "", track.artist ?? "", track.album ?? "")
        print("\nPlaying:")
        print("Title: \(title)\nArtist: \(artist)\nAlbum: \(album)\n")
        lyricOf(title: title, artist: artist)
            .receive(on: queue)
            .sink { lyric in
                guard let lrc = lyric else {
                    print("No lyrics found.")
                    return
                }
                print("Matched:")
                print("Source: \(lrc.metadata.service?.rawValue ?? "")\n")
                self.lines = lrc.lines
                self.tick(tickPast: true)
            }
            .store(in: &cancelBag)
    }
    
    private func updatePosition() {
        cancel(&scheduledTick)
        tick(tickPast: false)
    }
    
    private func tick(tickPast: Bool = true) {
        guard let index = index(of: player.playbackTime) else {
            for line in lines {
                onLine(line)
            }
            return
        }
        if tickPast {
            lines.prefix(index).forEach { line in
                onLine(line)
            }
        } else if index > 0 {
            onLine(lines[index - 1])
        }
        self.index = index
        scheduleTick()
    }
    
    private func schedule(after timeInterval: TimeInterval, action: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: action)
        queue.base.asyncAfter(deadline: .now() + timeInterval, execute: item)
        return item
    }
    
    private func scheduleTick() {
        if index == lines.count {
            return
        }
        let line = lines[index]
        scheduledTick = schedule(after: line.position - player.playbackTime) {
            self.onLine(line)
            self.index += 1
            self.scheduleTick()
        }
    }
    
    private func scheduleCheck() {
        scheduledCheck = schedule(after: 1) {
            self.checkTrack()
            self.scheduleCheck()
        }
    }
    
    private func checkTrack() {
        let track = player.playbackState.isPlaying ? player.currentTrack : nil
        if self.track?.id != track?.id {
            updateTrack(track: track)
            return
        }
        if track == nil {
            return
        }
        let pos = player.playbackTime
        if index > 0 && index <= lines.count {
            let prev = lines[index - 1]
            if pos < prev.position {
                updatePosition()
                return
            }
        }
        if index == lines.count {
            return
        }
        let line = lines[index]
        if pos > line.position {
            updatePosition()
        }
    }
    
    private func index(of offset: TimeInterval) -> Int? {
        lines.firstIndex { $0.position > offset }
    }
    
    private func lyricOf(title: String, artist: String) -> AnyPublisher<Lyrics?, Never> {
        let req = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist),
                                      title: title, artist: artist, duration: 0)
        return LyricsProviders.Group()
            .lyricsPublisher(request: req)
            .collect(3)
            .first()
            .map { $0.sorted { $1.quality < $0.quality }.first }
            .eraseToAnyPublisher()
    }
}
