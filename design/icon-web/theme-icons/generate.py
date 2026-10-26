#!/usr/bin/env python3
"""Theme-driven icon study with three background depths.

Screen gradient = theme derived solid + highlight (exact hexes from
PanelThemeTests.lightDerivationLocked). Tile = same hue, low saturation, three
depths: tier 1 = current study, tier 2/3 progressively deeper + a bit more
saturated. Follows PanelThemeMath (HSL + L* binary search).
"""
import os
from string import Template

HERE = os.path.dirname(os.path.abspath(__file__))

# id, zh, en, mid, deep, bg(derived), highlight(derived), solid(derived)
THEMES = [
    ("rose", "玫瑰红", "Rose", "#DDBFC3", "#70585C", "#F1EDED", "#E4BCC2", "#9C404C"),
    ("sage", "鼠尾草绿", "Sage", "#BECAB8", "#566253", "#ECEEEB", "#A8D392", "#3F692B"),
    ("orange", "橙色", "Orange", "#FFB787", "#8E4E1D", "#F2ECE9", "#ECBD9E", "#914C1E"),
    ("tan", "棕褐", "Tan", "#DEC1B1", "#705A4D", "#F0EEEC", "#DFC1B0", "#845236"),
    ("blue", "蓝色", "Blue", "#AAC7FF", "#3A5E98", "#EBEEF3", "#B2C8F0", "#3C5D9D"),
    ("blueGray", "蓝灰", "Blue Gray", "#BAC7E3", "#525F77", "#ECEEF1", "#B9C6E3", "#3F5D9B"),
    ("tealGray", "青灰", "Teal Gray", "#B8CACD", "#516164", "#EBEEEF", "#9DCED7", "#2E666F"),
]
SYSTEM = ("system", "跟随系统", "Follow System", "#007AFF")

# name, top L*, bottom L*, saturation multiplier, tint opacity
TIERS = [
    ("tier1", "档 1 · 现状", "顶 L*97 → 底 L*91 · S×1.0", 97.0, 91.0, 1.00, 0.14),
    ("tier2", "档 2 · 明显", "顶 L*95 → 底 L*86 · S×1.15", 95.0, 86.0, 1.15, 0.18),
    ("tier3", "档 3 · 更浓", "顶 L*93 → 底 L*80.5 · S×1.35", 93.0, 80.5, 1.35, 0.24),
]


def rgb(hexstr):
    s = hexstr.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hsl(hexstr):
    r, g, b = rgb(hexstr)
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return 0.0, 0.0, l
    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        h = ((g - b) / d + (6 if g < b else 0)) * 60
    elif mx == g:
        h = ((b - r) / d + 2) * 60
    else:
        h = ((r - g) / d + 4) * 60
    return h, s, l


def to_hex(h, s, l):
    c = (1 - abs(2 * l - 1)) * s
    hp = (h % 360) / 60
    x = c * (1 - abs(hp % 2 - 1))
    if hp < 1: r1, g1, b1 = c, x, 0
    elif hp < 2: r1, g1, b1 = x, c, 0
    elif hp < 3: r1, g1, b1 = 0, c, x
    elif hp < 4: r1, g1, b1 = 0, x, c
    elif hp < 5: r1, g1, b1 = x, 0, c
    else: r1, g1, b1 = c, 0, x
    m = l - c / 2
    def q(v):
        v = min(1.0, max(0.0, v + m))
        return int(v * 255 + 0.5)
    return "#%02X%02X%02X" % (q(r1), q(g1), q(b1))


def lstar(hexstr):
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(hexstr)
    y = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return 116 * y ** (1 / 3) - 16 if y > 0.008856 else 903.3 * y


def color(h, s, target):
    lo, hi = 0.0, 1.0
    for _ in range(24):
        mid = (lo + hi) / 2
        if lstar(to_hex(h, s, mid)) < target:
            lo = mid
        else:
            hi = mid
    return to_hex(h, s, (lo + hi) / 2)


