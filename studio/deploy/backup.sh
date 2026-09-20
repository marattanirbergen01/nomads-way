#!/bin/sh
# Ночной бэкап базы и загрузок в /srv/backups (хранит 14 дней). В cron: 0 3 * * * /srv/nomads-way/studio/deploy/backup.sh
set -e
mkdir -p /srv/backups
STAMP=$(date +%Y%m%d-%H%M)
docker run --rm -v deploy_studio-data:/data -v /srv/backups:/out alpine \
  sh -c "cp /data/studio.db /out/studio-$STAMP.db && tar czf /out/uploads-$STAMP.tgz -C /data uploads 2>/dev/null || true"
find /srv/backups -type f -mtime +14 -delete
