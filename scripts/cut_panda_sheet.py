#!/usr/bin/env python3
"""Нарезка листа поз панды в ассеты приложения.

Лист приходит от генератора одним изображением. Скрипт находит на нём
отдельные фигуры, приводит их к общему масштабу и кропу и кладёт в
app/assets/panda/.

    python3 scripts/cut_panda_sheet.py лист.png --names took almost ...
    python3 scripts/cut_panda_sheet.py лист.png --extra missed=отдельная.png

Две тонкости, из-за которых это скрипт, а не пара команд:

- **масштаб считается по ширине головы, а не по габариту кадра.** Поза с
  вытянутой лапой шире остальных, и подгонка по рамке сделала бы её панду
  мельче. Отдельно присланная поза подгоняется под лист по тому же признаку;
- **кроп общий для всего набора.** Обрезка каждой позы по её собственным
  краям убивает выравнивание: панда прыгала бы по экрану между моментами.

Если исходник потерял альфу (например, прошёл через мессенджер и фон
запёкся шахматкой), прозрачность восстанавливается по цвету: фон
нейтрально-серый, а шерсть тёплая, и по насыщенности они расходятся.
"""

import argparse
import os

import numpy as np
from PIL import Image
from scipy import ndimage

TARGET_H = 420
OUT_DIR = os.path.join('app', 'assets', 'panda')
DEFAULT_NAMES = [
    'took', 'almost', 'neutral', 'clap', 'neutral_dup', 'facepalm',
    'stop', 'notes', 'waiting', 'thumbs', 'sincere',
]


def with_alpha(path):
    """Изображение с альфой: своей, если она есть, иначе восстановленной."""
    im = Image.open(path)
    if im.mode == 'RGBA' and np.asarray(im)[..., 3].min() == 0:
        rgba = im
    else:
        rgb = im.convert('RGB')
        a = np.asarray(rgb).astype(int)
        sat = np.maximum.reduce([
            abs(a[..., 0] - a[..., 1]),
            abs(a[..., 1] - a[..., 2]),
            abs(a[..., 0] - a[..., 2]),
        ])
        bg = (sat <= 10) & (a.min(2) >= 200)
        lab, _ = ndimage.label(bg)
        edge = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
        edge.discard(0)
        # Только фон, связанный с краем: белые блики внутри фигуры остаются.
        outside = np.isin(lab, list(edge))
        alpha = np.where(outside, 0, 255).astype(np.uint8)
        rgba = Image.fromarray(np.dstack([np.asarray(rgb), alpha]), 'RGBA')
    return rgba


def figures(im, minpx=4000):
    lab, n = ndimage.label(np.asarray(im)[..., 3] > 0)
    sizes = ndimage.sum(np.asarray(im)[..., 3] > 0, lab, range(1, n + 1))
    out = []
    for i, s in enumerate(sizes, 1):
        if s > minpx:
            ys, xs = np.where(lab == i)
            out.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return sorted(out, key=lambda b: (round(b[1] / 150), b[0]))


def head_width(im):
    """Ширина головы: самая широкая строка в верхней шестой части фигуры."""
    al = np.asarray(im)[..., 3] > 0
    rows = np.where(al.any(1))[0]
    band = al[rows[0]:rows[0] + max(4, len(rows) // 6)]
    return band.sum(1).max()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sheet')
    ap.add_argument('--names', nargs='*', default=DEFAULT_NAMES)
    ap.add_argument('--extra', nargs='*', default=[],
                    help='имя=файл для поз, присланных отдельно')
    args = ap.parse_args()

    sheet = with_alpha(args.sheet)
    boxes = figures(sheet)
    if len(boxes) != len(args.names):
        raise SystemExit(
            f'на листе {len(boxes)} фигур, а имён {len(args.names)} — '
            'сверьте --names с порядком слева направо, сверху вниз')

    crops = [(n, sheet.crop(b)) for n, b in zip(args.names, boxes)]
    scale = min(900 / max(c.width for _, c in crops),
                800 / max(c.height for _, c in crops))
    ref_head = np.mean([head_width(c) * scale for _, c in crops])

    scaled = [(n, c.resize((round(c.width * scale), round(c.height * scale)),
                           Image.LANCZOS)) for n, c in crops]
    for pair in args.extra:
        name, path = pair.split('=', 1)
        im = with_alpha(path)
        c = im.crop(max(figures(im), key=lambda b: (b[2] - b[0]) * (b[3] - b[1])))
        s = ref_head / head_width(c)
        scaled.append((name, c.resize((round(c.width * s), round(c.height * s)),
                                      Image.LANCZOS)))

    # Общая рамка на весь набор — иначе позы разъедутся по вертикали.
    xs0 = ys0 = 10 ** 9
    xs1 = ys1 = -1
    for _, c in scaled:
        ys, xs = np.where(np.asarray(c)[..., 3] > 0)
        xs0, ys0 = min(xs0, xs.min()), min(ys0, ys.min())
        xs1, ys1 = max(xs1, xs.max() + 1), max(ys1, ys.max() + 1)

    os.makedirs(OUT_DIR, exist_ok=True)
    for name, c in scaled:
        if name.endswith('_dup'):
            continue
        pad = Image.new('RGBA', (xs1 - xs0, ys1 - ys0), (0, 0, 0, 0))
        pad.paste(c, (-xs0, -ys0), c)
        k = TARGET_H / pad.height
        pad = pad.resize((round(pad.width * k), TARGET_H), Image.LANCZOS)
        # Палитра вместо труколора: арт плоский, на экране живёт в ~120 точек.
        alpha = pad.getchannel('A')
        out = pad.convert('RGB').quantize(colors=64).convert('RGBA')
        out.putalpha(alpha)
        path = os.path.join(OUT_DIR, f'panda_{name}.png')
        out.save(path, optimize=True)
        print(f'{path}  {out.size}  {os.path.getsize(path) // 1024} KB')


if __name__ == '__main__':
    main()
