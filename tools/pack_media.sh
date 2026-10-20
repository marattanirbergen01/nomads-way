#!/bin/sh
# Нормализует иллюстрации из content/media/<season>/ в content/media/<season>/out/.
# Только macOS (sips). Дальше compile.dart копирует out/ в build/media/<season>/.
#
#   scenes/<id>.png|jpg        → out/<id>.jpg               до 1920 по длинной стороне
#   backgrounds/<id>.*         → out/<id>.jpg               до 1600
#   maps/<id>.png              → out/<id>.png               без сжатия: подписи на карте
#   maps/<id>_<lang>.mp4/.png  → out/ как есть             анимированная карта + постер (последний кадр)
#   avatars/<id>_bust.png      → out/avatars/<id>_bust.png  PNG с альфой, до 960
#   avatars/<id>.png           → out/avatars/<id>.jpg       портрет для кружка, до 512
#   characters/<id>.png        → out/characters/<id>.jpg    портрет исторического лица, до 512
#   <id>.png|jpg в корне сезона — старая раскладка, как scenes/
#
# out/ пересобирается с нуля, чтобы не оставались файлы под старыми именами.
set -e
cd "$(dirname "$0")/.."

# sips -Z умеет и увеличивать — а апскейл даёт только байты и мыло. Уменьшаем, если крупнее цели; иначе не трогаем размер.
maxdim() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/{if($2>m)m=$2} END{print m}'; }
jpg() { # src dst maxdim quality
  if [ "$(maxdim "$1")" -gt "$3" ]; then
    sips -s format jpeg -s formatOptions "$4" -Z "$3" "$1" --out "$2" >/dev/null
  else
    sips -s format jpeg -s formatOptions "$4" "$1" --out "$2" >/dev/null
  fi
  printf '%-34s → %-34s %5s KB  %s\n' "$(basename "$1")" "${2#content/media/}" "$(( $(stat -f%z "$2") / 1024 ))" "$(sips -g pixelWidth -g pixelHeight "$2" | awk '/pixel/{printf "%s ",$2}' | sed 's/ $//;s/ /×/')"
}
png() { # src dst maxdim
  if [ "$(maxdim "$1")" -gt "$3" ]; then
    sips -s format png -Z "$3" "$1" --out "$2" >/dev/null
  else
    cp "$1" "$2"
  fi
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
  for f in "$season"/maps/*.png "$season"/maps/*.mp4; do
    # карты — как есть: png без сжатия, ролики уже сжаты (<id>_<lang>.mp4 + постер <id>_<lang>.png)
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
