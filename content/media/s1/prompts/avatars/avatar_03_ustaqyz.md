# avatar_03_ustaqyz — Ұста қыз — юная мастерица

Аватар игрока, около 17 лет. Четыре эмоции — четыре файла с одним и тем же лицом.

## Как сохранить одно лицо во всех четырёх вариантах
1. Сгенерируйте вариант **calm** и утвердите его. Это эталон, остальные делаются от него.
2. Зафиксируйте seed эталона и не меняйте его. Меняется ровно одно предложение — про эмоцию.
3. ИЗМЕРЕНО на аватарах 01 и 02: диапазон strength 0.25–0.45 не работает — кадр отличается
   от входа на 2–4 из 255, это шум. Рабочее значение — **strength 1.0** при том же seed.
   Похожесть держит совпадение seed, а не малая сила денойза.
4. Входа для картинки-референса у klein нет: во вкладке Comp. списка Control модулей пусто.
5. ЭТАЛОН НЕ ПРАВИТЬ В ДРУГИХ ИНСТРУМЕНТАХ. У аватара 01 calm дорабатывался в Gemini, и
   эмоции от него расходятся на 8–13 из 255; у аватара 02 эталон родной — расхождение 3.7–4.0.
5. Все четыре файла одного аватара генерировать за один сеанс, не трогая настройки между ними.

## Базовый промпт (общая часть, не меняется)
Стиль сверен с утверждёнными аватарами 01 и 02 и с артом серии `art_s1e01_020`, `art_s1e01_030`.
Костюм сверен с фото 2026-09-11: высокий конический борик с меховой опушкой, тёмное бархатное
платье с орнаментом по груди и обшлагам. Цвет платья — сливовый, не синий: индиго уже занят акыном.
Черты лица и формы головного убора заданы утверждением: при guidance 1.0 отрицания не работают.

A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above her cap down to her waist, so head and chest fill most of the frame; eyes on the upper third line, same camera distance in every variant. No lettering, no border, no modern clothing, no fantasy armour. A Kazakh girl of seventeen who works felt and cloth: distinctly Central Asian features — broad flat cheekbones, dark almond eyes with a pronounced epicanthic fold at the inner corner, straight black brows, a low-bridged nose, a soft rounded chin. Her complexion is fair and warm, only lightly tanned. Two long dark braids fall forward over her shoulders. She wears a tall conical felt cap of dark cloth, its point rising high above her head, a band of soft grey fur running round its base and keeping close to the head, a curling ornament in muted thread worked over the cone. She wears a fitted dress of deep muted plum velvet with long narrow sleeves, a curling Kazakh ornament in dull old-brass thread laid over the chest and along the cuffs — worn and quiet, the colour of old brass rather than bright gold. Everything stays subdued: dark plum cloth and quiet ornament, never festive. Her clothes are simple but kept neat, the cloth honest in colour — not grey, not washed out.

## Варианты эмоций
Дописывается одним предложением в конец базового промпта.

### avatar_03_ustaqyz_calm — Спокойствие
Где используется: по умолчанию: профиль, меню, ровные сцены; а также sc020 и sc022
(решение уходить) — эмоция resolve упразднена 2026-09-09, вместо неё calm
```
Her expression is calm and open, looking directly at the viewer, mouth relaxed, shoulders easy.
```

### avatar_03_ustaqyz_joy — Радость
Где используется: sc032 приход в долину, sc042 новые роды
```
She is smiling widely with genuine delight, eyes crinkled at the corners, head lifted slightly, shoulders back.
```

### avatar_03_ustaqyz_alarm — Тревога
Где используется: sc010 набег, sc038 весть о походе
```
Her eyes are wide and round with the whites showing above the iris, her brows lifted high and pinched together at the inner ends, her mouth open in a sharp intake of breath, her head turned a little as if reacting to something off-frame.
```


### avatar_03_ustaqyz_sorrow — Печаль
Где используется: sc022 прощание с могилами, sc025 тяжёлый переход
```
Her gaze is lowered and turned slightly away, brows drawn together in quiet sadness, mouth closed and downturned, shoulders dropped.
```

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 (портрет), финал кадрируется в круг 512×512
- Steps: **4** · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Слово `brim` не употреблять: уводит модель в шляпу с плоскими полями.
- Эмоции описывать формой, а не названием чувства. Не отрисовываются ни разу:
  брови домиком, сведённые брови, прищур в углах глаз.
- Seed: один и тот же для всех четырёх эмоций, записать в manifest.yaml
- Стартовые значения — подобрать на эталоне calm и дальше не менять
