# char_aksakal — Аксакал — старейшина рода

Вымышленный персонаж (`fiction: true`), с историческим лицом не связан. Второй по числу реплик
в s1e01 после рассказчика, ведёт эмоциональную линию серии. Бриф — `docs/DECISIONS.md`,
запись «Портреты говорящих» от 2026-09-10.

Показывается в том же кружке `AvatarCircle`, что и аватары игрока, поэтому общая часть промпта
и кадрирование — те же, что у аватаров. Правила те же: strength 1.0 при том же seed, steps 4,
слово `brim` не употреблять, эмоции описывать формой, эталон не править снаружи.

## Базовый промпт (общая часть, не меняется)
Такия — по фото Марата 2026-09-14: невысокая коническая тулья на прямом околыше с орнаментной
полосой, тёмно-зелёный бархат. Пояс описан полосой сукна в два оборота: «sash» даёт верёвку.

A waist-up character portrait for a historical video game, painted as a digital illustration: visible brushwork, soft edges, semi-realistic stylised features, honest natural colour. Not a photograph, no photographic skin texture, no pores, no sharp photographic detail. 15th-century Kazakh steppe. Plain warm background, a soft dusty ochre-to-grey gradient, no scenery and nothing behind the figure. Warm directional light from the upper left, gentle rim light on the right shoulder. The crop runs from just above his cap down to his waist, so head and chest fill most of the frame; eyes on the upper third line, same camera distance in every variant. No lettering, no border, no modern clothing, no fantasy armour. A Kazakh elder past sixty, head of his clan: distinctly Central Asian features — broad flat cheekbones, narrow dark eyes under heavy lids with a pronounced epicanthic fold, a low-bridged nose, deep lines at the eyes and the corners of the mouth, weathered skin darkened by a life outdoors. A full grey beard, trimmed short, and a grey moustache. He wears a takiya: a low Kazakh cap of deep muted green velvet, a short straight band round the head and above it a shallow cone rising to a soft point, the band carrying a single narrow line of quiet embroidered ornament in dull thread; the cap sits close on the head. Over a coarse undyed shirt he wears a plain quilted chapan of grey-brown cloth, wrapped across the chest, tied at the waist with a wide band of dark woven cloth wound twice round, flat and soft — no ornament anywhere on the cloth, everything worn soft with age. One hand rests on the top of a plain wooden staff at chest height. He is not rich: the voice of experience, not of power.

## Портрет — одно состояние
Второстепенным персонажам эмоции не нужны: они показываются только кружком у реплики
(решение 2026-09-14). Предложение в конец базового промпта:
```
His expression is calm and faintly amused, looking directly at the viewer, the corners of the eyes softened, mouth relaxed under the moustache.
```

## Параметры (Draw Things · FLUX.2 [klein] 4B 8-bit)
- Size: 896×1152 · Steps: 4 · Guidance: 1.0 · Sampler: Euler A Trailing · Shift: 3.0
- Seed: один и тот же для всех состояний, записать в manifest.yaml после утверждения calm
