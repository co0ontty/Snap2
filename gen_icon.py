#!/usr/bin/env python3
"""Snap² 应用图标生成器
主题：加菲猫"初二" + 截图选区
设计：橙色 squircle 背景 + 居中加菲猫脸 + 右下角 ² 选区角标
"""
from PIL import Image, ImageDraw, ImageFont
import os

APP_NAME = "Snap2"

BG_TOP    = (255, 178,  72)
BG_BOT    = (236, 124,  32)
FACE      = (255, 222, 168)
STRIPE    = (200,  96,  24)
EAR_OUT   = (228, 118,  32)
EAR_IN    = (240, 168, 168)
EYE_W     = (255, 255, 255)
PUPIL     = ( 36,  28,  20)
NOSE      = (220, 110, 130)
MOUTH     = (110,  60,  30)
WHISKER   = ( 90,  60,  40, 220)
WHITE     = (255, 255, 255, 240)


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    margin = size * 0.05
    radius = size * 0.225  # macOS Big Sur 风格圆角

    # 1. 圆角矩形 + 橙色渐变背景
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / size
        c = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        bd.line([(0, y), (size, y)], fill=c + (255,))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [int(margin), int(margin), int(size - margin), int(size - margin)],
        radius=int(radius), fill=255,
    )
    bg.putalpha(mask)
    img = Image.alpha_composite(img, bg)

    draw = ImageDraw.Draw(img)

    # 2. 加菲猫脸
    cx = size // 2
    cy = int(size * 0.50)
    face_w = int(size * 0.56)
    face_h = int(size * 0.46)

    # 耳朵（先画，会被脸部分覆盖）
    ear_h = int(size * 0.16)
    ear_w = int(size * 0.13)
    # 左耳
    lex = cx - int(face_w * 0.34)
    ley = cy - face_h // 2 + int(size * 0.04)
    left_ear = [
        (lex - ear_w // 2, ley),
        (lex + ear_w // 2, ley + int(ear_h * 0.30)),
        (lex - ear_w // 2 + int(ear_w * 0.20), ley - ear_h),
    ]
    draw.polygon(left_ear, fill=EAR_OUT)
    inner_l = [
        (lex - ear_w // 2 + int(ear_w * 0.20), ley - int(size * 0.005)),
        (lex + ear_w // 2 - int(ear_w * 0.25), ley + int(ear_h * 0.18)),
        (lex - ear_w // 2 + int(ear_w * 0.32), ley - ear_h + int(ear_h * 0.30)),
    ]
    draw.polygon(inner_l, fill=EAR_IN)
    # 右耳
    rex = cx + int(face_w * 0.34)
    rey = ley
    right_ear = [
        (rex + ear_w // 2, rey),
        (rex - ear_w // 2, rey + int(ear_h * 0.30)),
        (rex + ear_w // 2 - int(ear_w * 0.20), rey - ear_h),
    ]
    draw.polygon(right_ear, fill=EAR_OUT)
    inner_r = [
        (rex + ear_w // 2 - int(ear_w * 0.20), rey - int(size * 0.005)),
        (rex - ear_w // 2 + int(ear_w * 0.25), rey + int(ear_h * 0.18)),
        (rex + ear_w // 2 - int(ear_w * 0.32), rey - ear_h + int(ear_h * 0.30)),
    ]
    draw.polygon(inner_r, fill=EAR_IN)

    # 脸（椭圆）
    draw.ellipse(
        [cx - face_w // 2, cy - face_h // 2,
         cx + face_w // 2, cy + face_h // 2],
        fill=FACE,
    )

    # 头顶虎斑（3 道短弧）
    sw = max(2, int(size * 0.014))
    for off in (-0.10, 0.0, 0.10):
        sx = cx + int(size * off)
        sy = cy - face_h // 2 + int(size * 0.025)
        draw.arc(
            [sx - int(size * 0.030), sy,
             sx + int(size * 0.030), sy + int(size * 0.07)],
            start=200, end=340, fill=STRIPE, width=sw,
        )

    # 眼睛
    eye_y = cy - int(size * 0.04)
    eye_w = int(size * 0.085)
    eye_h = int(size * 0.105)
    pup_w = max(2, int(size * 0.024))
    pup_h = max(3, int(size * 0.035))
    py_off = int(size * 0.006)
    border = max(1, int(size * 0.006))

    for ex_off in (-0.115, 0.115):
        ex = cx + int(size * ex_off)
        draw.ellipse(
            [ex - eye_w // 2, eye_y - eye_h // 2,
             ex + eye_w // 2, eye_y + eye_h // 2],
            fill=EYE_W, outline=PUPIL, width=border,
        )
        draw.ellipse(
            [ex - pup_w, eye_y - pup_h + py_off,
             ex + pup_w, eye_y + pup_h + py_off],
            fill=PUPIL,
        )
        # 高光
        hl = max(1, int(size * 0.010))
        draw.ellipse(
            [ex - pup_w + hl, eye_y - pup_h + py_off + hl,
             ex - pup_w + hl * 3, eye_y - pup_h + py_off + hl * 3],
            fill=(255, 255, 255, 230),
        )

    # 鼻子（小三角）
    nose_y = cy + int(size * 0.06)
    nose_w = int(size * 0.030)
    nose_h = int(size * 0.025)
    draw.polygon(
        [(cx - nose_w, nose_y),
         (cx + nose_w, nose_y),
         (cx, nose_y + nose_h)],
        fill=NOSE,
    )

    # 嘴：鼻下竖线 + W 形（两段弧）
    mw = max(2, int(size * 0.011))
    draw.line(
        [(cx, nose_y + nose_h),
         (cx, nose_y + nose_h + int(size * 0.025))],
        fill=MOUTH, width=mw,
    )
    arc_w = int(size * 0.045)
    arc_h = int(size * 0.045)
    arc_y = nose_y + nose_h + int(size * 0.025)
    draw.arc(
        [cx - arc_w, arc_y - arc_h // 2,
         cx,         arc_y + arc_h // 2],
        start=0, end=180, fill=MOUTH, width=mw,
    )
    draw.arc(
        [cx,         arc_y - arc_h // 2,
         cx + arc_w, arc_y + arc_h // 2],
        start=0, end=180, fill=MOUTH, width=mw,
    )

    # 胡须（每边 3 道）
    ww = max(1, int(size * 0.005))
    for dy in (-0.018, 0.002, 0.022):
        wy = nose_y + int(size * dy)
        draw.line(
            [(cx - int(size * 0.13), wy),
             (cx - int(size * 0.24), wy + int(size * 0.005))],
            fill=WHISKER, width=ww,
        )
        draw.line(
            [(cx + int(size * 0.13), wy),
             (cx + int(size * 0.24), wy + int(size * 0.005))],
            fill=WHISKER, width=ww,
        )

    # 3. 右下角：截图选区右下角 L + ² 角标（小尺寸下省略，保证清晰）
    if size >= 64:
        badge_corner_x = int(size - margin - size * 0.05)
        badge_corner_y = int(size - margin - size * 0.05)
        arm = int(size * 0.13)
        aw = max(2, int(size * 0.018))
        # L 形（选区右下角）
        draw.line([(badge_corner_x - arm, badge_corner_y),
                   (badge_corner_x,       badge_corner_y)], fill=WHITE, width=aw)
        draw.line([(badge_corner_x,       badge_corner_y - arm),
                   (badge_corner_x,       badge_corner_y)], fill=WHITE, width=aw)
        # 拐角小方块（拖拽手柄）
        h = max(3, int(size * 0.022))
        draw.rectangle(
            [badge_corner_x - h, badge_corner_y - h,
             badge_corner_x + h, badge_corner_y + h],
            fill=WHITE,
        )

        # ² 字（位于 L 角内侧）
        font_size = max(8, int(size * 0.12))
        font = None
        for fp in (
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/HelveticaNeue.ttc",
            "/System/Library/Fonts/SFNS.ttf",
            "/Library/Fonts/Arial.ttf",
        ):
            if os.path.exists(fp):
                try:
                    font = ImageFont.truetype(fp, font_size)
                    break
                except Exception:
                    pass

        if font is not None:
            # 优先用 unicode 上标 ²，回退到 "2"
            text = "²"
            bbox = draw.textbbox((0, 0), text, font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            if tw == 0 or th == 0:
                text = "2"
                bbox = draw.textbbox((0, 0), text, font=font)
                tw = bbox[2] - bbox[0]
                th = bbox[3] - bbox[1]
            tx = badge_corner_x - arm - int(size * 0.005) - tw
            ty = badge_corner_y - arm - th - int(size * 0.005)
            draw.text((tx, ty), text, font=font, fill=WHITE)

    return img


def main():
    out_dir = f"build_tmp/{APP_NAME}.iconset"
    os.makedirs(out_dir, exist_ok=True)

    sizes = {
        "icon_16x16.png":      16,
        "icon_16x16@2x.png":   32,
        "icon_32x32.png":      32,
        "icon_32x32@2x.png":   64,
        "icon_128x128.png":   128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png":   256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png":   512,
        "icon_512x512@2x.png": 1024,
    }

    for name, sz in sizes.items():
        make_icon(sz).save(os.path.join(out_dir, name))
        print(f"  ✓ {name} ({sz}x{sz})")

    os.system(f'iconutil -c icns "{out_dir}" -o build_tmp/{APP_NAME}.icns')
    print(f"\n  ✓ build_tmp/{APP_NAME}.icns 生成完成")

    make_icon(512).save("build_tmp/icon_preview.png")
    print(f"  ✓ build_tmp/icon_preview.png 预览图已保存")


if __name__ == "__main__":
    main()
