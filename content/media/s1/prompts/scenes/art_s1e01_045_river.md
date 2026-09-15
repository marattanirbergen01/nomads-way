# art_s1e01_045_river — Послесловие — вариант «юрта у реки»

Вариант `art_s1e01_045` для игрока, поставившего юрту у реки (флаг `practical`). ТО ЖЕ МЕСТО, что
`art_s1e01_032_river`, в сумерках и без коней — делается img2img от утверждённого дневного кадра
на его seed, чтобы юрта и берег совпали. Показывается вместо основного `045`, когда формат научится выбирать арт по флагу — см. DECISIONS 2026-09-13.

Модель: **FLUX.2 [klein] 4B 8-bit** (Draw Things). Промпт сплошным текстом. Юрты — гладкий купол,
шанырак вровень с войлоком, слово `brim`/`crowns` не употреблять. Людей в кадре нет.

## Prompt
A painterly semi-realistic historical illustration of the 15th-century Kazakh steppe. Muted earth palette — ochre, dust, faded indigo, weathered leather brown — under a wide cool sky, soft volumetric light, a tall vertical composition for a phone screen: sky in the upper third, the action in the middle third, the ground running out of the bottom of the frame. Felt yurts as low round tents of white felt: a straight drum wall and a smooth shallow domed roof closing at the very top in a small flat wooden ring that lies flush with the felt, the roofline clean and unbroken, the air above every roof clear and still. Short sturdy steppe horses. No plate armour, no fantasy elements, no modern objects, no lettering anywhere in the image. The same place as the day scene, now deep in the night, well after dusk: the sky dark navy and thick with stars, only the faintest cold trace of light left along the horizon, the mountains black against it, the grass and the yurt sunk in blue shadow so that the firelight in the door is the brightest thing in the picture. A single felt yurt of ordinary family size stands on the grassy left bank of a river that runs along ONE side of it only, down the right of the frame; its door is the height of a standing man; a warm glow of firelight shows at the door, the air above the roof clear and still. The horses are gone; the bank is empty. Behind the yurt, small in the distance, the rest of the camp's yurts stand dark with small fires glowing low among them, the only points of light in the dark plain, the snow-capped Tian Shan a pale line on the horizon. The whole picture is landscape only: no people anywhere in the frame.

## Замечание по кадру
Правка Марата 2026-09-15: первый сумеречный вариант вышел слишком светлым — теперь глубокая ночь,
свет в двери — самое яркое пятно кадра.

Вертикаль 9:16 и без дыма над юртами (правила 2026-09-15).

Людей в кадре нет: персонажей кладёт плеер (бюст аватара, кружок говорящего).

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 768×1344 (9:16, вертикально — решение 2026-09-15) · Steps: 4 · Guidance: 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Seed: записать в manifest.yaml после утверждения кадра
