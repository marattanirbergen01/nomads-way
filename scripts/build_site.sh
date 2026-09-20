#!/bin/sh
# Собирает статический сайт: веб-версия приложения + контент рядом (site/cdn).
#   sh scripts/build_site.sh            — для корня домена (base href /)
#   sh scripts/build_site.sh /nomads-way/   — для GitHub Pages вида https://<user>.github.io/nomads-way/
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
BASE="${1:-/}"

(cd tools && dart run bin/compile.dart >/dev/null && dart run bin/pack.dart >/dev/null && echo "контент собран → build/")

rm -rf site
(cd app && flutter build web --release --base-href "$BASE" --dart-define=CDN_URL=cdn --pwa-strategy=none >/dev/null && echo "приложение собрано")
cp -R app/build/web site
mkdir -p site/cdn
cp -R build/. site/cdn/
# CanvasKit грузится с gstatic (так задано во flutter_bootstrap.js); локальная копия — 36 МБ лишнего
rm -rf site/canvaskit
touch site/.nojekyll
echo "сайт → site/  ($(du -sh site | cut -f1)), base href: $BASE, контент: ${BASE}cdn/"
