#!/bin/sh
# Обновить студию на сервере до последнего main.
set -e
cd /srv/nomads-way
git pull --ff-only
cd studio/deploy
docker compose up -d --build
