#!/bin/sh
# Публикует сайт на GitHub Pages: ветка gh-pages репозитория marattanirbergen01/nomads-way.
# Адрес: https://marattanirbergen01.github.io/nomads-way/
# В ветке только собранный сайт (приложение + контент), исходники туда не попадают.
set -e
cd "$(dirname "$0")/.."
REPO=git@github.com:marattanirbergen01/nomads-way.git
sh scripts/build_site.sh /nomads-way/
cd site
git init -q -b gh-pages
git add -A
git -c user.name="deploy" -c user.email="m_tanirbergen@kbtu.kz" commit -qm "site $(date '+%Y-%m-%d %H:%M')"
git push -f -q "$REPO" gh-pages
echo "опубликовано → https://marattanirbergen01.github.io/nomads-way/  (обновление на GitHub занимает ~1 мин)"
