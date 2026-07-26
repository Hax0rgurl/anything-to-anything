#!/bin/zsh
set -u
setopt NULL_GLOB

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="${CODEX_MEDIA_OUTPUT_DIR:-$HOME/Movies/Anything to Anything}"

find_ffmpeg() {
  local candidates=(
    "$SCRIPT_DIR/AnythingToAnything/vendor/ffmpeg"
    "$SCRIPT_DIR/vendor/ffmpeg"
    "$SCRIPT_DIR/ffmpeg"
    "$HOME/.local/bin/ffmpeg"
    "/opt/homebrew/bin/ffmpeg"
    "/usr/local/bin/ffmpeg"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  if command -v ffmpeg >/dev/null 2>&1; then
    command -v ffmpeg
    return 0
  fi
  return 1
}

media_kind() {
  local ext="${1:e:l}"
  case "$ext" in
    mp4|mov|m4v|mkv|webm|avi|wmv|flv|mpeg|mpg|mts|m2ts|3gp) print video ;;
    mp3|m4a|aac|wav|flac|ogg|oga|opus|aiff|aif|wma|ac3) print audio ;;
    jpg|jpeg|png|webp|heic|heif|tif|tiff|bmp|gif|avif) print image ;;
    *) print unknown ;;
  esac
}

target_kind() {
  case "$1" in
    mp4|mov|webm|mkv) print video ;;
    mp3|m4a|wav|flac|ogg|opus) print audio ;;
    jpg|png|webp|tiff|gif) print image ;;
  esac
}

unique_output() {
  local source="$1" format="$2" label="${3:-}"
  local stem="${source:t:r}"
  local candidate="$OUTPUT_DIR/$stem$label.$format"
  local number=2
  while [[ -e "$candidate" ]]; do
    candidate="$OUTPUT_DIR/$stem$label $number.$format"
    (( number++ ))
  done
  print -r -- "$candidate"
}

pause_and_exit() {
  print
  read "REPLY?Press Return to close…"
  exit "${1:-0}"
}

clear
print "╭──────────────────────────────────────╮"
print "│      ANYTHING TO ANYTHING            │"
print "│  video • audio • photo • any way     │"
print "╰──────────────────────────────────────╯"
print

if ! FFMPEG="$(find_ffmpeg)"; then
  if [[ -x "$SCRIPT_DIR/script/install_ffmpeg.sh" ]]; then
    print "FFmpeg is not installed yet. Downloading it once…"
    "$SCRIPT_DIR/script/install_ffmpeg.sh" || pause_and_exit 1
    FFMPEG="$(find_ffmpeg)" || pause_and_exit 1
  else
    print "FFmpeg was not found. Keep this launcher inside the AnythingToAnything folder."
    pause_and_exit 1
  fi
fi

typeset -a FILES
FILES=("$@")

