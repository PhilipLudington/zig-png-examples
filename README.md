# zig-png-examples

An SDL3 desktop application demonstrating PNG decoding and encoding using the [zig-png](https://github.com/PhilipLudington/zig-png) library.

## Features

- Load and display PNG files in an SDL3 window
- Supports all PNG color types (grayscale, RGB, RGBA, indexed)
- Generate gradient images programmatically
- Save displayed images as PNG files

## Requirements

- Zig 0.15.0 or later

## Building

```bash
zig build
```

## Usage

Run with a default gradient:
```bash
zig build run
```

View a PNG file:
```bash
zig build run -- path/to/image.png
```

## Controls

| Key | Action |
|-----|--------|
| S | Save current image as `output.png` |
| G | Generate a new gradient image |
| Q / Escape | Quit |

## Dependencies

- [zig-png](https://github.com/PhilipLudington/zig-png) - Pure Zig PNG encoder/decoder
- [SDL3](https://github.com/castholm/SDL) - Cross-platform multimedia library
