"""生成 Resources/AppIcon.png（1024×1024），打包时由 bundle.sh 转成 .icns。

用法：python3 scripts/make_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # 超采样倍数，最后缩小得到平滑边缘
N = 1024 * S


def rounded(draw, box, r, fill):
    draw.rounded_rectangle([v * S for v in box], radius=r * S, fill=fill)


def gradient(size, top, bottom):
    img = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / (size - 1)
        img.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return img.resize((size, size))


def main():
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # 阴影 + 圆角底板（macOS 图标网格：824px 主体，四周留白）
    body = (100, 100, 924, 924)
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    rounded(ImageDraw.Draw(shadow), (100, 118, 924, 942), 186, (0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18 * S)))

    mask = Image.new("L", (N, N), 0)
    rounded(ImageDraw.Draw(mask), body, 186, 255)
    bg = gradient(N, (76, 92, 255), (40, 26, 140))
    canvas.paste(bg, (0, 0), mask)

    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 顶部“菜单栏”：半透明白条，右侧几个图标点和折叠箭头
    rounded(d, (190, 340, 834, 440), 50, (255, 255, 255, 80))
    for x in (560, 630, 700):
        rounded(d, (x - 18, 372, x + 18, 408), 10, (255, 255, 255, 235))
    w = 9 * S
    d.line([(782 * S, 364 * S), (760 * S, 390 * S), (782 * S, 416 * S)], fill=(255, 255, 255, 235), width=w, joint="curve")
    d.line([(735 * S, 360 * S), (735 * S, 420 * S)], fill=(255, 255, 255, 120), width=5 * S)

    # 下方弹出的小面板：收起来的图标
    panel_shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    rounded(ImageDraw.Draw(panel_shadow), (300, 530, 834, 700), 44, (10, 0, 60, 110))
    layer.alpha_composite(panel_shadow.filter(ImageFilter.GaussianBlur(16 * S)))
    rounded(d, (300, 510, 834, 680), 44, (255, 255, 255, 245))
    colors = [(76, 92, 255), (124, 92, 255), (64, 160, 255), (40, 26, 140)]
    for i, c in enumerate(colors):
        x = 370 + i * 132
        rounded(d, (x - 34, 561, x + 34, 629), 18, c + (255,))

    # 面板上方的小三角，指向折叠箭头
    d.polygon([(745 * S, 512 * S), (771 * S, 480 * S), (797 * S, 512 * S)], fill=(255, 255, 255, 245))

    clipped = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", (N, N), 0), mask))
    canvas.alpha_composite(clipped)

    out = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.png"
    canvas.resize((1024, 1024), Image.LANCZOS).save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
