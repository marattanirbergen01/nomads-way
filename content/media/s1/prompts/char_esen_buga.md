# char_esen_buga — Есен-Буга, хан Могулистана

## Достоверных портретов не существует
Прижизненных изображений Есен-Буги нет: в Дешті Қыпшақе XV века портрет с натуры не писали.
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
Чагатаид, правитель Могулистана. Более южный, «моголский» тип костюма: халат светлее, головной убор иной формы, чем у степных султанов. Лицо расчётливое, чуть настороженное — он ведёт свою игру.

## Prompt
A waist-up portrait in painterly semi-realistic historical illustration style, 15th-century Central Asian steppe. Plain warm grey-brown backdrop, soft even light from the upper left. Muted earth palette. Authentic 15th-century nomadic dress, no plate armour, no fantasy elements, no lettering. Dignified, calm, documentary in feel rather than heroic. A Moghul khan of the 15th century, a man of about forty. Shrewd, watchful expression with a faint politician's half-smile. His dress is distinctly different from the steppe sultans: a lighter ochre silk-faced robe with a patterned sash and a taller brimmed hat of Moghulistan style. Refined, calculating presence.

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 24 · Guidance (CFG): 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Seed утверждённого варианта записать в manifest.yaml и использовать во всех сценах
