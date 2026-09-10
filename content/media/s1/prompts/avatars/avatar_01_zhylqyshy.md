# avatar_01_zhylqyshy — Жылқышы — табунщик

Аватар игрока, около 17 лет. Четыре эмоции — четыре файла с одним и тем же лицом.

## Как сохранить одно лицо во всех пяти вариантах
1. Сгенерируйте вариант **calm** и утвердите его. Это эталон, остальные делаются от него.
2. Зафиксируйте seed эталона и не меняйте его. Меняется ровно одно предложение — про эмоцию.
3. ИЗМЕРЕНО 2026-09-09 на FLUX.2 klein 4B: диапазон 0.25–0.45 не работает вовсе.
   На 0.30, 0.40 и 0.55 кадр отличается от входа на 1.9–2.3 из 255 — это шум, а не генерация,
   эмоция не проступает ни на одной из этих сил. Рабочее значение — **strength 1.0**
   при том же seed: расхождение 13 из 255, эмоция появляется, лицо и костюм сохраняются.
   Похожесть держит совпадение seed, а не малая сила денойза.
4. Если в вашей сборке FLUX.2 есть вход для картинки-референса — используйте его вместо img2img,
   результат стабильнее. Проверьте по интерфейсу Draw Things: у klein-сборок этот вход есть не всегда.
5. Все четыре файла одного аватара генерировать за один сеанс, не трогая настройки между ними.

## Базовый промпт (общая часть, не меняется)
Стиль сверен с утверждённым артом серии — `art_s1e01_020` и `art_s1e01_030`: аватар должен
читаться как персонаж из тех же кадров, а не как фотопортрет.
Костюм сверен с историческим фото табунщика с құрықом: тымак с широкими ушами,
длинный распашной чапан, мягкий кушак. Кожа светлая, не смуглая.
Тымак — по второму фото: широкие меховые уши вдоль щёк, тулья тёмная, но мягкая: гладкий купол по голове,
ровный контур — без клёпок и без углов, торчащих по бокам.
Черты лица заданы явно (скулы, разрез глаз) — без этого модель уводит типаж. Ворот гладкий, без завязок
и пуговиц; пояс и ворот описаны утверждением, а не запретом — при guidance 1.0
отрицания не работают.

A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. Head and shoulders large in frame, eyes on the upper third line, same camera distance in every variant. No lettering, no border, no modern clothing, no fantasy armour. A Kazakh boy of seventeen who herds horses, and clearly a boy: distinctly Central Asian features — broad flat cheekbones, a wide jaw, dark almond eyes set slightly narrow with an epicanthic fold at the inner corner, straight black brows, a low-bridged nose, a firm chin and a strong neck, short black hair. His complexion is fair and warm, only lightly tanned. He wears a tymak — a big Kazakh winter hat whose crown is a smooth dome of dark brown felt fitting close to the head, its outline round and unbroken, while thick pale wolf fur forms the wide band framing the face and the two broad flaps hanging down along his cheeks past the ears. Over a coarse undyed shirt with a plain slit collar, smooth and bare at the throat, he wears a long loose chapan coat of worn rust-brown cloth, wrapped across the chest, with long wide sleeves. Around his waist, a wide band of red woven cloth wound twice, flat and soft, its fringed ends hanging at his side. A coiled horsehair lasso rests over one shoulder, and the plain wooden shaft of a long herding pole leans against the same shoulder. His clothes are poor and mended, but the cloth keeps its colour — not grey, not washed out.

## Варианты эмоций
Дописывается одним предложением в конец базового промпта.

### avatar_01_zhylqyshy_calm — Спокойствие
Где используется: по умолчанию: профиль, меню, ровные сцены; а также sc020 и sc022
(решение уходить) — эмоция resolve упразднена 2026-09-09, вместо неё calm
```
His expression is calm and open, looking directly at the viewer, mouth relaxed, shoulders easy.
```

### avatar_01_zhylqyshy_joy — Радость
Где используется: sc032 приход в долину, sc042 новые роды
```
He is smiling widely with genuine delight, eyes crinkled at the corners, head lifted slightly, shoulders back.
```

### avatar_01_zhylqyshy_alarm — Тревога
Где используется: sc010 набег, sc038 весть о походе
```
His eyes are wide and round with the whites showing above the iris, his brows lifted high and pinched together at the inner ends, his mouth open in a sharp intake of breath, his head turned a little as if reacting to something off-frame.
```


### avatar_01_zhylqyshy_sorrow — Печаль
Где используется: sc022 прощание с могилами, sc025 тяжёлый переход
```
His gaze is lowered and turned slightly away, brows drawn together in quiet sadness, mouth closed and downturned, shoulders dropped.
```

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 (портрет), финал кадрируется в круг 512×512
- Steps: **4** · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- ИЗМЕРЕНО 2026-09-09: klein дистиллирована, 24 шага избыточны. Один кадр 896×1152:
  24 шага — 3 мин 43 с, 8 шагов — 2 мин 29 с, 4 шага — 1 мин 20 с, при одинаковой
  проработке меха, складок и плетения. Ниже 4 смысла нет: ~50 с из 80 — фиксированные
  накладные на загрузку модели, а не сэмплинг.
- Seed: один и тот же для всех четырёх эмоций, записать в manifest.yaml
- Стартовые значения — подобрать на эталоне calm и дальше не менять
