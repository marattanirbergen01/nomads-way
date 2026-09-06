#!/bin/sh
# Нормализует иллюстрации: content/media/<season>/<id>.(png|jpg|jpeg) → content/media/<season>/out/<id>.jpg
# Сцены/баннеры — ширина 1600, обложки/иконки — 1024. JPEG качество ~82. Только macOS (sips).
# После этого compile.dart подхватывает out/<id>.jpg в build/<episode>/media/.
set -e
cd "$(dirname "$0")/.."
for season in content/media/s*/; do
  mkdir -p "$season/out"
  for f in "$season"*.png "$season"*.jpg "$season"*.jpeg; do
    [ -e "$f" ] || continue
    id=$(basename "${f%.*}")
    case "$id" in cover_*|app_icon) w=1024;; *) w=1600;; esac
    sips -s format jpeg -s formatOptions 82 --resampleWidth "$w" "$f" --out "$season/out/$id.jpg" >/dev/null
    printf '%-18s → %s (%s KB)\n' "$id" "$season/out/$id.jpg" "$(( $(stat -f%z "$season/out/$id.jpg") / 1024 ))"
  done
done
