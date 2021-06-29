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
            .debounce(for: 1, scheduler: queue)
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
        ignoreStatus(for: 1.5)
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
                self.lines = lrc.lines
                self.tick(tickPast: true, tickNext: self.player.playbackState.isPlaying)
            }
            .store(in: &tickCancelBag)
    }
    
    private func updateStatus(status: PlaybackState) {
        if ignoreStatus {
            return
        }
        cancelScheduledTick()
        if status.isPlaying {
            tick(tickPast: false)
        }
    }
    
    private func ignoreStatus(for time: TimeInterval) {
        ignoreStatus = true
        Just(())
            .delay(for: .seconds(time), scheduler: queue)
            .receive(on: queue)
            .sink { self.ignoreStatus = false }
            .store(in: &tickCancelBag)
    }
    
    private func cancelScheduledTick() {
        tickCancelBag.forEach { $0.cancel() }
        tickCancelBag = []
        ignoreStatus = false
    }
    
    private func tick(tickPast: Bool = true, tickNext: Bool = true) {
        guard let index = index(of: player.playbackTime) else {
            lines.forEach(onLine)
            return
        }
        if tickPast {
            lines.prefix(index).forEach(onLine)
        } else if index > 0 {
            onLine(lines[index - 1])
        }
        self.index = index
        if tickNext {
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
