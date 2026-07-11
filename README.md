# Codex Media Converter

A native macOS drag-and-drop converter for video, audio, and photos. It bundles
Apple Silicon builds of FFmpeg and FFprobe into the installed app, so it is standalone.

## Conversions

- Video to video, extracted audio, still photo, or animated GIF
- Audio to audio, waveform video, waveform photo, or waveform GIF
- Photo to photo, five-second video, or five-second silent audio
- Separate tutorial speed-up workflow from 1.25x to 10x; exports MP4 and always removes audio
- Batch queue, progress, cancellation, collision-safe filenames, and Finder reveal

Outputs default to `~/Movies/Codex Conversions`.

## Quick launcher

Double-click `Codex Media Converter.command`, choose files, then choose either
Format Conversion or the separate Speed Up Tutorial workflow. The first launch
downloads FFmpeg automatically if needed.

Speed Up Tutorial accepts video, supports 1.25x through 10x, exports MP4, and
always removes the complete audio track.

## Build and run

```bash
./script/install_ffmpeg.sh
./script/build_and_run.sh
```

The app bundle is staged at `dist/Codex Media Converter.app`.
