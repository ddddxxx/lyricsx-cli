import Foundation
import CoreFoundation
import LyricsService

#if os(macOS)
import MusicPlayer
#endif

class LyricTicker {
    let onLine: (LyricsLine) -> Void
    
    var lines: [LyricsLine] = []
    var index = 0
    var playing: (title: String, artist: String)?
    var tickLoop: RunLoop! = nil
    var scheduledTick: Timer? = nil
    
    init(onLine: @escaping (LyricsLine) -> Void) {
        self.onLine = onLine
        Thread.detachNewThread {
            Thread.current.name = "LyricTicker"
            self.tickLoop = RunLoop.current
            self.tickLoop.run(mode: .default, before: .distantFuture)
        }
    }
    
    deinit {
        CFRunLoopStop(tickLoop.getCFRunLoop())
    }
    
    func run() {
        scheduleCheck()
        RunLoop.main.run(mode: .default, before: .distantFuture)
    }
    
    private func changeTrack(_ track: MusicTrack) {
        let (title, artist, album) = (track.title ?? "", track.artist ?? "", track.album ?? "")
        playing = (title, artist)
        print("\nPlaying:")
        print("Title: \(title)\nArtist: \(artist)\nAlbum: \(album)\n")
        guard let lrc = lyricOf(title: title, artist: artist) else {
            print("No lyrics found.")
            return
        }
        print("Matched:")
        print("Source: \(lrc.metadata.service?.rawValue ?? "")\n")
        lines = lrc.lines
        tick()
    }
    
    @discardableResult private func scheduleOn(_ loop: RunLoop, after timeInterval: TimeInterval, action: @escaping () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
            action()
        }
        loop.add(timer, forMode: .default)
        return timer
    }
    
    private func doOnTrackDetected(_ onTrack: @escaping (MusicTrack) -> Void) {
        if let track = Playing.track {
            onTrack(track)
            return
        }
        scheduleOn(RunLoop.main, after: 1) {
            self.doOnTrackDetected(onTrack)
        }
    }
    
    private func tick(tickPast: Bool = true) {
        guard let index = index(of: Playing.position) else {
            for line in lines {
                onLine(line)
            }
            return
        }
        if tickPast {
            for line in lines[0..<index] {
                onLine(line)
            }
        } else if index > 0 {
            onLine(lines[index - 1])
        }
        self.index = index
        scheduleTick()
    }
    
    private func scheduleCheck() {
        scheduleOn(RunLoop.main, after: 1) {
            self.checkTrack()
        }
    }
    
    private func scheduleTick() {
        let index = index
        if index == lines.count {
            return
        }
        let line = lines[index]
        scheduledTick = scheduleOn(tickLoop, after: line.position - Playing.position) {
            self.onLine(line)
            self.index += 1
            self.scheduleTick()
        }
    }
    
    private func cancelScheduledTick() {
        if let scheduledTick = scheduledTick {
            scheduledTick.invalidate()
        }
    }
    
    private func checkTrack() {
        if let track = Playing.track {
            if let playing = playing, playing == (track.title, track.artist) {
                correctPosition()
            } else {
                cancelScheduledTick()
                changeTrack(track)
            }
            scheduleCheck()
        } else {
            cancelScheduledTick()
            doOnTrackDetected { track in
                if let playing = self.playing, playing == (track.title, track.artist) {
                    self.tick(tickPast: false)
                } else {
                    self.changeTrack(track)
                }
                self.scheduleCheck()
            }
        }
    }
    
    private func correctPosition() {
        let index = index
        let pos = Playing.position
        if index > 0 && index <= lines.count {
            let prev = lines[index - 1]
            if pos < prev.position {
                cancelScheduledTick()
                tick(tickPast: false)
                return
            }
        }
        if index == lines.count {
            return
        }
        let line = lines[index]
        if pos > line.position {
            cancelScheduledTick()
            tick(tickPast: false)
        }
    }
    
    private func index(of offset: TimeInterval) -> Int? {
        lines.firstIndex { $0.position > offset }
    }
    
    private func lyricOf(title: String, artist: String) -> Lyrics? {
        let req = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist),
                                      title: title, artist: artist, duration: 0)
        let provider = LyricsProviders.Group()
        return provider.lyricsPublisher(request: req)
            .collect(3).blocking().next()?.sorted { $1.quality < $0.quality }.first
    }
}
