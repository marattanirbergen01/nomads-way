#!/bin/sh
# Первичная настройка чистого Ubuntu 24.04 на Hetzner. Запускать от root:
#   curl -fsSL https://raw.githubusercontent.com/marattanirbergen01/nomads-way/main/studio/deploy/setup.sh | sh
# или скопировать файл и выполнить sh setup.sh
set -e
REPO=git@github.com:marattanirbergen01/nomads-way.git

echo "== Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

echo "== deploy-ключ для GitHub"
if [ ! -f /root/.ssh/id_ed25519 ]; then
  ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 -C "nomads-studio-server" -q
fi
ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null
echo
echo "Добавьте этот ключ в GitHub → репозиторий nomads-way → Settings → Deploy keys (Allow write access):"
echo
cat /root/.ssh/id_ed25519.pub
echo
printf "Нажмите Enter, когда ключ добавлен... "
read _ </dev/tty

echo "== Клонируем репозиторий в /srv/nomads-way"
if [ ! -d /srv/nomads-way ]; then
  git clone "$REPO" /srv/nomads-way
fi
git -C /srv/nomads-way config user.name "Nomads Studio"
git -C /srv/nomads-way config user.email "studio@nomads-way.local"

echo "== Настройки"
IP=$(curl -fsS https://api.ipify.org || hostname -I | awk '{print $1}')
cd /srv/nomads-way/studio/deploy
if [ ! -f .env ]; then
  cat > .env <<ENV
STUDIO_HOST=${IP}.sslip.io
SESSION_SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
ADMIN_PASSWORD=$(head -c 9 /dev/urandom | base64 | tr -d '/+=' )
ENV
fi
echo "Адрес студии: https://$(grep STUDIO_HOST .env | cut -d= -f2)"
echo "Пароль admin: $(grep ADMIN_PASSWORD .env | cut -d= -f2)   (смените после входа)"

echo "== Запуск"
docker compose up -d --build
echo "Готово. Логи: docker compose -f /srv/nomads-way/studio/deploy/docker-compose.yml logs -f studio"
