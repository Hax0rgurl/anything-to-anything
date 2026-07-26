# Anything to Anything

A native macOS drag-and-drop converter for video, audio, photos, and documents.
It bundles Apple Silicon builds of FFmpeg and FFprobe into the installed app, so
media conversion is standalone. Document conversion uses macOS-native
`textutil`, PDFKit, and WebKit.

## Conversions

- Video to video, extracted audio, still photo, or animated GIF
- Audio to audio, waveform video, waveform photo, or waveform GIF
- Photo to photo, five-second video, or five-second silent audio
- Documents between TXT, Markdown, HTML, RTF, DOC, DOCX, ODT, and PDF
- PDF text extraction to editable formats
- HTML, plain text, Markdown, Word, RTF, and ODT rendering to PDF
- Separate tutorial speed-up workflow from 1.25x to 10x; exports MP4 and always removes audio
- Batch queue, progress, cancellation, collision-safe filenames, and Finder reveal

Outputs default to `~/Movies/Anything to Anything`.

Document and media formats stay in their own lanes: document-to-document and
media-to-media conversions are supported, while document-to-video (and similar
cross-category routes) are intentionally rejected. Complex page layout may be
simplified. Image-only scanned PDFs require OCR and will report that limitation
instead of creating an empty document.

## Quick launcher

Double-click `Anything to Anything.command`, choose files, then choose either
Format Conversion or the separate Speed Up Tutorial workflow. The first launch
downloads FFmpeg automatically if needed.

Speed Up Tutorial accepts video, supports 1.25x through 10x, exports MP4, and
always removes the complete audio track.

## Build and run

```bash
./script/install_ffmpeg.sh
./script/build_and_run.sh
```

The app bundle is staged at `dist/Anything to Anything.app`.
