# 海报 v4 素材管线：仓库壁纸 + 真机截图局部 → assets/canvas-<tag>.jpg（面板已贴回原位的大画布）
# 依赖 Pillow + numpy。截图来自 5K 主屏（5120×2880），面板窗口原点 (1902,38) pt。
# 玻璃由窗口服务器绘制，窗口截图的 alpha 只有文字有值，所以面板按矩形区域羽化贴回它在壁纸上的原位置，
# 玻璃里透出的就是同一块壁纸，接缝不可见。画布向上、向右镜像延伸，海报再按布局从画布上取景。
import json
import pathlib
import numpy as np
from PIL import Image, ImageFilter

D = pathlib.Path(__file__).parent
ROOT = D.parent.parent
CAP, OUT = D / "captures", D / "assets"
OUT.mkdir(exist_ok=True)
WALLS = {"dark": "wallhaven-4k_24090.jpg", "light": "wallhaven-4k_26311.jpg"}
PANEL_ORIGIN, CALIB_ORIGIN = (3757, 70), (2620, 90)
PANEL_TILES = (3827, 93, 4589, 962)   # 面板瓷砖外接矩形（屏幕像素）
EXT_TOP, EXT_RIGHT = 700, 2500


def wallpaper(tag):
    w = Image.open(ROOT / "screenshots/backgrounds" / WALLS[tag]).convert("RGB")
    return w if w.size == (5120, 2880) else w.resize((5120, 2880), Image.LANCZOS)


def color_matched(tag):
    """按干净桌面条带逐通道线性拟合，消除截图与壁纸文件的色彩配置差。"""
    w = np.asarray(wallpaper(tag)).astype(np.float64)
    strip = np.asarray(Image.open(CAP / f"{tag}-calib-strip.png")).astype(np.float64)
    x0, y0 = CALIB_ORIGIN
    ref = w[y0:y0 + strip.shape[0], x0:x0 + strip.shape[1]]
    for c in range(3):
        a, b = np.polyfit(ref[..., c].ravel(), strip[..., c].ravel(), 1)
        w[..., c] = w[..., c] * a + b
    return Image.fromarray(np.clip(w, 0, 255).astype(np.uint8))


def build(tag):
    clean = color_matched(tag)
    W, H = 5120 + EXT_RIGHT, 2880 + EXT_TOP
    canvas = Image.new("RGB", (W, H))
    canvas.paste(clean, (0, EXT_TOP))
    top = clean.crop((0, 0, 5120, EXT_TOP)).transpose(Image.FLIP_TOP_BOTTOM)
    canvas.paste(top, (0, 0))
    right = canvas.crop((5120 - EXT_RIGHT, 0, 5120, H)).transpose(Image.FLIP_LEFT_RIGHT)
    canvas.paste(right, (5120, 0))
    if tag == "dark":   # 镜像接缝上有颗亮星会被复制成一对，用左侧天空盖掉
        patch = canvas.crop((4780, 860, 4900, 980))
        m = Image.new("L", patch.size, 0)
        m.paste(255, (16, 16, 104, 104))
        canvas.paste(patch, (5060, 860), m.filter(ImageFilter.GaussianBlur(6)))
    region = Image.open(CAP / f"{tag}-panel-region.png")
    mask = Image.new("L", region.size, 0)
    mask.paste(255, (30, 10, region.width - 30, region.height - 30))
    mask = mask.filter(ImageFilter.GaussianBlur(8))
    canvas.paste(region, (PANEL_ORIGIN[0], PANEL_ORIGIN[1] + EXT_TOP), mask)
    canvas.save(OUT / f"canvas-{tag}.jpg", quality=94)


def frame(tag, panel_x, panel_y, scale=2.0, size=(1600, 640), out=None):
    """从画布取景：让面板左上角落在海报 CSS 坐标 (panel_x, panel_y)，scale = 屏幕像素 / CSS 像素。"""
    canvas = Image.open(OUT / f"canvas-{tag}.jpg")
    px, py = PANEL_TILES[0], PANEL_TILES[1] + EXT_TOP
    x0, y0 = px - panel_x * scale, py - panel_y * scale
    w, h = size[0] * scale, size[1] * scale
    assert x0 >= 0 and y0 >= 0 and x0 + w <= canvas.width and y0 + h <= canvas.height, (tag, x0, y0)
    img = canvas.crop((int(x0), int(y0), int(x0 + w), int(y0 + h)))
    if img.size != (size[0] * 2, size[1] * 2):
        img = img.resize((size[0] * 2, size[1] * 2), Image.LANCZOS)
    img.save(out, quality=93)
    tw = (PANEL_TILES[2] - PANEL_TILES[0]) / scale
    th = (PANEL_TILES[3] - PANEL_TILES[1]) / scale
    return {"w": round(tw, 1), "h": round(th, 1)}


if __name__ == "__main__":
    for t in WALLS:
        build(t)
        print("built", t)
