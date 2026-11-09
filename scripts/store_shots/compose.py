"""App Store 用スクリーンショットを、実機の素のキャプチャから組み立てる。

使い方:
    python scripts/store_shots/compose.py            # iPhone と iPad 両方
    python scripts/store_shots/compose.py --only iphone
    python scripts/store_shots/compose.py --config scripts/store_shots/shots.json

依存:
    pip install pillow

やること:
    1. shots.json の各行について、素のキャプチャ (src) を読む
    2. 端末らしい角丸と枠を付け、背景の上に置く
    3. 上に見出し (title) と補足 (subtitle) を焼き込む
    4. App Store の要求サイズ (iPhone 6.9" = 1320x2868, iPad 13" = 2064x2752) で書き出す

素のキャプチャの端末サイズは問わない。枠の中に縮めて置くので、
iPhone 13 (1170x2532) でも 6.9" の枠に収まる。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT_PATH = Path(r"C:\Windows\Fonts\NotoSansJP-VF.ttf")

# アプリの配色 (seed #6750A4 のダークテーマ) に合わせる
BG_TOP = (28, 24, 48)
BG_BOTTOM = (15, 13, 22)
GLOW = (103, 80, 164)
TITLE_COLOR = (243, 238, 255)
SUB_COLOR = (185, 176, 208)
BEZEL = (11, 10, 16)
BEZEL_EDGE = (58, 53, 80)


@dataclass(frozen=True)
class Layout:
    """端末種別ごとの寸法。単位は px"""

    canvas: tuple[int, int]
    top_pad: int
    title_size: int
    sub_size: int
    text_gap: int        # title と subtitle の間
    device_gap: int      # 文字と端末の間
    bottom_pad: int      # 端末の下に残す余白。足りなければ端末を下へはみ出させる
    screen_width: int    # 端末の画面部分の幅 (上限)
    screen_radius: int   # 画面の角丸 (縮小後)
    bezel: int           # 画面の外側の枠の太さ
    side_pad: int        # 文字の左右余白


LAYOUTS = {
    "iphone": Layout(
        canvas=(1320, 2868), top_pad=150, title_size=92, sub_size=44,
        text_gap=28, device_gap=96, bottom_pad=90, screen_width=1040,
        screen_radius=120, bezel=26, side_pad=90,
    ),
    "ipad": Layout(
        canvas=(2064, 2752), top_pad=150, title_size=96, sub_size=50,
        text_gap=28, device_gap=100, bottom_pad=90, screen_width=1700,
        screen_radius=44, bezel=34, side_pad=120,
    ),
}


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    if not FONT_PATH.exists():
        sys.exit(f"フォントが見つかりません: {FONT_PATH}")
    f = ImageFont.truetype(str(FONT_PATH), size)
    f.set_variation_by_name(weight)
    return f


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont,
         max_width: int) -> list[str]:
    """明示の改行を優先し、収まらない行は文字単位で折る (日本語前提)"""
    lines: list[str] = []
    for para in text.split("\n"):
        cur = ""
        for ch in para:
            # 句読点は行頭に来させない (ぶら下げる)
            if draw.textlength(cur + ch, font=f) <= max_width or ch in "、。，．」』）":
                cur += ch
            else:
                lines.append(cur)
                cur = ch
        lines.append(cur)
    return lines


def background(size: tuple[int, int], glow_y: int) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size, BG_BOTTOM)
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = tuple(round(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    # 端末の上あたりに淡い光を置いて、黒い枠が背景に沈まないようにする
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    r = int(w * 0.7)
    g.ellipse((w // 2 - r, glow_y - r // 2, w // 2 + r, glow_y + r // 2),
              fill=GLOW + (110,))
    glow = glow.filter(ImageFilter.GaussianBlur(w // 6))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    return img


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1),
                                        radius=radius, fill=255)
    return m


def compose(src: Path, title: str, subtitle: str, layout: Layout) -> Image.Image:
    cw, ch = layout.canvas
    shot = Image.open(src).convert("RGB")

    # 文字を先に測って、端末に使える高さを決める
    tf = font(layout.title_size, "Bold")
    sf = font(layout.sub_size, "Medium")
    measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    max_text_w = cw - layout.side_pad * 2
    title_lines = wrap(measure, title, tf, max_text_w)
    sub_lines = wrap(measure, subtitle, sf, max_text_w) if subtitle else []
    title_h = len(title_lines) * int(layout.title_size * 1.3)
    sub_h = len(sub_lines) * int(layout.sub_size * 1.5)
    text_bottom = layout.top_pad + title_h + (layout.text_gap + sub_h if sub_lines else 0)

    device_top = text_bottom + layout.device_gap
    avail_h = ch - device_top - layout.bottom_pad - layout.bezel
    # 幅いっぱいを上限に、下の余白を残して全体が収まる大きさにする
    scale = min(layout.screen_width / shot.width, avail_h / shot.height)
    screen_w = round(shot.width * scale)
    screen_h = round(shot.height * scale)

    img = background((cw, ch), glow_y=device_top + screen_h // 5)
    draw = ImageDraw.Draw(img)

    # 文字
    y = layout.top_pad
    for line in title_lines:
        lw = draw.textlength(line, font=tf)
        draw.text(((cw - lw) / 2, y), line, font=tf, fill=TITLE_COLOR)
        y += int(layout.title_size * 1.3)
    if sub_lines:
        y += layout.text_gap
        for line in sub_lines:
            lw = draw.textlength(line, font=sf)
            draw.text(((cw - lw) / 2, y), line, font=sf, fill=SUB_COLOR)
            y += int(layout.sub_size * 1.5)

    # 端末
    b = layout.bezel
    outer_w, outer_h = screen_w + b * 2, screen_h + b * 2
    x0 = (cw - outer_w) // 2
    y0 = device_top - b
    outer_r = layout.screen_radius + b

    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x0, y0 + 30, x0 + outer_w, y0 + outer_h + 30), radius=outer_r,
        fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    img = Image.alpha_composite(img, shadow)

    frame = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((x0, y0, x0 + outer_w, y0 + outer_h), radius=outer_r,
                         fill=BEZEL + (255,), outline=BEZEL_EDGE + (255,), width=2)
    img = Image.alpha_composite(img, frame)

    screen = shot.resize((screen_w, screen_h), Image.LANCZOS)
    img.paste(screen, (x0 + b, y0 + b), rounded_mask((screen_w, screen_h), layout.screen_radius))
    return img.convert("RGB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--config", default=str(ROOT / "scripts/store_shots/shots.json"))
    ap.add_argument("--only", choices=list(LAYOUTS), help="この端末だけ作る")
    ap.add_argument("--out", default=str(ROOT / "スナップショット/store"),
                    help="書き出し先。この下に iphone/ ipad/ ができる")
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text(encoding="utf-8"))
    for device, shots in cfg.items():
        if args.only and device != args.only:
            continue
        layout = LAYOUTS[device]
        out_dir = Path(args.out) / device
        out_dir.mkdir(parents=True, exist_ok=True)
        for i, s in enumerate(shots, 1):
            src = ROOT / s["src"]
            if not src.exists():
                print(f"  skip {device} {i}: 見つからない {src}")
                continue
            img = compose(src, s["title"], s.get("subtitle", ""), layout)
            out = out_dir / f"{i:02d}_{s['name']}.png"
            img.save(out, optimize=True)
            print(f"  {out.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    # Windows のコンソール (cp932) でも日本語のパスを出せるように
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    os.chdir(ROOT)
    main()
