# char_zhanibek — Жанибек-султан

## Достоверных портретов не существует
Прижизненных изображений Жанибека нет: в Дешті Қыпшақе XV века портрет с натуры не писали.
Всё, что ходит по интернету и учебникам, — это работы художников XX–XXI веков, памятники,
кадры из фильмов и рисунки на банкнотах. Похожести на реальное лицо добиться нельзя,
потому что сравнивать не с чем.

Достижима другая цель, и она важнее: **один и тот же узнаваемый персонаж во всех сценах серии
и всех серий сезона**. Для этого мы сами назначаем канон: генерируем портрет, историк его визирует,
и дальше он становится эталоном.

## Как закрепить канон
1. Сгенерировать 4–6 вариантов по промпту ниже, выбрать один.
2. Показать историку вместе с описанием одежды. Виза ставится на конкретный файл.
3. Записать seed утверждённого кадра в manifest.yaml — с ним воспроизводится тот же типаж.
4. Дальше в сценах: тот же seed + описание из блока «Канон внешности» слово в слово.
5. Если персонаж нужен часто и крупно — обучить маленькую LoRA на 8–12 утверждённых портретах.
   Это единственный по-настоящему надёжный способ держать лицо на дистанции всей серии.

Важно: в сценах серии лица идут средним планом и со спины, крупных портретов почти нет.
Это сделано специально — так расхождение между кадрами не бросается в глаза.

## Канон внешности (переносить в промпты сцен дословно)
Младший из двух, около сорока — на десять лет моложе Керея. Усы и небольшая острая чёрная бородка без седины, живое лицо, прямая осанка. Круглая шапка со светлой тульёй, синим околышем и пером. Светло-золотой чапан с мягким орнаментом, на поясе нож в простых ножнах.

Иконография — по прототипам, присланным Маратом 2026-09-14 (памятник в Астане и живописный
портрет пары): взяты типы головных уборов, бород, цвета одежды; конкретное произведение не копируется.

## Prompt
A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above his hat down to his waist, so head and chest fill most of the frame; eyes on the upper third line. No lettering, no border, no modern clothing, no fantasy armour. Dignified and calm, documentary in feel rather than heroic; hands not visible. Zhanibek, the younger of the two sultans, a Kazakh ruler of about forty: distinctly Central Asian features — broad flat cheekbones, narrow dark eyes with a pronounced epicanthic fold, a low-bridged nose, straight black brows, a dark moustache and a small pointed black goatee without a trace of grey, an alert lively face and an upright bearing. He wears a rounded cap fitting close to the head, its crown of pale cream cloth and its band of deep blue, a single plume of white feathers standing at the front. Over a plain shirt he wears a chapan of pale gold cloth with a soft curling ornament woven into it, wrapped across the chest, a leather belt, and at the belt a knife in a plain leather sheath. Visibly younger than Kerei, by about ten years.

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 4 · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Промпт переписан 2026-09-14 под каркас аватаров: стиль серии, кадр, явные черты лица,
  шапки без слова brim. Один портрет, без эмоций — второстепенные показываются кружком.
- Пробовали «за сорок, морщины, первая седина» — на том же seed возраст не меняется, на новых
  seed лица хуже; утверждённый кадр сделан исходной формулировкой, она и оставлена.
- Перстень Абулхаира из канона не рисуется: руки вне кадра, модель рисует их хуже всего.
- Seed утверждённого варианта записать в manifest.yaml и использовать во всех сценах
