# 把 out/ 里的变体拼成带标签的对比图 sheets/*.png（两列，每张缩到 1200 宽）
import pathlib, sys
from PIL import Image, ImageDraw, ImageFont
D = pathlib.Path(__file__).parent
FONT = next(p for p in ["/System/Library/Fonts/Hiragino Sans GB.ttc", "/System/Library/Fonts/STHeiti Medium.ttc",
                        "/System/Library/Fonts/Helvetica.ttc"] if pathlib.Path(p).exists())
f = ImageFont.truetype(FONT, 30)
SHEETS = {
    "fonts": [("font-newyork", "1  New York"), ("font-iowan", "2  Iowan Old Style"), ("font-hoefler", "3  Hoefler Text"),
              ("font-baskerville", "4  Baskerville"), ("font-athelas", "5  Athelas"), ("font-didot", "6  Didot")],
    "colors": [("color-sand", "a  沙色 #D9C8A9"), ("color-slate", "b  雾蓝灰 #AEBBCB"),
               ("color-sage", "c  灰绿 #B9C4AE"), ("color-rose", "d  灰玫瑰 #D4B8B0")],
    "layouts": [("layout-L1", "L1  左文右窗"), ("layout-L2", "L2  左窗右文"), ("layout-L3", "L3  居中面板"),
                ("layout-L4", "L4  小窗多留白"), ("layout-L5", "L5  面板出血")],
}
W, H, LAB, GAP = 1200, 480, 56, 24
(D / "sheets").mkdir(exist_ok=True)
for name, items in SHEETS.items():
    rows = (len(items) + 1) // 2
    sheet = Image.new("RGB", (W * 2 + GAP * 3, rows * (H + LAB + GAP) + GAP), "#F2F1EC")
    d = ImageDraw.Draw(sheet)
    for i, (fn, label) in enumerate(items):
        x, y = GAP + (i % 2) * (W + GAP), GAP + (i // 2) * (H + LAB + GAP)
        d.text((x, y + 8), label, fill="#222", font=f)
        sheet.paste(Image.open(D / "out" / f"{fn}.png").resize((W, H), Image.LANCZOS), (x, y + LAB))
    sheet.save(D / "sheets" / f"{name}.png")
    print(name, sheet.size)
