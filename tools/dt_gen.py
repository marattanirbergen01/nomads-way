#!/usr/bin/env python3
"""dt_gen.py — обёртка над HTTP API Draw Things (A1111-совместимый).

Зачем: генерировать кадры для content/media/** воспроизводимо. Рядом с каждым
PNG кладётся .json с точным запросом и seed — из него потом заполняется
content/media/<season>/manifest.yaml.

Подкоманды:
  probe    — что вообще отдаёт API: GET / (текущий конфиг), options, модели, семплеры
  txt2img  — POST /sdapi/v1/txt2img
  img2img  — POST /sdapi/v1/img2img (вход — утверждённый кадр)

Зависимостей нет, только стандартная библиотека.

Пример:
  python3 tools/dt_gen.py probe
  python3 tools/dt_gen.py txt2img --prompt-file /tmp/calm.txt --count 4 \\
      --width 896 --height 1152 --steps 24 --guidance 1.0 \\
      --sampler "Euler A Trailing" --shift 3.0 \\
      --out content/media/s1/raw --name avatar_01_zhylqyshy_calm
  python3 tools/dt_gen.py img2img --prompt-file /tmp/joy.txt --seed 12345 \\
      --init content/media/s1/avatar_01_zhylqyshy_calm.png \\
      --denoising-strength 0.30 --out content/media/s1/raw --name avatar_01_zhylqyshy_joy
"""

import argparse
import base64
import json
import random
import sys
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_HOST = "http://127.0.0.1:7860"
SEED_MAX = 2**32 - 1


# --- транспорт ---------------------------------------------------------------

def _request(host, path, payload=None, timeout=600):
    url = host.rstrip("/") + path
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        die("HTTP %s на %s\n%s" % (e.code, url, body[:2000]))
    except urllib.error.URLError as e:
        die("нет связи с %s (%s).\n"
            "Draw Things запущен, но HTTP-сервер выключен? В приложении:\n"
            "вкладка Advanced слева → API Server → Protocol HTTP, Port 7860, localhost only."
            % (url, e.reason))
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        die("ответ %s — не JSON:\n%s" % (url, body[:2000]))


def die(msg):
    print("dt_gen: " + msg, file=sys.stderr)
    sys.exit(1)


# --- вспомогательное ---------------------------------------------------------

def load_prompt(args):
    if args.prompt_file:
        text = Path(args.prompt_file).read_text(encoding="utf-8")
    elif args.prompt:
        text = args.prompt
    else:
        die("нужен --prompt или --prompt-file")
    text = text.strip()
    if not text:
        die("промпт пустой")
    return text


def parse_info(resp):
    """У A1111 info — строка с JSON внутри. У других сборок бывает объект."""
    info = resp.get("info")
    if isinstance(info, str):
        try:
            return json.loads(info)
        except json.JSONDecodeError:
            return {"raw": info}
    return info if isinstance(info, dict) else {}


def decode_png(b64):
    if b64.startswith("data:"):
        b64 = b64.split(",", 1)[1]
    return base64.b64decode(b64)


def report_drift(payload, info):
    """Печатает поля, которые API вернул иначе, чем мы просили.

    Это единственный честный способ узнать, приняла ли сборка steps /
    cfg_scale / sampler_name / shift, или молча их проглотила.
    """
    if not info:
        print("    info: пусто — сверить параметры нечем, проверь их в приложении")
        return
    watched = ("steps", "guidance_scale", "sampler", "width", "height", "seed", "shift",
               "strength")
    for key in watched:
        if key not in payload:
            continue
        if key not in info:
            print("    ! поле %r API не вернул — принято ли оно, неизвестно" % key)
            continue
        want, got = payload[key], info[key]
        if isinstance(want, float) or isinstance(got, float):
            same = abs(float(want) - float(got)) < 1e-6
        else:
            same = str(want) == str(got)
        if not same:
            print("    ! %s: просили %r, API вернул %r" % (key, want, got))


def base_payload(args, prompt):
    # Имена полей взяты из ответа GET / самого Draw Things: guidance_scale
    # (не cfg_scale), sampler (не sampler_name), shift — настоящее поле.
    payload = {
        "prompt": prompt,
        "negative_prompt": args.negative,
        "width": args.width,
        "height": args.height,
        "steps": args.steps,
        "guidance_scale": args.guidance,
        "batch_count": 1,
        "batch_size": 1,
    }
    if args.sampler:
        payload["sampler"] = args.sampler
    if args.shift is not None:
        payload["shift"] = args.shift
    return payload


def resolve_seeds(args):
    if args.seeds:
        seeds = [int(s) for s in args.seeds.split(",") if s.strip()]
    elif args.seed is not None:
        seeds = [args.seed]
    else:
        seeds = [random.randint(0, SEED_MAX) for _ in range(args.count)]
    return seeds


