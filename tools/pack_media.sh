#!/bin/sh
# Нормализует иллюстрации из content/media/<season>/ в content/media/<season>/out/.
# Только macOS (sips). Дальше compile.dart копирует out/ в build/media/<season>/.
#
#   scenes/<id>.png|jpg        → out/<id>.jpg            (до 1920 по длинной стороне)
#   backgrounds/<id>.*         → out/<id>.jpg            (до 1600)
#   avatars/<id>_bust.png      → out/avatars/<id>_bust.png  (PNG, альфа сохраняется, до 960)
#   avatars/<id>.png           → out/avatars/<id>.jpg    (портрет для кружка, до 512)
#   <id>.png|jpg в корне сезона — старая раскладка, как scenes/
set -e
cd "$(dirname "$0")/.."

jpg() { # src dst maxdim quality
  sips -s format jpeg -s formatOptions "$4" -Z "$3" "$1" --out "$2" >/dev/null
  printf '%-34s → %-28s %5s KB\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))"
}
png() { # src dst maxdim
  sips -s format png -Z "$3" "$1" --out "$2" >/dev/null
  printf '%-34s → %-28s %5s KB\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))"
}

for season in content/media/s*/; do
  out="$season/out"; mkdir -p "$out/avatars"
  for f in "$season"*.png "$season"*.jpg "$season"*.jpeg "$season"scenes/*.png "$season"scenes/*.jpg "$season"scenes/*.jpeg; do
    [ -e "$f" ] || continue
    jpg "$f" "$out/$(basename "${f%.*}").jpg" 1920 82
  done
  for f in "$season"backgrounds/*.png "$season"backgrounds/*.jpg "$season"backgrounds/*.jpeg; do
    [ -e "$f" ] || continue
    jpg "$f" "$out/$(basename "${f%.*}").jpg" 1600 82
  done
  for f in "$season"avatars/*_bust.png; do
    [ -e "$f" ] || continue
    png "$f" "$out/avatars/$(basename "$f")" 960
  done
  for f in "$season"avatars/*.png; do
    [ -e "$f" ] || continue
    case "$f" in *_bust.png) continue;; esac
    jpg "$f" "$out/avatars/$(basename "${f%.*}").jpg" 512 84
  done
done
