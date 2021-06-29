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
    var eventCancelBag: [AnyCancellable] = []
    var tickCancelBag: [AnyCancellable] = []
    var ignoreStatus = false
    
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
            .store(in: &eventCancelBag)
        player.playbackStateWillChange
            .debounce(for: 0.5, scheduler: queue)
            .receive(on: queue)
            .sink(receiveValue: updateStatus)
            .store(in: &eventCancelBag)
    }
    
    func stop() {
        cancelScheduledTick()
        eventCancelBag.forEach { $0.cancel() }
        eventCancelBag = []
    }
    
    private func updateTrack(track: MusicTrack?) {
        cancelScheduledTick()
        ignoreStatus = true
        guard let track = track else {
            return
        }
        let (title, artist, album) = (track.title ?? "", track.artist ?? "", track.album ?? "")
        print("\nPlaying:")
        print("Title: \(title)\nArtist: \(artist)\nAlbum: \(album)\n")
        
        lyricOf(title: title, artist: artist)
            .receive(on: queue)
            .sink { lrc in
                guard let lrc = lrc else {
                    print("No lyrics found.")
                    return
                }
                print("Matched:")
                print("Source: \(lrc.metadata.service?.rawValue ?? "")\n")
                self.ignoreStatus = false
                self.lines = lrc.lines
                self.index = 0
                self.tick()
            }
            .store(in: &tickCancelBag)
    }
    
    private func updateStatus(status: PlaybackState) {
        if ignoreStatus {
            return
        }
        cancelScheduledTick()
        if status.isPlaying {
            tick()
        }
    }
    
    private func cancelScheduledTick() {
        tickCancelBag.forEach { $0.cancel() }
        tickCancelBag = []
    }
    
    private func tick() {
        guard let index = index(of: player.playbackTime) else {
            lines.forEach(onLine)
            return
        }
        if index > self.index {
            lines.prefix(index).dropFirst(self.index).forEach(onLine)
        } else if index < self.index && index > 0 {
            onLine(lines[index - 1])
        }
        self.index = index
        if player.playbackState.isPlaying {
            scheduleTick()
        }
    }
    
    private func scheduleTick() {
        if index >= lines.count {
            return
        }
        let line = lines[index]
        Just(line)
            .delay(for: .seconds(line.position - player.playbackTime), scheduler: queue)
            .receive(on: queue)
            .sink {
                self.onLine($0)
                self.index += 1
                self.scheduleTick()
            }
            .store(in: &tickCancelBag)
    }
    
    private func index(of offset: TimeInterval) -> Int? {
        lines.firstIndex { $0.position > offset }
    }
    
    private func lyricOf(title: String, artist: String) -> AnyPublisher<Lyrics?, Never> {
        let req = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist),
                                      title: title, artist: artist, duration: 0)
        return LyricsProviders.Group()
            .lyricsPublisher(request: req)
            .collect(2)
            .first()
            .map { $0.sorted { $1.quality < $0.quality }.first }
            .eraseToAnyPublisher()
    }
}
