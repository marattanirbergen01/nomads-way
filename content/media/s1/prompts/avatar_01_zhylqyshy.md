# avatar_01_zhylqyshy — Жылқышы — табунщик

Аватар игрока, около 17 лет. Пять эмоций — пять файлов с одним и тем же лицом.

## Как сохранить одно лицо во всех пяти вариантах
1. Сгенерируйте вариант **calm** и утвердите его. Это эталон, остальные делаются от него.
2. Зафиксируйте seed эталона и не меняйте его. Меняется ровно одно предложение — про эмоцию.
3. Надёжнее всего добить сходство через img2img: подайте утверждённый calm на вход,
   сила (strength) 0.25–0.40, тот же промпт с новой эмоцией. Ниже 0.25 эмоция не проступит,
   выше 0.45 лицо начнёт уплывать.
4. Если в вашей сборке FLUX.2 есть вход для картинки-референса — используйте его вместо img2img,
   результат стабильнее. Проверьте по интерфейсу Draw Things: у klein-сборок этот вход есть не всегда.
5. Все пять файлов одного аватара генерировать за один сеанс, не трогая настройки между ними.

## Базовый промпт (общая часть, не меняется)
A waist-up character portrait in painterly semi-realistic historical illustration style, 15th-century Kazakh steppe. Neutral warm grey-beige background with a soft gradient and no scenery. Even soft light from the upper left, gentle rim light on the right shoulder. Muted earth palette. Period-accurate nomadic clothing, hand-stitched and worn from use. Head and shoulders centred, eyes on the upper third line, same camera distance in every variant. No lettering, no border, no modern clothing, no fantasy armour. A seventeen-year-old Kazakh horse herder boy. Sun-weathered cheeks and a faint pale line across the forehead where his hat sits, short dark hair, first soft down on the upper lip rather than a beard. He wears a plain undyed quilted chapan over a coarse shirt, a woven belt, and a simple felt hat pushed slightly back; a coiled horsehair lasso rests over one shoulder.

## Варианты эмоций
Дописывается одним предложением в конец базового промпта.

### avatar_01_zhylqyshy_calm — Спокойствие
Где используется: по умолчанию: профиль, меню, ровные сцены
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
His eyes are wide with alarm, brows drawn up and together, lips parted as if he has just drawn breath, head turned a little as if reacting to something off-frame.
```

### avatar_01_zhylqyshy_resolve — Решимость
Где используется: sc020 и sc022 решение уходить
```
His jaw is set and his brows lowered in determination, mouth a firm line, chin raised, gaze steady and unblinking.
```

### avatar_01_zhylqyshy_sorrow — Печаль
Где используется: sc022 прощание с могилами, sc025 тяжёлый переход
```
His gaze is lowered and turned slightly away, brows drawn together in quiet sadness, mouth closed and downturned, shoulders dropped.
```

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 (портрет), финал кадрируется в круг 512×512
- Steps: 24 · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Seed: один и тот же для всех пяти эмоций, записать в manifest.yaml
- Стартовые значения — подобрать на эталоне calm и дальше не менять
