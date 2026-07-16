#!/usr/bin/env bash
# gif2mp4.sh — turn a GIF (file or URL) into an APL-safe looping mp4.
#
# APL's Image component renders GIFs as a static first frame; animation only
# works through the Video component, which wants h264/yuv420p with even
# dimensions. This produces exactly that, muted and faststart-flagged.
#
# usage: tools/gif2mp4.sh <gif-file-or-url> <out.mp4>
# then commit the mp4 under media/ and reference it from a deck card as:
#   "video": "https://cdn.jsdelivr.net/gh/AssiamahS/flashdeck@main/media/<out.mp4>"
# (jsDelivr serves proper video/mp4 headers; raw.githubusercontent.com sends
# octet-stream, which some Echo firmwares refuse to play.)
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <gif-file-or-url> <out.mp4>" >&2
  exit 1
fi

src="$1"
out="$2"
tmp=""

if [[ "$src" == http* ]]; then
  tmp="$(mktemp -t gif2mp4).gif"
  curl -sfL -A "Mozilla/5.0" -o "$tmp" "$src"
  src="$tmp"
fi

ffmpeg -y -v error -i "$src" \
  -movflags +faststart -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos" \
  -an "$out"

[ -n "$tmp" ] && rm -f "$tmp"
echo "wrote $out ($(du -h "$out" | cut -f1 | tr -d ' '))"
