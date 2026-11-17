#!/usr/bin/env python3
"""Prepare photos for the Kobo Touch C photo frame: grayscale, exact screen size, 16 levels with dithering.

Usage (on the PC; needs Pillow:  pip install pillow):
    python prepare_photos.py SOURCE_DIR DEST_DIR                      # portrait 600x800, fills the whole screen
    python prepare_photos.py SOURCE DEST --landscape --rotate 90      # landscape photos, Kobo turned sideways
    python prepare_photos.py SOURCE DEST --fit                        # no cropping, white borders

Then copy the contents of DEST_DIR to  E:\\.frame\\photos\\
"""
import argparse, sys
from pathlib import Path
from PIL import Image, ImageOps

EXT = {'.jpg', '.jpeg', '.png', '.bmp', '.webp', '.tif', '.tiff'}

def gray_palette(n):
    pal = Image.new('P', (1, 1))
    vals = [round(i * 255 / (n - 1)) for i in range(n)]
    flat = []
    for v in vals:
        flat += [v, v, v]
    flat += [0, 0, 0] * (256 - n)
    pal.putpalette(flat)
    return pal

def prepare(img, width, height, fit, levels, rotate):
    img = ImageOps.exif_transpose(img).convert('L')
    if fit:
        img = ImageOps.contain(img, (width, height), Image.LANCZOS)
        canvas = Image.new('L', (width, height), 255)
        canvas.paste(img, ((width - img.width) // 2, (height - img.height) // 2))
        img = canvas
    else:
        img = ImageOps.fit(img, (width, height), Image.LANCZOS, centering=(0.5, 0.5))
    img = ImageOps.autocontrast(img, cutoff=1)
    if levels < 256:
        img = img.convert('RGB').quantize(palette=gray_palette(levels), dither=Image.FLOYDSTEINBERG).convert('L')
    if rotate:
        img = img.rotate(rotate, expand=True)   # counter-clockwise
    return img

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('source'); ap.add_argument('dest')
    ap.add_argument('--landscape', action='store_true', help='lay the photo out as landscape (800x600) and rotate it afterwards')
    ap.add_argument('--rotate', type=int, choices=(0, 90, 180, 270), default=0, help='final rotation in degrees (counter-clockwise)')
    ap.add_argument('--fit', action='store_true', help='do not crop: whole photo with white borders')
    ap.add_argument('--levels', type=int, default=16, help='gray levels (16 = what the Kobo Touch shows; 256 = no reduction)')
    ap.add_argument('--size', default='600x800', help='screen size WIDTHxHEIGHT as reported in the log (default 600x800)')
    a = ap.parse_args()

    w, h = (int(x) for x in a.size.lower().split('x'))
    if a.landscape:
        w, h = max(w, h), min(w, h)
        if a.rotate == 0:
            a.rotate = 90
    src, dst = Path(a.source), Path(a.dest)
    if not src.is_dir():
        sys.exit(f'Source folder does not exist: {src}')
    dst.mkdir(parents=True, exist_ok=True)
    photos = sorted(p for p in src.iterdir() if p.suffix.lower() in EXT)
    if not photos:
        sys.exit('No images found in the source folder')
    for i, p in enumerate(photos, 1):
        with Image.open(p) as im:
            out = prepare(im, w, h, a.fit, a.levels, a.rotate)
        target = dst / f'{i:03d}.png'
        out.save(target, optimize=True)
        print(f'{p.name} -> {target.name} ({out.width}x{out.height})')
    print(f'Done: {len(photos)} photos in {dst}')

if __name__ == '__main__':
    main()