SVG = Template('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">$title</title>
  <desc id="desc">$desc</desc>

  <defs>
    <path id="tileShape" d="M285 100H739C841 100 924 183 924 285V739C924 841 841 924 739 924H285C183 924 100 841 100 739V285C100 183 183 100 285 100Z"/>
    <clipPath id="tileClip"><use href="#tileShape"/></clipPath>
    <clipPath id="screenClip"><rect x="246" y="316" width="532" height="312" rx="20"/></clipPath>

    <linearGradient id="tile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="$tileTop"/>
      <stop offset="0.55" stop-color="$tileBottom"/>
      <stop offset="1" stop-color="$tileBottom"/>
    </linearGradient>

    <radialGradient id="tint" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="$tint" stop-opacity="$tintOp"/>
      <stop offset="0.46" stop-color="$tint" stop-opacity="$tintOp2"/>
      <stop offset="1" stop-color="$tint" stop-opacity="0"/>
    </radialGradient>

    <linearGradient id="rim" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#0B1220" stop-opacity="0.05"/>
      <stop offset="0.55" stop-color="#0B1220" stop-opacity="0.09"/>
      <stop offset="1" stop-color="#0B1220" stop-opacity="0.13"/>
    </linearGradient>

    <linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#33333E"/>
      <stop offset="0.36" stop-color="#1C1C24"/>
      <stop offset="1" stop-color="#111117"/>
    </linearGradient>

    <linearGradient id="stand" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#45454F"/>
      <stop offset="0.35" stop-color="#2A2A33"/>
      <stop offset="0.75" stop-color="#191920"/>
      <stop offset="1" stop-color="#121218"/>
    </linearGradient>

    <linearGradient id="screen" x1="0" y1="0" x2="1" y2="1">
$stops    </linearGradient>

    <linearGradient id="screenGloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="0.42" stop-color="#FFFFFF" stop-opacity="0.04"/>
      <stop offset="0.75" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>

    <linearGradient id="specular" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.33" stop-color="#FFFFFF" stop-opacity="0.02"/>
      <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.13"/>
      <stop offset="0.52" stop-color="#FFFFFF" stop-opacity="0.035"/>
      <stop offset="0.68" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>

    <linearGradient id="screenShade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0.66" stop-color="$shade" stop-opacity="0"/>
      <stop offset="1" stop-color="$shade" stop-opacity="0.30"/>
    </linearGradient>

    <radialGradient id="screenBloom" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.08"/>
      <stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0.018"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>

    <radialGradient id="ledGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFD9C0" stop-opacity="0.65"/>
      <stop offset="0.4" stop-color="#FFB99B" stop-opacity="0.24"/>
      <stop offset="1" stop-color="#FFA07C" stop-opacity="0"/>
    </radialGradient>

    <radialGradient id="deskShadow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#0B1220" stop-opacity="0.13"/>
      <stop offset="0.6" stop-color="#0B1220" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#0B1220" stop-opacity="0"/>
    </radialGradient>

    <linearGradient id="knob" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="0.55" stop-color="#FAF9FF"/>
      <stop offset="1" stop-color="#E9E6F2"/>
    </linearGradient>

    <filter id="frontShadow" x="-40%" y="-45%" width="180%" height="200%">
      <feDropShadow dx="0" dy="28" stdDeviation="30" flood-color="#0B1220" flood-opacity="0.22"/>
    </filter>
    <filter id="standShadow" x="-60%" y="-80%" width="220%" height="260%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#0B1220" flood-opacity="0.20"/>
    </filter>
    <filter id="knobShadow" x="-60%" y="-60%" width="220%" height="240%">
      <feDropShadow dx="0" dy="5" stdDeviation="8" flood-color="#000000" flood-opacity="0.30"/>
    </filter>
  </defs>

  <use href="#tileShape" fill="url(#tile)"/>

  <g clip-path="url(#tileClip)">
    <ellipse cx="512" cy="610" rx="540" ry="450" fill="url(#tint)"/>
    <ellipse cx="512" cy="742" rx="200" ry="30" fill="url(#deskShadow)"/>

    <g filter="url(#standShadow)">
      <rect x="484" y="628" width="56" height="68" rx="14" fill="url(#stand)"/>
      <rect x="412" y="694" width="200" height="20" rx="10" fill="url(#stand)"/>
      <path d="M420 694H604" fill="none" stroke="#FFFFFF" stroke-opacity="0.20" stroke-width="2" stroke-linecap="round"/>
      <path d="M492 644H532" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2" stroke-linecap="round"/>
    </g>

    <g filter="url(#frontShadow)">
      <rect x="232" y="302" width="560" height="340" rx="34" fill="url(#bezel)"/>
      <rect x="232" y="302" width="560" height="340" rx="34" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="2.5"/>
      <g clip-path="url(#screenClip)">
        <rect x="246" y="316" width="532" height="312" rx="20" fill="url(#screen)"/>
        <ellipse cx="350" cy="380" rx="240" ry="172" fill="url(#screenBloom)"/>
        <rect x="246" y="316" width="532" height="312" rx="20" fill="url(#screenGloss)"/>
        <rect x="246" y="316" width="532" height="312" rx="20" fill="url(#specular)"/>
        <rect x="246" y="316" width="532" height="312" rx="20" fill="url(#screenShade)"/>
      </g>
      <rect x="246" y="316" width="532" height="312" rx="20" fill="none" stroke="#FFFFFF" stroke-opacity="0.30" stroke-width="2.2"/>

      <circle cx="512" cy="309" r="2.6" fill="#07070A"/>
      <circle cx="512" cy="309" r="2.6" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="1"/>

      <g>
        <rect x="422" y="458" width="180" height="84" rx="42" fill="#FFFFFF" fill-opacity="0.24"/>
        <rect x="422" y="458" width="180" height="84" rx="42" fill="none" stroke="#FFFFFF" stroke-opacity="0.68" stroke-width="2.5"/>
        <g filter="url(#knobShadow)">
          <circle cx="556" cy="500" r="30" fill="url(#knob)"/>
        </g>
        <circle cx="556" cy="500" r="29" fill="none" stroke="#FFFFFF" stroke-opacity="0.78" stroke-width="1.2"/>
        <circle cx="549" cy="492" r="5" fill="#FFFFFF" opacity="0.55"/>
      </g>

      <circle cx="512" cy="635.5" r="6.5" fill="url(#ledGlow)"/>
      <circle cx="512" cy="635.5" r="2.2" fill="#FFF0E2"/>
    </g>
  </g>

  <use href="#tileShape" fill="none" stroke="url(#rim)" stroke-width="2.5"/>
</svg>
''')


def ramp(mid, bg, hi, solid, tier):
    """Five screen stops (fixed) + tile colors that depend on the tier."""
    h = hsl(mid)[0]
    s_solid = hsl(solid)[1]
    s_hi = hsl(hi)[1]
    s_bg = min(0.30, hsl(bg)[1] * tier[5])
    stops = [
        (0.00, color(h, s_solid, 30)),
        (0.30, solid),
        (0.60, color(h, s_hi, 62)),
        (0.82, hi),
        (1.00, color(h, s_bg, 92)),
    ]
    tile_top = color(h, s_bg * 0.55, tier[3])
    tile_bottom = color(h, s_bg, tier[4])
    return stops, tile_top, tile_bottom, color(h, s_solid, 26)


def build(slug, zh, en, mid, deep, bg, hi, solid, tier,
          title=None, desc=None, filename=None):
    stops, tile_top, tile_bottom, shade = ramp(mid, bg, hi, solid, tier)
    stops_svg = "".join(
        '      <stop offset="%.2f" stop-color="%s"/>\n' % (o, c) for o, c in stops
    )
    svg = SVG.substitute(
        title=title or "MoniSwitch app icon — %s theme" % zh,
        desc=desc or ("A %s-tinted squircle holding a dark widescreen display lit "
                      "with the %s palette, plus a frosted toggle." % (zh, en)),
        zh=zh, en=en, tileTop=tile_top, tileBottom=tile_bottom,
        tint=hi, shade=shade, stops=stops_svg,
        tintOp="%.2f" % tier[6], tintOp2="%.2f" % (tier[6] * 0.36),
    )
    name = filename or ("icon-%s.svg" % slug if tier[0] == "tier1"
                        else "%s-%s.svg" % (tier[0], slug))
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        f.write(svg)
    return dict(tileTop=tile_top, tileBottom=tile_bottom, solid=solid, highlight=hi,
                bg=bg, filename=os.path.basename(name))


def system_parts(accent, tier):
    h, s, _ = hsl(accent)
    solid = color(h, min(0.66, max(0.42, s)), 40)
    hi = color(h, min(0.68, max(0.42, s)), 80)
    bg = color(h, 0.10, 94)
    return accent, accent, bg, hi, solid


# 标准强调色（macOS「系统设置 > 外观 > 强调色」里的 8 个固定档）。
# 运行时的 AppleAccentColor 序号映射见 AppIconTheme.accentSlug。
ACCENTS = [
    ("blue", "#007AFF"),
    ("purple", "#A550A7"),
    ("pink", "#F74F9E"),
    ("red", "#FF5257"),
    ("orange", "#FF9F0A"),
    ("yellow", "#FFD60A"),
    ("green", "#61BB46"),
    ("graphite", "#8C8C8C"),
]

theme_entries = list(THEMES)
system_entries = []
for slug, accent in ACCENTS:
    mid, deep, bg, hi, solid = system_parts(accent, TIERS[0])
    system_entries.append(("system-" + slug, SYSTEM[1], SYSTEM[2], mid, deep, bg, hi, solid))

# 预览页只展示 7 个主题 + 跟随系统（蓝）；资源文件按 8 个强调色全出。
entries = theme_entries + [e for e in system_entries if e[0] == "system-blue"]
all_entries = theme_entries + system_entries

# --- 资产：档 1 全部（打包用），档 2/3 仅供对比页 ---
metas = {}
for tier in TIERS:
    for tid, zh, en, mid, deep, bg, hi, solid in all_entries:
        title = desc = None
        if tid.startswith("system-"):
            accent = tid.split("-", 1)[1]
            title = "MoniSwitch app icon — system accent (%s)" % accent
            desc = ("A %s-tinted squircle holding a dark widescreen display lit with "
                    "the %s system accent, plus a frosted toggle." % (accent, accent))
        metas[(tier[0], tid)] = build(tid, zh, en, mid, deep, bg, hi, solid, tier,
                                      title=title, desc=desc)

# --- 主图标：bundle 默认图 = 跟随系统（蓝强调色）----
mid, deep, bg, hi, solid = system_parts("#007AFF", TIERS[0])
build("main", SYSTEM[1], SYSTEM[2], mid, deep, bg, hi, solid, TIERS[0],
      title="MoniSwitch app icon",
      desc=("A pale blue-tinted squircle holding a dark widescreen display lit with "
            "the system accent palette, plus a frosted toggle."),
      filename=os.path.join("..", "moniswitch-icon.svg"))

# --- tier 1 grid page (keeps the earlier layout) ---
cards, order = [], []
for tid, zh, en, mid, deep, bg, hi, solid in entries:
    meta = metas[("tier1", tid)]
    order.append((tid, zh))
    chips = "".join(
        '<span class="chip" style="background:%s" title="%s"></span>' % (c, c)
        for c in [meta["tileTop"], meta["tileBottom"], meta["solid"], meta["highlight"]]
    )
    cards.append(
        '<figure class="card">'
        '<img class="main" src="%s" width="264" height="264" alt="%s">'
        '<div class="tiny"><img src="%s" width="64" height="64" alt="">'
        '<img src="%s" width="32" height="32" alt="">'
        '<img src="%s" width="16" height="16" alt=""></div>'
        '<figcaption><b>%s</b><span>%s</span><div class="chips">%s</div></figcaption>'
        '</figure>' % (meta["filename"], en, meta["filename"], meta["filename"],
                       meta["filename"], zh, en, chips)
    )

darkstrip = "".join(
    '<div class="ds"><img src="%s" width="64" height="64" alt=""><span>%s</span></div>'
    % (metas[("tier1", s)]["filename"], z)
    for s, z in order
)

page = """<!doctype html>
<html lang="zh">
<meta charset="utf-8">
<title>MoniSwitch icon — 主题配色</title>
<style>
  html,body{margin:0}
  body{background:#F2F3F6;font:13px/1.45 -apple-system,"SF Pro Text",system-ui,sans-serif;color:#1C1C1E;padding:28px 30px 34px}
  h1{font-size:15px;font-weight:600;margin:0 0 2px}
  p.sub{margin:0 0 20px;font-size:11.5px;color:#6B7280}
  .grid{display:grid;grid-template-columns:repeat(4,300px);gap:16px}
  .card{margin:0;background:#fff;border-radius:14px;padding:14px 14px 12px;
        box-shadow:0 1px 2px rgba(0,0,0,.05),0 8px 24px -12px rgba(0,0,0,.18)}
  .main{display:block;border-radius:12px}
  .tiny{display:flex;align-items:flex-end;gap:10px;margin:6px 0 0 6px;min-height:64px}
  figcaption{margin-top:8px;font-size:12px;display:flex;flex-direction:column;gap:3px}
  figcaption b{font-size:13px;font-weight:600}
  figcaption span{color:#6B7280;font-size:11px}
  .chips{display:flex;gap:4px;margin-top:6px}
  .chip{width:22px;height:9px;border-radius:3px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.07)}
  h2{font-size:12px;font-weight:600;margin:22px 0 10px;color:#6B7280;letter-spacing:.04em;text-transform:uppercase}
  .darkstrip{display:flex;gap:26px;background:#1B1B1F;border-radius:12px;padding:16px 20px}
  .ds{display:flex;flex-direction:column;align-items:center;gap:6px}
  .ds span{font-size:10px;color:#8E8E96}
</style>
<h1>MoniSwitch 图标 · 跟随设置主题（档 1 现状）</h1>
<p class="sub">屏幕渐变 = 该主题浅色派生的实心档 → 高亮档（精确 hex）；面板底色 = 同色相低饱和（主题 bg 方向）。跟随系统一项用当前系统强调色 #007AFF。</p>
<div class="grid">%s</div>
<h2>深色背景 · 64 px</h2>
<div class="darkstrip">%s</div>
</html>
""" % ("".join(cards), darkstrip)

with open(os.path.join(HERE, "preview.html"), "w", encoding="utf-8") as f:
    f.write(page)

# --- tier comparison page ---
head = "".join('<th><b>%s</b><span>%s</span></th>' % (zh, en) for _, zh, en, *_ in entries)
rows = []
for tier in TIERS:
    cells = "".join(
        '<td><img src="%s" width="158" height="158" alt=""><img class="small" src="%s" width="64" height="64" alt=""></td>'
        % (metas[(tier[0], tid)]["filename"], metas[(tier[0], tid)]["filename"])
        for tid, *_ in entries
    )
    rows.append(
        '<tr><th class="tier"><b>%s</b><span>%s</span></th>%s</tr>' % (tier[1], tier[2], cells)
    )

tiers_page = """<!doctype html>
<html lang="zh">
<meta charset="utf-8">
<title>MoniSwitch icon — 底板三档</title>
<style>
  html,body{margin:0}
  body{background:#F2F3F6;font:13px/1.45 -apple-system,"SF Pro Text",system-ui,sans-serif;color:#1C1C1E;padding:26px 30px 30px}
  h1{font-size:15px;font-weight:600;margin:0 0 2px}
  p.sub{margin:0 0 18px;font-size:11.5px;color:#6B7280}
  table{border-collapse:separate;border-spacing:10px 12px}
  th{font-weight:400;text-align:center;font-size:11.5px;color:#6B7280;padding:0 0 4px}
  th b{display:block;font-size:12.5px;font-weight:600;color:#1C1C1E}
  th span{display:block;font-size:10.5px;color:#8A9099}
  th.tier{text-align:left;padding-left:2px;white-space:nowrap}
  td{background:#fff;border-radius:12px;padding:10px 10px 8px;vertical-align:middle;
     box-shadow:0 1px 2px rgba(0,0,0,.05),0 6px 18px -12px rgba(0,0,0,.18)}
  td img{display:block}
  td img.small{margin:6px auto 0}
</style>
<h1>MoniSwitch 图标 · 底板深浅三档</h1>
<p class="sub">屏幕渐变完全不动（主题实心档 → 高亮档）。只调底板：饱和度乘系数 + 上下端 L* 目标；档 1 就是现在的样子。</p>
<table>
<tr><th></th>%s</tr>
%s
</table>
</html>
""" % (head, "\n".join(rows))

with open(os.path.join(HERE, "tiers.html"), "w", encoding="utf-8") as f:
    f.write(tiers_page)

print("tiers written")
for tier in TIERS:
    print(tier[0], tier[2])
