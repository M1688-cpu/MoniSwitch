# README 海报 v4：字体 / 配色 / 布局参考稿。用法：python make.py（需先跑 assets.py 生成画布）
# 每个变体 = 从画布取景的背景 + 极简文字（应用名、标题、系统支持），Chrome headless 2x 渲染。
import json
import pathlib
import subprocess
import sys

D = pathlib.Path(__file__).parent
sys.path.insert(0, str(D))
from assets import frame  # noqa: E402

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONTS = {
    "newyork": ("New York", '"NY"'),
    "iowan": ("Iowan Old Style", '"Iowan Old Style"'),
    "hoefler": ("Hoefler Text", '"Hoefler Text"'),
    "baskerville": ("Baskerville", '"Baskerville"'),
    "athelas": ("Athelas", '"Athelas"'),
    "didot": ("Didot", '"Didot"'),
}
COLORS = {  # 标题第二行（低饱和），第一行统一暖白
    "sand": "#D9C8A9", "slate": "#AEBBCB", "sage": "#B9C4AE", "rose": "#D4B8B0",
}
# 布局：面板左上角 CSS 坐标 + 缩放；文字块位置。a = 对齐
LAYOUTS = {
    "L1": dict(label="左文右窗", px=1100, py=102, s=2.0,
               name=dict(x=120, y=112, a="left"), title=dict(x=120, y=238, a="left"), foot=dict(x=120, y=540, a="left")),
    "L2": dict(label="左窗右文", px=120, py=102, s=2.0,
               name=dict(x=120, y=112, a="right"), title=dict(x=120, y=238, a="right"), foot=dict(x=120, y=540, a="right")),
    "L3": dict(label="居中面板", px=610, py=102, s=2.0,
               name=dict(x=110, y=112, a="left"), title=dict(x=110, y=390, a="left"), foot=dict(x=110, y=540, a="right")),
    "L4": dict(label="小窗多留白", px=1180, py=152, s=2.6,
               name=dict(x=140, y=150, a="left"), title=dict(x=140, y=262, a="left"), foot=dict(x=140, y=490, a="left")),
    "L5": dict(label="面板出血", px=1060, py=250, s=2.0,
               name=dict(x=120, y=96, a="left"), title=dict(x=120, y=190, a="left"), foot=dict(x=120, y=520, a="left")),
}

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{{font-family:"NY";src:url("file:///System/Library/Fonts/NewYork.ttf");font-style:normal}}
@font-face{{font-family:"NY";src:url("file:///System/Library/Fonts/NewYorkItalic.ttf");font-style:italic}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1600px;height:640px;overflow:hidden;background:#000}}
body{{position:relative;font-family:{font};color:#EEE9E0;-webkit-font-smoothing:antialiased}}
.bg{{position:absolute;inset:0;width:1600px;height:640px}}
.scrim{{position:absolute;inset:0;background:{scrim}}}
.t{{position:absolute;{side}:{x}px;text-align:{a}}}
.name{{font-size:21px;letter-spacing:.6px;color:rgba(238,233,224,.86)}}
h1{{font-weight:400;font-size:62px;line-height:1.12;letter-spacing:-.4px}}
h1 em{{display:block;color:{accent};font-style:italic}}
.foot{{font-size:14px;letter-spacing:.4px;color:rgba(238,233,224,.58)}}
</style></head><body>
<img class="bg" src="{bg}"><div class="scrim"></div>
{blocks}
</body></html>"""


def block(cls, spec, html):
    side = "left" if spec["a"] == "left" else "right"
    return f'<div class="t {cls}" style="{side}:{spec["x"]}px;top:{spec["y"]}px;text-align:{spec["a"]}">{html}</div>'


def render(name, layout="L1", font="newyork", color="sand", tag="dark"):
    L = LAYOUTS[layout]
    bg = D / "assets" / f"bg-{layout}-{tag}.jpg"
    if not bg.exists():
        frame(tag, L["px"], L["py"], L["s"], out=bg)
    scrim_side = "270deg" if L["name"]["a"] == "right" else "90deg"
    scrim = (f"linear-gradient({scrim_side},rgba(2,6,18,.45) 0%,rgba(2,6,18,.18) 40%,rgba(2,6,18,0) 60%),"
             "linear-gradient(0deg,rgba(2,6,18,.55) 0%,rgba(2,6,18,0) 24%)")
    blocks = "\n".join([
        block("name", L["name"], "MoniSwitch"),
        block("title", L["title"], f'<h1>Every display.<em>One switch.</em></h1>'),
        block("foot", L["foot"], "macOS 14+ · Apple Silicon · Free and open source"),
    ])
    html = PAGE.format(font=FONTS[font][1], scrim=scrim, accent=COLORS[color], bg=bg.name and f"assets/{bg.name}",
                       blocks=blocks, side="left", x=0, a="left")
    page = D / "out" / f"{name}.html"
    page.parent.mkdir(exist_ok=True)
    page.write_text(html.replace('src="assets/', 'src="../assets/'), encoding="utf-8")
    png = D / "out" / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    "--window-size=1600,640", f"--screenshot={png}", f"file://{page}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    return png


if __name__ == "__main__":
    plan = json.loads(sys.argv[1]) if len(sys.argv) > 1 else None
    sheets = plan or {
        "fonts": [(f"font-{k}", dict(font=k)) for k in FONTS],
        "colors": [(f"color-{k}", dict(color=k)) for k in COLORS],
        "layouts": [(f"layout-{k}", dict(layout=k)) for k in LAYOUTS],
    }
    for sheet, items in sheets.items():
        for name, kw in items:
            print(render(name, **kw))
