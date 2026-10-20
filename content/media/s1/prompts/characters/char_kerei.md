# char_kerei — Керей-султан

## Достоверных портретов не существует
Прижизненных изображений Керея нет: в Дешті Қыпшақе XV века портрет с натуры не писали.
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
Старший из двух султанов, около пятидесяти. Усы и короткая бородка с первой сединой на подбородке, две тонкие косички у щёк, спокойный тяжёлый взгляд. Бөрік с меховым околышем, красно-золотой полосатой тульёй со скруглённым верхом и пером. Синий чапан с золотой парчой по вороту и лацканам, простой пояс с серебряной пряжкой. Никаких доспехов: он показан как правитель, а не воин.

Иконография — по прототипам, присланным Маратом 2026-09-14 (памятник в Астане и живописный
портрет пары): взяты типы головных уборов, бород, цвета одежды; конкретное произведение не копируется.

## Prompt
A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above his hat down to his waist, so head and chest fill most of the frame; eyes on the upper third line. No lettering, no border, no modern clothing, no fantasy armour. Dignified and calm, documentary in feel rather than heroic; hands not visible. Kerei, the elder of the two sultans, a Kazakh ruler of about fifty: distinctly Central Asian features — broad flat cheekbones, narrow dark eyes under straight heavy brows, a low-bridged nose, a dark moustache and a short dark goatee just beginning to grey at the chin, a stern composed face with a calm heavy gaze; two thin dark braids hang down beside his cheeks in the manner of steppe nobility. He wears a tall börik: a wide band of pale fur round the head, and above it a high crown of red and gold striped cloth rising to a rounded point, a single plume of white feathers standing at the top. Over a plain shirt he wears a deep blue chapan with a wide collar and lapels of gold brocade, wrapped across the chest, and a plain leather belt with a single silver buckle. A ruler, not a warrior.

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 4 · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Промпт переписан 2026-09-14 под каркас аватаров: стиль серии, кадр, явные черты лица,
  шапки без слова brim. Один портрет, без эмоций — второстепенные показываются кружком.
- Пробовали «низкий купол» тульи на том же seed — seed её не отпускает; утверждённый кадр
  сделан исходной формулировкой, она и оставлена.
- Перстень Абулхаира из канона не рисуется: руки вне кадра, модель рисует их хуже всего.
- Seed утверждённого варианта записать в manifest.yaml и использовать во всех сценах
