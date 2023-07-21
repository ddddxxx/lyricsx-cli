# lyricsx-cli

[![GitHub CI](https://github.com/ddddxxx/lyricsx-cli/workflows/CI/badge.svg)](https://github.com/ddddxxx/lyricsx-cli/actions)

[LyricsX](https://github.com/ddddxxx/LyricsX) cross platform command line interface.

## Dependences

### macOS

No additional dependencies required.

### Linux

- [playerctl](https://github.com/altdesktop/playerctl)

## Usage

### Search

```
$ lyricsx-cli search <keyword>
```

### Tick

```
$ lyricsx-cli tick
```

### Play

```
$ lyricsx-cli play [--color <color>] [--no-bold]
```

#### Keyboard actions

| KEY       | ACTION          |
|-----------|-----------------|
| `[Q]`     | *Q*uit          |
| `[R]`     | *R*eload lyrics |
| `[space]` | Play or pause   |
| `[,]`     | Previous track  |
| `[.]`     | Next track      |


#### Snapshots

![play.png](.assets/play.png)
