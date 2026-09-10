#!/bin/sh
# Поднимает прототип для просмотра в Chrome на этом Mac.
#   sh scripts/dev.sh          — только с этого компьютера (localhost)
#   sh scripts/dev.sh lan      — плюс телефон в той же Wi-Fi (в приложении ☁ → указать http://<IP>:8787)
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
HOST=localhost; [ "$1" = "lan" ] && HOST=0.0.0.0
IP=$(ipconfig getifaddr en0 2>/dev/null || echo localhost)

(cd tools && dart run bin/compile.dart >/dev/null && dart run bin/pack.dart >/dev/null && echo "контент собран и упакован → build/")
python3 tools/serve.py 8787 >/dev/null 2>&1 &
CDN=$!
trap 'kill $CDN 2>/dev/null' EXIT

echo "CDN:        http://$HOST:8787   (с телефона: http://$IP:8787)"
echo "Приложение: http://localhost:5173   (с телефона: http://$IP:5173)"
echo "Открываю Chrome через несколько секунд… Остановить: Ctrl+C"
( sleep 12 && open -a "Google Chrome" http://localhost:5173 ) &
cd app && flutter run -d web-server --web-port 5173 --web-hostname "$HOST"
