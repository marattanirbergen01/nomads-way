# char_shaibani — Мұхаммед Шайбани

## Откуда образ
Единственный известный портрет — миниатюра, приписываемая Бехзаду (около 1507 г., Metropolitan Museum,
«Portrait of Muhammad Khan Shaibani, the Uzbek»; commons.wikimedia.org/wiki/File:Muhammad_Shaybani.jpg):
полное круглое лицо, короткие усы и бородка по скуле, большая белая чалма вокруг красной шапочки,
голубой халат с рядом золотых пуговиц, зелёные нижние рукава, жёлтый кушак. Берём эти узнаваемые
приметы, но моложе — в серии он появляется около двадцати пяти (sc020, sc040).

**Расхождение с брифом сценариста:** в брифах sc020 и sc110 у Шайбани «чёрная шапка». На единственном
портрете — белая чалма с красным верхом; её и делаем сквозным знаком (въезд в Сыгнак, чалма на песке
под Мервом). В репликах цвет шапки не звучит — менять текст не нужно.

## Канон внешности (переносить в промпты сцен дословно)
Около двадцати пяти. Полное круглое лицо, короткие чёрные усы и тонкая бородка по скуле, холодный неподвижный взгляд. Большая белая чалма, из-под которой сверху видна красная шапочка. Голубой халат с рядом мелких золотых пуговиц, зелёные нижние рукава, жёлтый кушак.

## Prompt
A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. Late 15th-century Kazakh steppe and Syr Darya towns. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above the headdress down to the waist, so head and chest fill most of the frame; eyes on the upper third line. No lettering, no border, no modern clothing, no fantasy armour. Dignified, documentary in feel rather than heroic; hands not visible. Muhammad Shaibani, a young Turkic-Mongol prince of about twenty-five, grandson of Abulkhair: a full round face with broad cheekbones and narrow dark eyes, a short black moustache and a thin short black beard running along the line of the jaw, a cold, still, calculating gaze. He wears a large white turban wound in thick round folds, with a small red cap showing at its top. A pale blue robe fastened down the chest with a row of small round gold buttons, green undersleeves at the wrists, a yellow sash at the waist. Composed, ambitious, dangerous.

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 4 · Guidance: 1.0 · Sampler: Euler A Trailing · Shift: 3.0 · Negative: пусто
- Один портрет, без эмоций: второстепенный персонаж показывается кружком (правило 2026-09-15).
- Каркас как у char_kerei: стиль серии, кадр по пояс, черты лица утверждением, слово `brim` не употреблять.
- Seed утверждённого кадра записать в manifest.yaml; канон внешности переносить в сцены дословно.
