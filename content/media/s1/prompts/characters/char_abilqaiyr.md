# char_abilqaiyr — Абулхаир-хан

## Достоверных портретов не существует
Прижизненных изображений Абулхаира нет: в Дешті Қыпшақе XV века портрет с натуры не писали.
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
Правитель Государства кочевых узбеков, около пятидесяти пяти. Массивная фигура, тяжёлое лицо, прямой тяжёлый взгляд из-под низких бровей — главное в портрете. Усы и короткая бородка с проседью. Высокая остроконечная шапка: широкий собольий околыш и синяя тулья, расшитая золотом. Тёмно-синий бархатный чапан с густой золотой вышивкой по вороту и полам, золотые застёжки, круглый золотой медальон у горла. Он не злодей: властный и уставший, а не жестокий.

Иконография — по прототипу, присланному Маратом 2026-09-15 (живописный портрет неизвестного
авторства): взяты взгляд, тип шапки и золотая вышивка; само произведение не используется —
автор и лицензия неизвестны, по STYLE.md в сборку не проходит.

## Prompt
A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above his hat down to his waist, so head and chest fill most of the frame; eyes on the upper third line. No lettering, no border, no modern clothing, no fantasy armour. Dignified and calm, documentary in feel rather than heroic; hands not visible. Abulkhair Khan, ruler of the Uzbek nomads, a heavy-built man of about fifty-five: distinctly Central Asian features — a broad heavy face, flat cheekbones, narrow dark eyes under thick black brows drawn low, a low-bridged nose, a dark moustache and a short dark goatee streaked with grey, a hard set mouth. His gaze is the centre of the portrait: level, heavy and direct, staring straight at the viewer from under the brows — the look of a man used to being obeyed, tired rather than cruel. He wears a tall pointed hat: a wide thick band of dark brown sable fur round the head, and above it a high conical crown of deep blue cloth worked all over with gold embroidery, rising to a point. Over a fine shirt he wears a rich chapan of deep blue-black velvet, its wide collar and front edges covered in dense curling gold embroidery, a row of small gold clasps down the chest, and a heavy round gold medallion on a cord at the throat. Power and weariness, not villainy.

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 4 · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Промпт переписан 2026-09-14 под каркас аватаров: стиль серии, кадр, явные черты лица,
  шапки без слова brim. Один портрет, без эмоций — второстепенные показываются кружком.
- Перстень Абулхаира из канона не рисуется: руки вне кадра, модель рисует их хуже всего.
- Seed утверждённого варианта записать в manifest.yaml и использовать во всех сценах
