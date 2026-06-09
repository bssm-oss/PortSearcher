#!/usr/bin/env python3
"""
SVG → PNG 아이콘 세트 + .icns 생성
사용: python3 make_icons.py
"""
import os, subprocess, shutil
from pathlib import Path

HERE = Path(__file__).parent
SVG  = HERE / "icon.svg"
OUT  = HERE / "iconset"
OUT.mkdir(exist_ok=True)

# macOS 아이콘셋 필요 사이즈
SIZES = [16, 32, 64, 128, 256, 512, 1024]

def svg_to_png(svg_path, out_path, size):
    """Python + PIL 로 SVG → PNG (cairosvg 없을 때 sips 우회)"""
    # 1차 시도: cairosvg
    try:
        import cairosvg
        cairosvg.svg2png(url=str(svg_path), write_to=str(out_path),
                         output_width=size, output_height=size)
        return
    except Exception:
        pass

    # 2차 시도: rsvg-convert
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size),
                        "-o", str(out_path), str(svg_path)], check=True)
        return

    # 3차: Python PIL 로 SVG 없이 직접 그리기 (로고 재현)
    from PIL import Image, ImageDraw, ImageFont
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = size

    # 배경
    draw.rounded_rectangle([0, 0, s-1, s-1], radius=int(s*0.22),
                            fill=(26, 31, 46, 255))

    # 돋보기 원
    cx, cy = int(s*0.48), int(s*0.48)
    r = int(s*0.26)
    lw = max(3, int(s*0.037))
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(79, 158, 255, 240), width=lw)

    # 돋보기 손잡이
    x0 = cx + int(r * 0.72)
    y0 = cy + int(r * 0.72)
    x1 = cx + int(r * 1.38)
    y1 = cy + int(r * 1.38)
    draw.line([x0, y0, x1, y1], fill=(79, 158, 255, 240), width=lw)

    # 중앙 포트 텍스트
    if s >= 64:
        fs = max(8, int(s * 0.11))
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", fs)
        except Exception:
            font = ImageFont.load_default()
        text = "8080"
        bb = draw.textbbox((0,0), text, font=font)
        tw, th = bb[2]-bb[0], bb[3]-bb[1]
        draw.text((cx - tw//2, cy - th//2), text,
                  fill=(100, 210, 255, 220), font=font)

    # 네트워크 노드 점
    dots = [(0.50, 0.22), (0.25, 0.67), (0.75, 0.67)]
    for nx, ny in dots:
        nr = max(3, int(s*0.033))
        px, py = int(s*nx), int(s*ny)
        draw.ellipse([px-nr, py-nr, px+nr, py+nr], fill=(79, 158, 255, 200))

    img.save(str(out_path), "PNG")

# PNG 생성
print("PNG 생성 중...")
for size in SIZES:
    path = OUT / f"icon_{size}x{size}.png"
    svg_to_png(SVG, path, size)
    print(f"  ✓ {size}x{size}")

    # @2x 복사 (절반 사이즈용)
    if size <= 512:
        path2x = OUT / f"icon_{size//2}x{size//2}@2x.png"
        shutil.copy(path, path2x)

# .iconset 폴더 형식으로 이름 변환
ICONSET = HERE / "AppIcon.iconset"
ICONSET.mkdir(exist_ok=True)

mapping = {
    16:   ["icon_16x16.png"],
    32:   ["icon_16x16@2x.png", "icon_32x32.png"],
    64:   ["icon_32x32@2x.png"],
    128:  ["icon_128x128.png"],
    256:  ["icon_128x128@2x.png", "icon_256x256.png"],
    512:  ["icon_256x256@2x.png", "icon_512x512.png"],
    1024: ["icon_512x512@2x.png"],
}

for size, names in mapping.items():
    src = OUT / f"icon_{size}x{size}.png"
    for name in names:
        shutil.copy(src, ICONSET / name)

# .icns 생성
print("\n.icns 생성 중...")
icns_path = HERE / "AppIcon.icns"
result = subprocess.run(
    ["iconutil", "-c", "icns", str(ICONSET), "-o", str(icns_path)],
    capture_output=True, text=True
)
if result.returncode == 0:
    print(f"  ✅ AppIcon.icns 생성 완료")
else:
    print(f"  ⚠️  iconutil 오류: {result.stderr}")

# 1024 PNG도 루트에 복사 (GitHub README용)
shutil.copy(OUT / "icon_1024x1024.png", HERE / "icon.png")
print(f"  ✅ icon.png (1024×1024) — README용")
print(f"\n완료! logo/ 폴더 확인")
