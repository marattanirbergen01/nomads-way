#!/bin/sh
# Нормализует иллюстрации из content/media/<season>/ в content/media/<season>/out/.
# Только macOS (sips). Дальше compile.dart копирует out/ в build/media/<season>/.
#
#   scenes/<id>.png|jpg        → out/<id>.jpg               до 1920 по длинной стороне
#   backgrounds/<id>.*         → out/<id>.jpg               до 1600
#   maps/<id>.png              → out/<id>.png               без сжатия: подписи на карте
#   avatars/<id>_bust.png      → out/avatars/<id>_bust.png  PNG с альфой, до 960
#   avatars/<id>.png           → out/avatars/<id>.jpg       портрет для кружка, до 512
#   characters/<id>.png        → out/characters/<id>.jpg    портрет исторического лица, до 512
#   <id>.png|jpg в корне сезона — старая раскладка, как scenes/
#
# out/ пересобирается с нуля, чтобы не оставались файлы под старыми именами.
set -e
cd "$(dirname "$0")/.."

jpg() { # src dst maxdim quality
  sips -s format jpeg -s formatOptions "$4" -Z "$3" "$1" --out "$2" >/dev/null
  printf '%-34s → %-34s %5s KB\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))"
}
png() { # src dst maxdim
  sips -s format png -Z "$3" "$1" --out "$2" >/dev/null
  printf '%-34s → %-34s %5s KB\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))"
}
copy() { # src dst
  cp "$1" "$2"
  printf '%-34s → %-34s %5s KB  (как есть)\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))"
}

for season in content/media/s*/; do
  season="${season%/}"
  out="$season/out"; rm -rf "$out"; mkdir -p "$out/avatars" "$out/characters"
  for f in "$season"/*.png "$season"/*.jpg "$season"/*.jpeg "$season"/scenes/*.png "$season"/scenes/*.jpg "$season"/scenes/*.jpeg; do
    [ -e "$f" ] || continue
    jpg "$f" "$out/$(basename "${f%.*}").jpg" 1920 82
  done
  for f in "$season"/backgrounds/*.png "$season"/backgrounds/*.jpg "$season"/backgrounds/*.jpeg; do
    [ -e "$f" ] || continue
    jpg "$f" "$out/$(basename "${f%.*}").jpg" 1600 82
  done
  for f in "$season"/maps/*.png; do
    [ -e "$f" ] || continue
    copy "$f" "$out/$(basename "$f")"
  done
  for f in "$season"/avatars/*_bust.png; do
    [ -e "$f" ] || continue
    png "$f" "$out/avatars/$(basename "$f")" 960
  done
  for f in "$season"/avatars/*.png; do
    [ -e "$f" ] || continue
    case "$f" in *_bust.png) continue;; esac
    jpg "$f" "$out/avatars/$(basename "${f%.*}").jpg" 512 84
  done
  for f in "$season"/characters/*.png "$season"/characters/*.jpg; do
    [ -e "$f" ] || continue
    jpg "$f" "$out/characters/$(basename "${f%.*}").jpg" 512 84
  done
done
