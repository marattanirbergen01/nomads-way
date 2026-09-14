# art_s1e01_045_river — Послесловие — вариант «юрта у реки»

Вариант `art_s1e01_045` для игрока, поставившего юрту у реки (флаг `practical`). ТО ЖЕ МЕСТО, что
`art_s1e01_032_river`, в сумерках и без коней — делается img2img от утверждённого дневного кадра
на его seed, чтобы юрта и берег совпали. Показывается вместо основного `045`, когда формат научится выбирать арт по флагу — см. DECISIONS 2026-09-13.

Модель: **FLUX.2 [klein] 4B 8-bit** (Draw Things). Промпт сплошным текстом. Юрты — гладкий купол,
шанырак вровень с войлоком, слово `brim`/`crowns` не употреблять. Людей в кадре нет.

## Prompt
A painterly semi-realistic historical illustration of the 15th-century Kazakh steppe. Muted earth palette — ochre, dust, faded indigo, weathered leather brown — under a wide cool sky, soft volumetric light, wide cinematic composition with a low horizon. Felt yurts as low round tents of white felt: a straight drum wall and a smooth shallow domed roof closing at the very top in a small flat wooden ring that lies flush with the felt, the roofline clean and unbroken. Short sturdy steppe horses. No plate armour, no fantasy elements, no modern objects, no lettering anywhere in the image. The same place as the day scene, now at dusk after sunset: a last band of warm light low on the horizon under a sky filling with stars. A single felt yurt of ordinary family size on the grassy bank of a river, its felt pale in the dusk, a warm glow of firelight at its door, the roof ring closed and the air above every roof clear and still. The horses are gone; the bank is empty. Across the river the yurts of the camp stand dark with small fires glowing low among them, the sky above the roofs clear, the snow-capped Tian Shan a pale line on the horizon. The whole picture is landscape only: no people anywhere in the frame.

## Замечание по кадру
Людей в кадре нет: персонажей кладёт плеер (бюст аватара, кружок говорящего).

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 1344×768 (16:9) · Steps: 4 · Guidance: 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Seed: записать в manifest.yaml после утверждения кадра