if (( ${#FILES[@]} == 0 )); then
  print "Choose one or more media files…"
  selection="$(osascript <<'APPLESCRIPT' 2>/dev/null
try
  set pickedFiles to choose file with prompt "Choose video, audio, or photo files" with multiple selections allowed
  set output to ""
  repeat with pickedFile in pickedFiles
    set output to output & POSIX path of pickedFile & linefeed
  end repeat
  return output
on error number -128
  return ""
end try
APPLESCRIPT
)"
  while IFS= read -r path; do
    [[ -n "$path" ]] && FILES+=("$path")
  done <<< "$selection"
fi

if (( ${#FILES[@]} == 0 )); then
  print "No files selected."
  pause_and_exit 0
fi

print "Selected ${#FILES[@]} file(s). Choose a separate workflow:"
print
print "  1) Format Conversion"
print "  2) Speed Up Tutorial (MP4, audio removed)"
print

while true; do
  read "workflow_choice?Enter 1 or 2: "
  [[ "$workflow_choice" == 1 || "$workflow_choice" == 2 ]] && break
  print "Please enter 1 or 2."
done

SPEED_MODE=0
SPEED_VALUE=""
SPEED_LABEL=""

if [[ "$workflow_choice" == 2 ]]; then
  SPEED_MODE=1
  print
  while true; do
    read "SPEED_VALUE?Speed multiplier (1.25–10): "
    if [[ "$SPEED_VALUE" =~ '^[0-9]+([.][0-9]+)?$' ]] && (( SPEED_VALUE >= 1.25 && SPEED_VALUE <= 10 )); then
      break
    fi
    print "Enter a number from 1.25 through 10."
  done
  FORMAT="mp4"
  SPEED_LABEL=" ${SPEED_VALUE}x"
  print
  print "Speed Up Tutorial: ${SPEED_VALUE}× MP4 with all audio removed."
else
  print
  print "Convert the selected files to:"
  print
print "  VIDEO             AUDIO             PHOTO"
print "  1) MP4            5) MP3            11) JPG"
print "  2) MOV            6) M4A            12) PNG"
print "  3) WEBM           7) WAV            13) WEBP"
print "  4) MKV            8) FLAC           14) TIFF"
print "                     9) OGG            15) GIF"
print "                    10) OPUS"
print

typeset -A FORMATS
FORMATS=(1 mp4 2 mov 3 webm 4 mkv 5 mp3 6 m4a 7 wav 8 flac 9 ogg 10 opus 11 jpg 12 png 13 webp 14 tiff 15 gif)

while true; do
  read "choice?Enter 1–15: "
  FORMAT="${FORMATS[$choice]:-}"
  [[ -n "$FORMAT" ]] && break
  print "Please enter a number from 1 to 15."
done
fi

mkdir -p "$OUTPUT_DIR"
DEST_KIND="$(target_kind "$FORMAT")"
successes=0
failures=0

print
print "Saving to: $OUTPUT_DIR"
print

for source in "${FILES[@]}"; do
  if [[ ! -f "$source" ]]; then
    print "✗ Skipped missing file: $source"
    (( failures++ ))
    continue
  fi

  SOURCE_KIND="$(media_kind "$source")"
  if [[ "$SOURCE_KIND" == unknown ]]; then
    print "✗ Unsupported file: ${source:t}"
    (( failures++ ))
    continue
  fi

  if (( SPEED_MODE == 1 )) && [[ "$SOURCE_KIND" != video ]]; then
    print "✗ Speed Up skipped non-video file: ${source:t}"
    (( failures++ ))
    continue
  fi

  output="$(unique_output "$source" "$FORMAT" "$SPEED_LABEL")"
  typeset -a INPUT_ARGS CODEC_ARGS
  INPUT_ARGS=()
  CODEC_ARGS=()

  if [[ "$SOURCE_KIND" == image && "$DEST_KIND" == video ]]; then
    INPUT_ARGS=(-loop 1 -framerate 30 -i "$source" -t 5)
  elif [[ "$SOURCE_KIND" == image && "$DEST_KIND" == audio ]]; then
    INPUT_ARGS=(-i "$source" -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 5 -map 1:a:0)
  else
    INPUT_ARGS=(-i "$source")
  fi

  if (( SPEED_MODE == 1 )); then
    CODEC_ARGS=(-vf "setpts=PTS/${SPEED_VALUE},scale=trunc(iw/2)*2:trunc(ih/2)*2" -an -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -movflags +faststart)
  else
  case "$FORMAT" in
    mp4)
      if [[ "$SOURCE_KIND" == audio ]]; then
        CODEC_ARGS=(-filter_complex "[0:a]showwaves=s=1280x720:mode=line:rate=30:colors=0x7C5CFC[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest)
      else
        CODEC_ARGS=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart)
      fi ;;
    mov)
      if [[ "$SOURCE_KIND" == audio ]]; then
        CODEC_ARGS=(-filter_complex "[0:a]showwaves=s=1280x720:mode=line:rate=30:colors=0x7C5CFC[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest)
      else
        CODEC_ARGS=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k)
      fi ;;
    webm)
      if [[ "$SOURCE_KIND" == audio ]]; then
        CODEC_ARGS=(-filter_complex "[0:a]showwaves=s=1280x720:mode=line:rate=30:colors=0x7C5CFC[v]" -map "[v]" -map 0:a -c:v libvpx-vp9 -crf 31 -b:v 0 -c:a libopus -b:a 160k -shortest)
      else
        CODEC_ARGS=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libvpx-vp9 -crf 31 -b:v 0 -c:a libopus -b:a 160k)
      fi ;;
    mkv)
      if [[ "$SOURCE_KIND" == audio ]]; then
        CODEC_ARGS=(-filter_complex "[0:a]showwaves=s=1280x720:mode=line:rate=30:colors=0x7C5CFC[v]" -map "[v]" -map 0:a -c:v libx264 -crf 20 -c:a aac -b:a 192k -shortest)
      else
        CODEC_ARGS=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 20 -c:a aac -b:a 192k)
      fi ;;
    mp3) CODEC_ARGS=(-vn -c:a libmp3lame -q:a 2) ;;
    m4a) CODEC_ARGS=(-vn -c:a aac -b:a 256k) ;;
    wav) CODEC_ARGS=(-vn -c:a pcm_s24le) ;;
    flac) CODEC_ARGS=(-vn -c:a flac) ;;
    ogg) CODEC_ARGS=(-vn -c:a libvorbis -q:a 6) ;;
    opus) CODEC_ARGS=(-vn -c:a libopus -b:a 160k) ;;
    jpg)
      if [[ "$SOURCE_KIND" == audio ]]; then CODEC_ARGS=(-filter_complex "[0:a]showwavespic=s=1600x900:colors=0x7C5CFC[v]" -map "[v]" -frames:v 1 -q:v 2)
      else CODEC_ARGS=(-frames:v 1 -q:v 2); fi ;;
    png)
      if [[ "$SOURCE_KIND" == audio ]]; then CODEC_ARGS=(-filter_complex "[0:a]showwavespic=s=1600x900:colors=0x7C5CFC[v]" -map "[v]" -frames:v 1 -compression_level 6)
      else CODEC_ARGS=(-frames:v 1 -compression_level 6); fi ;;
    webp)
      if [[ "$SOURCE_KIND" == audio ]]; then CODEC_ARGS=(-filter_complex "[0:a]showwavespic=s=1600x900:colors=0x7C5CFC[v]" -map "[v]" -frames:v 1 -c:v libwebp -quality 90)
      else CODEC_ARGS=(-frames:v 1 -c:v libwebp -quality 90); fi ;;
    tiff)
      if [[ "$SOURCE_KIND" == audio ]]; then CODEC_ARGS=(-filter_complex "[0:a]showwavespic=s=1600x900:colors=0x7C5CFC[v]" -map "[v]" -frames:v 1 -c:v tiff)
      else CODEC_ARGS=(-frames:v 1 -c:v tiff); fi ;;
    gif)
      if [[ "$SOURCE_KIND" == video ]]; then CODEC_ARGS=(-vf "fps=15,scale='min(1280,iw)':-2:flags=lanczos" -loop 0)
      elif [[ "$SOURCE_KIND" == audio ]]; then CODEC_ARGS=(-filter_complex "[0:a]showwaves=s=1200x675:mode=line:rate=24:colors=0x7C5CFC[v]" -map "[v]" -t 10 -loop 0)
      else CODEC_ARGS=(-frames:v 1); fi ;;
  esac
  fi

  print "→ ${source:t}  →  ${output:t}"
  if "$FFMPEG" -hide_banner -y "${INPUT_ARGS[@]}" "${CODEC_ARGS[@]}" "$output"; then
    print "✓ Done"
    (( successes++ ))
  else
    print "✗ Conversion failed"
    rm -f "$output"
    (( failures++ ))
  fi
  print
done

print "Finished: $successes converted, $failures failed."
if (( successes > 0 )) && [[ "${CODEX_NO_OPEN:-0}" != 1 ]]; then
  open "$OUTPUT_DIR"
fi
pause_and_exit $(( failures > 0 ? 1 : 0 ))
