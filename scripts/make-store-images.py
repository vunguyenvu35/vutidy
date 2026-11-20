#!/usr/bin/env python3
"""Dựng ảnh cover (1280x720) và thumbnail (600x600) cho trang bán hàng (Gumroad…) từ ảnh hero của README và ký hiệu chữ V.

    /usr/bin/python3 scripts/make-store-images.py

Cần Pillow. Ra docs/assets/marketing/gumroad-cover.png và gumroad-thumbnail.png. Phông Avenir Next có sẵn trên macOS.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/assets/marketing")
HERO = os.path.join(ROOT, "docs/assets/screens/smart-scan-hero.webp")
AVENIR = "/System/Library/Fonts/Avenir Next.ttc"
BOLD, DEMI, MEDIUM, REGULAR, HEAVY = 0, 2, 5, 7, 8

BLUE, GREEN, BAR = (90, 169, 255), (61, 220, 151), (237, 240, 244)


def font(index, size):
    return ImageFont.truetype(AVENIR, size, index=index)


def gradient(size, top, bottom):
    w, h = size
    base = Image.new("RGB", size, top)
    px = base.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return base


def glow(img, center, radius, color, alpha):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    img.alpha_composite(layer)


def background(size):
    img = gradient(size, (30, 11, 58), (74, 24, 130)).convert("RGBA")
    w, h = size
    glow(img, (int(w * 0.80), int(h * 0.18)), int(h * 0.55), (150, 70, 220), 150)
    glow(img, (int(w * 0.10), int(h * 0.95)), int(h * 0.45), (40, 110, 220), 110)
    return img


def v_glyph(px):
    """Chữ V hai màu (xanh dương | xanh lá) kèm thanh trắng, vẽ ở 4x rồi thu nhỏ cho mịn. Toạ độ theo LogoMark trong app."""
    s = 4
    n = 1024 * s
    k = s
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))

    def stroke(color, clip_x0, clip_x1):
        part = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(part)
        pts = [(292 * k, 347 * k), (512 * k, 677 * k), (732 * k, 347 * k)]
        w = 92 * k
        d.line(pts, fill=color + (255,), width=w, joint="curve")
        for (x, y) in pts:
            d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=color + (255,))
        mask = Image.new("L", (n, n), 0)
        ImageDraw.Draw(mask).rectangle((clip_x0 * k, 0, clip_x1 * k, n), fill=255)
        part.putalpha(ImageChops.multiply(part.getchannel("A"), mask))
        layer.alpha_composite(part)

    stroke(BLUE, 0, 512)
    stroke(GREEN, 512, 1024)
    ImageDraw.Draw(layer).rounded_rectangle((437 * k, 327 * k, 587 * k, 419 * k), radius=20 * k, fill=BAR + (255,))
    box = layer.getbbox()
    layer = layer.crop(box)
    scale = px / max(layer.size)
    return layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))), Image.LANCZOS)


def glass_tile(img, xy, size, glyph_ratio=0.62):
    x, y = xy
    r = int(size * 0.28)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + size * 0.05, x + size, y + size * 1.05), radius=r, fill=(0, 0, 0, 120))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(size * 0.08)))
    tile = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    d.rounded_rectangle((x, y, x + size, y + size), radius=r, fill=(255, 255, 255, 34), outline=(255, 255, 255, 110), width=max(2, size // 60))
    img.alpha_composite(tile)
    g = v_glyph(int(size * glyph_ratio))
    img.alpha_composite(g, (x + (size - g.width) // 2, y + (size - g.height) // 2))


def text(d, xy, s, fnt, fill, anchor="la"):
    d.text(xy, s, font=fnt, fill=fill, anchor=anchor)


def pill(img, xy, label, fnt):
    d = ImageDraw.Draw(img)
    pad_x, pad_y = 18, 9
    bbox = d.textbbox((0, 0), label, font=fnt)
    w, h = bbox[2] - bbox[0] + 2 * pad_x, bbox[3] - bbox[1] + 2 * pad_y
    x, y = xy
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(255, 255, 255, 28), outline=(255, 255, 255, 90), width=1)
    img.alpha_composite(layer)
    ImageDraw.Draw(img).text((x + pad_x, y + pad_y - bbox[1]), label, font=fnt, fill=(255, 255, 255, 235))
    return w


def cover():
    W, H = 1280, 720
    img = background((W, H))
    d = ImageDraw.Draw(img)

    # Ảnh cửa sổ app bên phải, tràn nhẹ ra mép phải
    hero = Image.open(HERO).convert("RGBA")
    hw = 740
    hero = hero.resize((hw, int(hero.height * hw / hero.width)), Image.LANCZOS)
    img.alpha_composite(hero, (W - hw + 56, (H - hero.height) // 2 + 36))

    # Cột chữ bên trái
    glass_tile(img, (72, 70), 76)
    d = ImageDraw.Draw(img)
    text(d, (164, 108), "Vutidy", font(DEMI, 40), (255, 255, 255, 255), "lm")

    # Ba dòng để cột chữ không chạm cửa sổ app bên phải
    text(d, (72, 190), "See what", font(HEAVY, 62), (255, 255, 255, 255))
    text(d, (72, 258), "it removes.", font(HEAVY, 62), (255, 255, 255, 255))
    text(d, (72, 326), "Undo anything.", font(HEAVY, 62), (124, 240, 184, 255))
    text(d, (72, 436), "A cleaner and optimizer for macOS", font(MEDIUM, 25), (255, 255, 255, 215))
    text(d, (72, 472), "that shows every step before it runs.", font(MEDIUM, 25), (255, 255, 255, 215))

    f = font(DEMI, 21)
    x = 72
    for label in ("No account", "No telemetry", "Open source"):
        x += pill(img, (x, 540), label, f) + 12
    text(ImageDraw.Draw(img), (72, 622), "macOS 13+   ·   Apple silicon and Intel", font(MEDIUM, 21), (255, 255, 255, 150))
    return img.convert("RGB")


def thumbnail():
    S = 600
    img = background((S, S))
    glass_tile(img, ((S - 248) // 2, 96), 248)
    d = ImageDraw.Draw(img)
    text(d, (S // 2, 410), "Vutidy", font(HEAVY, 92), (255, 255, 255, 255), "mm")
    text(d, (S // 2, 486), "Mac cleaner with undo", font(MEDIUM, 31), (255, 255, 255, 215), "mm")
    f = font(DEMI, 20)
    lab = "No account  ·  No telemetry"
    text(d, (S // 2, 540), lab, f, (124, 240, 184, 235), "mm")
    return img.convert("RGB")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    cover().save(os.path.join(OUT, "gumroad-cover.png"), optimize=True)
    thumbnail().save(os.path.join(OUT, "gumroad-thumbnail.png"), optimize=True)
    print("ok ->", OUT)
