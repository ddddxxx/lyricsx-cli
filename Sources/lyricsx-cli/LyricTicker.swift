import Foundation
import LyricsService
import CXShim
import CXExtensions
import MusicPlayer
import Dispatch

class LyricTicker {
    
    private static var id = 0
    
    private let player: MusicPlayerProtocol
    
    var onTrack: ((MusicTrack?) -> Void)?
    var onLyrics: ((Lyrics?) -> Void)?
    var onLine: ((LyricsLine) -> Void)?
    var onSeek: ((Int, Int) -> Void)?
    var onState: ((PlaybackState) -> Void)?
    
    private(set) var lines: [LyricsLine] = []
    private(set) var index = -1
    
    private let queue = DispatchQueue(label: "LyricTicker\(LyricTicker.id)").cx
    private var eventCancelBag: [AnyCancellable] = []
    private var tickCancelBag: [AnyCancellable] = []
    private var ignoreStatus = false
    
    init(player: MusicPlayerProtocol) { self.player = player }
    
    deinit { stop() }
    
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
    
    var size: Int { lines.count }
    
    var current: LyricsLine? { index >= 0 && index < lines.count ? lines[index] : nil }
    
    var past: ArraySlice<LyricsLine> { lines.prefix(max(0, index)) }
    
    func peek(_ count: Int) -> ArraySlice<LyricsLine> {
        assert(count >= 0)
        return lines.dropFirst(index + 1).prefix(count)
    }
    
    func updateLyric() { updateLyric(track: player.currentTrack) }
    
    private func updateTrack(track: MusicTrack?) {
        cancelScheduledTick()
        ignoreStatus = true
        index = -1
        lines = []
        onTrack?(track)
        updateLyric(track: track)
    }
    
    private func updateLyric(track: MusicTrack?) {
        guard let track = track else {
            onReceiveLyric(lyric: nil)
            return
        }
        lyricOf(title: track.title ?? "", artist: track.artist ?? "")
            .receive(on: queue)
            .sink(receiveValue: onReceiveLyric)
            .store(in: &tickCancelBag)
    }
    
    private func onReceiveLyric(lyric: Lyrics?) {
        cancelScheduledTick()
        ignoreStatus = false
        if let lyric = lyric {
            lines = lyric.lines
        }
        onLyrics?(lyric)
        tick()
    }
    
    private func updateStatus(status: PlaybackState) {
        onState?(status)
        if ignoreStatus { return }
        cancelScheduledTick()
        if status.isPlaying { tick() }
    }
    
    private func cancelScheduledTick() {
        tickCancelBag.forEach { $0.cancel() }
        tickCancelBag = []
    }
    
    private func tick() {
        if lines.isEmpty { return }
        let index = index(of: player.playbackTime)
        if self.index != index {
            let old = self.index
            self.index = index
            onSeek?(old, index)
        }
        if player.playbackState.isPlaying { scheduleTick() }
    }
    
    private func scheduleTick() {
        if index + 1 >= lines.count { return }
        let line = lines[index + 1]
        Just(line)
            .delay(for: .seconds(line.position - player.playbackTime), scheduler: queue)
            .receive(on: queue)
            .sink {
                self.index += 1
                self.onLine?($0)
                self.scheduleTick()
            }
            .store(in: &tickCancelBag)
    }
    
    private func index(of offset: TimeInterval) -> Int {
        (lines.firstIndex { $0.position > offset } ?? lines.count) - 1
    }
    
    private func lyricOf(title: String, artist: String) -> AnyPublisher<Lyrics?, Never> {
        let req = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist),
                                      title: title, artist: artist, duration: 0)
        return LyricsProviders.Group()
            .lyricsPublisher(request: req)
            .collect(3)
            .first()
            .map { $0.sorted { $1.quality < $0.quality }.first }
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}
