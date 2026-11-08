#!/usr/bin/env python3
# 批量水印工作台 / Batch Watermark Studio
# Copyright (c) 2026 KYO4926 · SPDX-License-Identifier: MIT
"""生成 macOS AppIcon.icns：渐变圆角底 + 叠放照片 + 水印徽标。"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S, AA = 1024, 4
W = S * AA


def layer():
    return Image.new("RGBA", (W, W), (0, 0, 0, 0))


def rounded_mask(box, radius):
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).rounded_rectangle(tuple(int(v) for v in box), radius=int(radius), fill=255)
    return m


img = layer()

# 1. 渐变底 + 圆角遮罩
grad = layer()
gd = ImageDraw.Draw(grad)
for y in range(W):
    t = y / W
    gd.line([(0, y), (W, y)], fill=(int(103 + 75 * t), int(126 - 16 * t), 255, 255))
base_mask = rounded_mask((56 * AA, 56 * AA, W - 56 * AA, W - 56 * AA), 185 * AA)
img.paste(grad, (0, 0), base_mask)
glow = layer()
ImageDraw.Draw(glow).ellipse((-180 * AA, -460 * AA, 1180 * AA, 430 * AA),
                             fill=(255, 255, 255, 44))
# 柔光同样限制在圆角底内，避免溢出到透明区
img.paste(glow.filter(ImageFilter.GaussianBlur(55 * AA)), (0, 0), base_mask)

# 2. 后层照片（旋转，示意「批量」）
back = layer()
ImageDraw.Draw(back).rounded_rectangle((232 * AA, 212 * AA, 792 * AA, 742 * AA),
                                      radius=52 * AA, fill=(224, 231, 252, 230))
back = back.rotate(9, resample=Image.BICUBIC, center=(W / 2, W / 2))
img.alpha_composite(back)

# 3. 前层白色卡片
d = ImageDraw.Draw(img)
d.rounded_rectangle((168 * AA, 258 * AA, 722 * AA, 746 * AA),
                    radius=54 * AA, fill=(255, 255, 255, 255))
inner = (204 * AA, 294 * AA, 686 * AA, 706 * AA)
inner_mask = rounded_mask(inner, 26 * AA)
d.rounded_rectangle(tuple(int(v) for v in inner), radius=26 * AA, fill=(232, 239, 255, 255))

# 4. 照片内容（天空 + 太阳 + 两层山），统一用圆角遮罩裁切
scene = layer()
sd = ImageDraw.Draw(scene)
for y in range(int(inner[1]), int(inner[3])):
    t = (y - inner[1]) / (inner[3] - inner[1])
    sd.line([(int(inner[0]), y), (int(inner[2]), y)],
            fill=(int(176 - 42 * t), int(202 - 38 * t), 255, 255))
sd.ellipse((548 * AA, 342 * AA, 620 * AA, 414 * AA), fill=(255, 234, 172, 255))
sd.polygon([(204 * AA, 706 * AA), (204 * AA, 546 * AA), (372 * AA, 414 * AA),
            (520 * AA, 548 * AA), (600 * AA, 486 * AA), (686 * AA, 566 * AA),
            (686 * AA, 706 * AA)], fill=(108, 142, 226, 255))
sd.polygon([(204 * AA, 706 * AA), (204 * AA, 620 * AA), (330 * AA, 524 * AA),
            (452 * AA, 618 * AA), (556 * AA, 556 * AA), (686 * AA, 646 * AA),
            (686 * AA, 706 * AA)], fill=(66, 98, 190, 255))
img.paste(scene, (0, 0), inner_mask)

# 5. 右下角水印徽标
d = ImageDraw.Draw(img)
badge = (596 * AA, 600 * AA, 884 * AA, 888 * AA)
d.ellipse((badge[0] - 14 * AA, badge[1] - 14 * AA, badge[2] + 14 * AA, badge[3] + 14 * AA),
          fill=(255, 255, 255, 255))
bg = layer()
bd = ImageDraw.Draw(bg)
for y in range(int(badge[1]), int(badge[3])):
    t = (y - badge[1]) / (badge[3] - badge[1])
    bd.line([(int(badge[0]), y), (int(badge[2]), y)],
            fill=(int(123 + 45 * t), int(140 - 20 * t), 255, 255))
bm = Image.new("L", (W, W), 0)
ImageDraw.Draw(bm).ellipse(tuple(int(v) for v in badge), fill=255)
img.paste(bg, (0, 0), bm)
d = ImageDraw.Draw(img)
cx, cy = (badge[0] + badge[2]) / 2, (badge[1] + badge[3]) / 2
lw = 22 * AA
pts = [(cx - 80 * AA, cy - 54 * AA), (cx - 46 * AA, cy + 60 * AA),
       (cx, cy - 18 * AA), (cx + 46 * AA, cy + 60 * AA), (cx + 80 * AA, cy - 54 * AA)]
d.line(pts, fill=(255, 255, 255, 255), width=int(lw), joint="curve")
for px, py in (pts[0], pts[-1]):
    r = lw / 2
    d.ellipse((px - r, py - r, px + r, py + r), fill=(255, 255, 255, 255))

# 6. 输出 iconset / icns
img = img.resize((S, S), Image.LANCZOS)
iconset = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for s in (16, 32, 128, 256, 512):
    img.resize((s, s), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}.png"))
    img.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}@2x.png"))
img.save(os.path.join(iconset, "icon_1024x1024.png"))
img.save(os.path.join(HERE, "AppIcon.png"))
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(HERE, "AppIcon.icns")], check=True)
print("icon created:", os.path.join(HERE, "AppIcon.icns"))
