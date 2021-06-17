import Foundation

#if os(Linux)

import playerctl

enum PlaybackState: Equatable, Hashable {
    case stopped
    case playing
    case paused
    
    public var isPlaying: Bool {
        switch self {
        case .playing:
            return true
        case .paused, .stopped:
            return false
        }
    }
}

public struct MusicTrack {
    
    public var id: String
    public var title: String?
    public var album: String?
    public var artist: String?
    public var duration: TimeInterval?
    public var fileURL: URL?
    
    public init(id: String, title: String?, album: String?, artist: String?, duration: TimeInterval? = nil, fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.album = album
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
    }
}

class EventLoop {
    
    static private(set) var loop: OpaquePointer? /* GMainLoop* */ = nil
    static private(set) var running = false
    
    static func start() {
        if !running {
            Thread.detachNewThread {
                Thread.current.name = "GMainLoop"
                loop = g_main_loop_new(g_main_context_get_thread_default(), 0)
                g_main_loop_run(loop)
            }
            running = true
        }
    }
    
    static func quit() {
        if running {
            g_main_loop_quit(loop)
        }
    }
}

func gproperty<T, R>(_ ptr: UnsafeMutablePointer<T>, name: String, transform: (UnsafeMutablePointer<GValue>) -> R) -> R {
    ptr.withMemoryRebound(to: GObject.self, capacity: 1) {
        var value = GValue()
        g_object_get_property($0, name, &value)
        return transform(&value)
    }
}

class MprisPlayer /*: MusicPlayer.MusicPlayerProtocol*/ {
    
    private let manager: UnsafeMutablePointer<PlayerctlPlayerManager> = playerctl_player_manager_new(nil)!
    
    private var player: UnsafeMutablePointer<PlayerctlPlayer>? {
        gproperty(manager, name: "players") {
            g_value_get_pointer($0)
        }.map { players in
            players.assumingMemoryBound(to: GList.self)
                .pointee.data.assumingMemoryBound(to: PlayerctlPlayer.self)
        }
    }
    
    init() {
        EventLoop.start()
        
        var playerNames: UnsafeMutablePointer<GList>? = playerctl_list_players(nil)
        while (playerNames != nil) {
            let playerName = playerNames!.pointee.data.assumingMemoryBound(to: PlayerctlPlayerName.self)
            let player = playerctl_player_new_from_name(playerName, nil)
            playerctl_player_manager_manage_player(manager, player)
            playerNames = playerNames!.pointee.next
        }
        
        
        let onNameAppeared: @convention(c) (UnsafeMutablePointer<PlayerctlPlayerManager>?,
                                            UnsafeMutablePointer<PlayerctlPlayerName>?,
                                            UnsafeMutableRawPointer?) -> Void
            = { manager, name, data in
                let self_ = data!.assumingMemoryBound(to: MprisPlayer.self).pointee
                let player = playerctl_player_new_from_name(name, nil)
                playerctl_player_manager_manage_player(self_.manager, player)
            }
        
        let onPlayerVanished: @convention(c) (UnsafeMutablePointer<PlayerctlPlayerManager>?,
                                              UnsafeMutablePointer<PlayerctlPlayer>?,
                                              UnsafeMutableRawPointer?) -> Void
            = { manager, player, data in
                // TODO: notify player removed
            }
        
        let pself = Unmanaged.passUnretained(self).toOpaque()
        g_signal_connect_data(manager, "name-appeared", unsafeBitCast(onNameAppeared, to: GCallback?.self), pself, nil, G_CONNECT_AFTER)
        g_signal_connect_data(manager, "player-vanished", unsafeBitCast(onPlayerVanished, to: GCallback?.self), pself, nil, G_CONNECT_AFTER)
    }
    
    var name: String? {
        player.flatMap { player in
            gproperty(player, name: "player-name") { val in
                g_value_get_pointer(val).map { name in
                    String(cString: name.assumingMemoryBound(to: CChar.self))
                }
            }
        }
    }
    
    var currentTrack: MusicTrack? {
        player.map { player in
            let title = playerctl_player_get_title(player, nil).map { String(cString: $0) }
            let artist = playerctl_player_get_artist(player, nil).map { String(cString: $0) }
            let album = playerctl_player_get_album(player, nil).map { String(cString: $0) }
            let duration = (metadata("mpris:length").flatMap { TimeInterval($0) } ?? 0) / 1_000_000
            return MusicTrack(id: metadata("mpris:trackid") ?? "",
                              title: title,
                              album: album,
                              artist: artist,
                              duration: duration,
                              fileURL: metadata("xesam:url").flatMap { URL(string: $0) })
        }
    }
    
    var playbackState: PlaybackState {
        player.map { player in
            gproperty(player, name: "playback-status") { val in
                switch PlayerctlPlaybackStatus(UInt32(g_value_get_enum(val))) {
                case PLAYERCTL_PLAYBACK_STATUS_PLAYING:
                    return .playing
                case PLAYERCTL_PLAYBACK_STATUS_PAUSED:
                    return .paused
                case PLAYERCTL_PLAYBACK_STATUS_STOPPED:
                    return .stopped
                default:
                    return .stopped
                }
            }
        } ?? .stopped
    }
    
    var playbackTime: TimeInterval {
        get {
            player.map { player in
                Double(playerctl_player_get_position(player, nil)) / 1_000_000.0
            } ?? 0
        }
        set {
            player.map { player in
                playerctl_player_set_position(player, Int(newValue * 1_000_000), nil)
            }
        }
    }
    
    func resume() {
        player.map { player in
            playerctl_player_play(player, nil)
        }
    }
    
    func pause() {
        player.map { player in
            playerctl_player_pause(player, nil)
        }
    }
    
    func playPause() {
        player.map { player in
            playerctl_player_play_pause(player, nil)
        }
    }
    
    func skipToNextItem() {
        player.map { player in
            playerctl_player_next(player, nil)
        }
    }
    
    func skipToPreviousItem() {
        player.map { player in
            playerctl_player_previous(player, nil)
        }
    }
    
    private func metadata(_ key: String) -> String? {
        player.flatMap { player in
            playerctl_player_print_metadata_prop(player, key, nil).map { String(cString: $0) }
        }
    }
}

#endif

#if os(macOS)
import MusicPlayer
#endif

struct Playing {
    
    #if os(macOS)
    private static var player = MusicPlayers.SystemMedia()!
    #endif
    
    #if os(Linux)
    private static var player = MprisPlayer()
    #endif
    
    static var track: MusicTrack? {
        return player.playbackState.isPlaying ? player.currentTrack : nil
    }
    
    static var position: Double {
        player.playbackTime
    }
}
