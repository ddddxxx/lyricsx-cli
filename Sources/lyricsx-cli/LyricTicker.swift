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
    
    let queue = DispatchQueue(label: "LyricTicker\(LyricTicker.id)").cx
    var scheduledTick: DispatchWorkItem?
    var cancelBag: [AnyCancellable] = []
    
    init(player: MusicPlayerProtocol, onLine: @escaping (LyricsLine) -> Void) {
        self.player = player
        self.onLine = onLine
    }
    
    deinit {
        stop()
    }
    
    func start() {
        player.currentTrackWillChange
            .receive(on: queue)
            .sink(receiveValue: updateTrack)
            .store(in: &cancelBag)
        player.playbackStateWillChange
            .receive(on: queue)
            .sink(receiveValue: updateStatus)
            .store(in: &cancelBag)
        updateTrack(track: player.currentTrack)
    }
    
    func stop() {
        cancelBag.forEach { $0.cancel() }
        cancelBag = []
        cancelScheduledTick()
    }
    
    private func updateTrack(track: MusicTrack?) {
        cancelScheduledTick()
        guard let track = track else {
            return
        }
        let (title, artist, album) = (track.title ?? "", track.artist ?? "", track.album ?? "")
        print("\nPlaying:")
        print("Title: \(title)\nArtist: \(artist)\nAlbum: \(album)\n")
        lyricOf(title: title, artist: artist)
            .receive(on: queue)
            .sink { lyric in
                if let lrc = lyric {
                    print("Matched:")
                    print("Source: \(lrc.metadata.service?.rawValue ?? "")\n")
                    self.lines = lrc.lines
                    self.tick(tickPast: true, tickNext: self.player.playbackState.isPlaying)
                } else {
                    print("No lyrics found.")
                }
            }
            .store(in: &cancelBag)
    }
    
    private func updateStatus(status: PlaybackState) {
        cancelScheduledTick()
        if status.isPlaying {
            tick(tickPast: false)
        }
    }
    
    private func cancelScheduledTick() {
        if let item = scheduledTick {
            item.cancel()
            scheduledTick = nil
        }
    }
    
    private func tick(tickPast: Bool = true, tickNext: Bool = true) {
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
        if tickNext {
            scheduleTick()
        }
    }
    
    private func scheduleTick() {
        if index == lines.count {
            return
        }
        let line = lines[index]
        let item = DispatchWorkItem {
            self.onLine(line)
            self.index += 1
            self.scheduleTick()
        }
        queue.base.asyncAfter(deadline: .now() + (line.position - player.playbackTime), execute: item)
        scheduledTick = item
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
