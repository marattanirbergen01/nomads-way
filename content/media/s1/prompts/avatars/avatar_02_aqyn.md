# avatar_02_aqyn — Ақын — юный акын

Аватар игрока, около 17 лет. Четыре эмоции — четыре файла с одним и тем же лицом.

## Как сохранить одно лицо во всех четырёх вариантах
1. Сгенерируйте вариант **calm** и утвердите его. Это эталон, остальные делаются от него.
2. Зафиксируйте seed эталона и не меняйте его. Меняется ровно одно предложение — про эмоцию.
3. ИЗМЕРЕНО 2026-09-09 на аватаре 01: диапазон strength 0.25–0.45 не работает вовсе —
   на 0.30, 0.40 и 0.55 кадр отличается от входа на 1.9–2.3 из 255, это шум, эмоция не проступает.
   Рабочее значение — **strength 1.0** при том же seed: расхождение ~10 из 255, эмоция появляется,
   лицо и костюм сохраняются. Похожесть держит совпадение seed, а не малая сила денойза.
4. Входа для картинки-референса у klein нет: во вкладке Comp. списка Control модулей пусто.
   Проверено 2026-09-09, этот путь закрыт.
5. Все четыре файла одного аватара генерировать за один сеанс, не трогая настройки между ними.

## Базовый промпт (общая часть, не меняется)
Стиль сверен с утверждённым артом серии — `art_s1e01_020` и `art_s1e01_030`, и с утверждённым
аватаром 01. Черты лица заданы явно: без этого модель уводит типаж в европеоидность.
Такия и покрой шапана сверены с фотографиями, присланными 2026-09-10:
қалпақ — высокий конус, нижний край загнут вверх и прижат к тулье (фото 2026-09-10).
Слово brim не употреблять: оно уводит модель в шляпу с плоскими полями, длинный распашной шапан с орнаментом
по полам и обшлагам. Орнамент приглушённый, не золотой. Формы описаны утверждением, а не запретом — при guidance 1.0 отрицания не работают.

A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above his cap down to his waist, so head and chest fill most of the frame; eyes on the upper third line, same camera distance in every variant. No lettering, no border, no modern clothing, no fantasy armour. A Kazakh boy of seventeen, an aqyn — a young singer of verses, and clearly a boy: distinctly Central Asian features — broad flat cheekbones, a wide jaw, narrow dark eyes, the opening a long thin almond under heavy lids, with a pronounced epicanthic fold at the inner corner, straight black brows, a low-bridged nose, a firm chin and a strong neck, short black hair. His complexion is fair and warm, only lightly tanned. He wears a qalpaq: a tall Kazakh hat of thick dark indigo felt, shaped as a high cone with a softly rounded tip. Its lower edge is folded upward and lies back flat against the cone itself, making a thick standing rim that hugs the hat and is split open at the two sides into two upturned points. That folded rim rises against the cone; the felt hugs the hat everywhere and keeps close to the head. A curling ornament is worked across the cone and along the folded rim. Over a coarse undyed shirt with a plain slit collar he wears a shapan: a long deep indigo robe of heavy cloth, wrapped across the chest, with long wide sleeves that cover his arms to the wrist. A broad band of curling Kazakh ornament runs down both front edges and around the cuffs, embroidered in dull muted ochre and bone thread — worn and soft, the colour of old brass rather than bright gold. Everything stays subdued: deep indigo cloth and quiet ornament, never festive. His clothes are simple but kept neat, the cloth heavy and honest in colour — not grey, not washed out.

## Варианты эмоций
Дописывается одним предложением в конец базового промпта.

### avatar_02_aqyn_calm — Спокойствие
Где используется: по умолчанию: профиль, меню, ровные сцены; а также sc020 и sc022
(решение уходить) — эмоция resolve упразднена 2026-09-09, вместо неё calm
```
His expression is calm and open, looking directly at the viewer, mouth relaxed, shoulders easy.
```

### avatar_02_aqyn_joy — Радость
Где используется: sc032 приход в долину, sc042 новые роды
```
He is smiling widely with genuine delight, eyes crinkled at the corners, head lifted slightly, shoulders back.
```

### avatar_02_aqyn_alarm — Тревога
Где используется: sc010 набег, sc038 весть о походе
```
His eyes are wide and round with the whites showing above the iris, his brows lifted high and pinched together at the inner ends, his mouth open in a sharp intake of breath, his head turned a little as if reacting to something off-frame.
```


### avatar_02_aqyn_sorrow — Печаль
Где используется: sc022 прощание с могилами, sc025 тяжёлый переход
```
His gaze is lowered and turned slightly away, brows drawn together in quiet sadness, mouth closed and downturned, shoulders dropped.
```

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 (портрет), финал кадрируется в круг 512×512
- Steps: **4** · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- ИЗМЕРЕНО: klein дистиллирована, 24 шага избыточны. Кадр 896×1152: 24 шага — 3 мин 43 с,
  8 — 2 мин 29 с, 4 — 1 мин 20 с, при одинаковой проработке.
- Seed: один и тот же для всех четырёх эмоций, записать в manifest.yaml
- Стартовые значения — подобрать на эталоне calm и дальше не менять