def run_batch(args, endpoint, payload_extra=None):
    """Один запрос на кадр: так seed каждого файла известен точно,
    а не выводится из порядка картинок в ответе."""
    prompt = load_prompt(args)
    seeds = resolve_seeds(args)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    written, failed = [], []

    for seed in seeds:
        payload = base_payload(args, prompt)
        payload["seed"] = seed
        if payload_extra:
            payload.update(payload_extra)

        if args.dry_run:
            shown = dict(payload)
            if "init_images" in shown:
                shown["init_images"] = ["<%d байт base64>" % len(payload["init_images"][0])]
            print(json.dumps(shown, ensure_ascii=False, indent=2))
            continue

        # Приложение изредка отдаёт {"images": []} — похоже, срывается очередь.
        # Один повтор снимает это; если и он пуст, кадр пропускаем, пачку не рушим.
        images = []
        for attempt in (1, 2):
            resp = _request(args.host, endpoint, payload, timeout=args.timeout)
            images = resp.get("images") or []
            if images:
                break
            if attempt == 1:
                print("  · seed=%d: пустой ответ, повторяю" % seed)
        if not images:
            print("  ! seed=%d: API дважды вернул ответ без картинок, пропускаю" % seed)
            failed.append(seed)
            continue

        info = parse_info(resp)
        for n, b64 in enumerate(images):
            suffix = "" if len(images) == 1 else "_%d" % (n + 1)
            png = out_dir / ("%s_seed%d%s.png" % (args.name, seed, suffix))
            png.write_bytes(decode_png(b64))
            sidecar = dict(payload)
            sidecar.pop("init_images", None)
            if "init_images" in payload:
                sidecar["init_image_path"] = args.init
            meta = {"request": sidecar, "endpoint": endpoint, "info": info}
            png.with_suffix(".json").write_text(
                json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
            written.append((png, seed))
            print("  %s  seed=%d" % (png, seed))
        report_drift(payload, info)

    if failed:
        print("не отдались кадры с seed: %s" % ", ".join(str(x) for x in failed))
    return written


# --- подкоманды --------------------------------------------------------------

def cmd_probe(args):
    print("== %s ==" % args.host)
    # GET / отдаёт текущую настройку Draw Things (модель, размер, семплер, shift)
    for path in ("/", "/sdapi/v1/options", "/sdapi/v1/sd-models",
                 "/sdapi/v1/samplers", "/sdapi/v1/upscalers"):
        print("\n-- %s" % path)
        try:
            data = _request(args.host, path, timeout=30)
        except SystemExit:
            print("   (недоступно)")
            continue
        text = json.dumps(data, ensure_ascii=False, indent=2)
        print(text if len(text) < 4000 else text[:4000] + "\n   ...обрезано")


def cmd_txt2img(args):
    print("txt2img → %s" % args.out)
    run_batch(args, "/sdapi/v1/txt2img")


def cmd_img2img(args):
    init = Path(args.init)
    if not init.is_file():
        die("нет входного файла: %s" % init)
    b64 = base64.b64encode(init.read_bytes()).decode("ascii")
    print("img2img ← %s (strength %.2f) → %s"
          % (init, args.denoising_strength, args.out))
    # API принимает и strength, и denoising_strength, но строго одно из двух:
    # при обоих отвечает 422. Шлём strength — так поле зовётся в конфиге Draw Things.
    run_batch(args, "/sdapi/v1/img2img", {
        "init_images": [b64],
        "strength": args.denoising_strength,
    })


# --- разбор аргументов -------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Обёртка над HTTP API Draw Things (A1111-совместимый).")
    ap.add_argument("--host", default=DEFAULT_HOST, help="по умолчанию " + DEFAULT_HOST)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_probe = sub.add_parser("probe", help="показать, что отдаёт API")
    p_probe.set_defaults(func=cmd_probe)

    def add_gen_args(p):
        p.add_argument("--prompt")
        p.add_argument("--prompt-file", help="файл с полным текстом промпта")
        p.add_argument("--negative", default="", help="по умолчанию пусто")
        p.add_argument("--seed", type=int, help="конкретный seed")
        p.add_argument("--seeds", help="список seed через запятую")
        p.add_argument("--count", type=int, default=1,
                       help="сколько кадров со случайными seed (если --seed не задан)")
        p.add_argument("--width", type=int, default=896)
        p.add_argument("--height", type=int, default=1152)
        p.add_argument("--steps", type=int, default=24)
        p.add_argument("--guidance", type=float, default=1.0, help="уходит как guidance_scale")
        p.add_argument("--sampler", default="Euler A Trailing")
        p.add_argument("--shift", type=float, default=None,
                       help="настоящее поле Draw Things, есть в GET /")
        p.add_argument("--out", required=True, help="каталог для PNG")
        p.add_argument("--name", required=True, help="префикс имени файла")
        p.add_argument("--timeout", type=int, default=600)
        p.add_argument("--dry-run", action="store_true",
                       help="напечатать запрос и выйти")

    p_t2i = sub.add_parser("txt2img")
    add_gen_args(p_t2i)
    p_t2i.set_defaults(func=cmd_txt2img)

    p_i2i = sub.add_parser("img2img")
    add_gen_args(p_i2i)
    p_i2i.add_argument("--init", required=True, help="входная картинка")
    p_i2i.add_argument("--denoising-strength", type=float, default=0.30,
                       help="0.25–0.40 для эмоций; выше 0.45 лицо уплывает")
    p_i2i.set_defaults(func=cmd_img2img)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
