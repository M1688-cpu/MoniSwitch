#!/usr/bin/env python3
"""Generate light-tile icon candidates for MoniSwitch.

Same geometry as design/icon-web/moniswitch-icon.svg; the tile turns light and the
screen gradient is swapped per scheme. Writes one SVG per scheme plus a compare page.
"""
import os
from string import Template

HERE = os.path.dirname(os.path.abspath(__file__))

SCHEMES = [
    dict(slug="teal", zh="青碧", en="Teal – Mint",
         stops=[(0, "#0A3F49"), (0.26, "#0D6E74"), (0.52, "#14A3A8"), (0.78, "#4FD1C5"), (1, "#9DECE4")],
         mid="#14A3A8", deep="#0A3F49"),
    dict(slug="violet", zh="紫罗兰", en="Violet – Lilac",
         stops=[(0, "#2E1065"), (0.26, "#4C1D95"), (0.52, "#7C3AED"), (0.78, "#A78BFA"), (1, "#D5C7FA")],
         mid="#7C3AED", deep="#2E1065"),
    dict(slug="amber", zh="琥珀", en="Amber – Honey",
         stops=[(0, "#4A2500"), (0.26, "#8A4300"), (0.52, "#D98324"), (0.78, "#F5B841"), (1, "#FCE3A6")],
         mid="#D98324", deep="#4A2500"),
    dict(slug="sage", zh="鼠尾草", en="Sage – Olive",
         stops=[(0, "#22331F"), (0.26, "#3D5C36"), (0.52, "#6B8F5E"), (0.78, "#A3C293"), (1, "#DAE9D1")],
         mid="#6B8F5E", deep="#22331F"),
    dict(slug="slate", zh="石板青", en="Slate – Steel",
         stops=[(0, "#0F172A"), (0.26, "#1E293B"), (0.52, "#475569"), (0.78, "#7C8DA6"), (1, "#C6D2E1")],
         mid="#475569", deep="#0F172A"),
]

SVG = Template('''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">MoniSwitch app icon — $zh / $en</title>
  <desc id="desc">A light squircle holding a dark widescreen display, lit with a $en gradient and carrying a frosted glass toggle switch.</desc>

  <defs>
    <path id="tileShape" d="M285 100H739C841 100 924 183 924 285V739C924 841 841 924 739 924H285C183 924 100 841 100 739V285C100 183 183 100 285 100Z"/>
    <clipPath id="tileClip"><use href="#tileShape"/></clipPath>
    <clipPath id="screenClip"><rect x="246" y="316" width="532" height="312" rx="20"/></clipPath>

    <linearGradient id="tile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="0.62" stop-color="#F7F9FC"/>
      <stop offset="1" stop-color="#ECEFF5"/>
    </linearGradient>

    <radialGradient id="tint" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="$mid" stop-opacity="0.17"/>
      <stop offset="0.46" stop-color="$mid" stop-opacity="0.07"/>
      <stop offset="1" stop-color="$mid" stop-opacity="0"/>
    </radialGradient>

    <linearGradient id="rim" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#0B1220" stop-opacity="0.035"/>
      <stop offset="0.55" stop-color="#0B1220" stop-opacity="0.075"/>
      <stop offset="1" stop-color="#0B1220" stop-opacity="0.11"/>
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
      <stop offset="0.66" stop-color="$deep" stop-opacity="0"/>
      <stop offset="1" stop-color="$deep" stop-opacity="0.30"/>
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

def render(scheme):
    stops = "\n".join(
        '      <stop offset="%s" stop-color="%s"/>' % (o, c) for o, c in scheme["stops"]
    ) + "\n"
    return SVG.substitute(
        zh=scheme["zh"], en=scheme["en"], mid=scheme["mid"], deep=scheme["deep"],
        stops=stops,
    )

cards = []
for i, s in enumerate(SCHEMES, 1):
    path = os.path.join(HERE, "c%d-%s.svg" % (i, s["slug"]))
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(s))
    chips = "".join(
        '<span class="chip" style="background:%s" title="%s"></span>' % (c, c)
        for _, c in s["stops"]
    )
    cards.append(
        '<figure class="card">'
        '<img src="c%d-%s.svg" width="300" height="300" alt="%s">'
        '<figcaption><b>%d · %s</b><span>%s</span><div class="chips">%s</div></figcaption>'
        '</figure>' % (i, s["slug"], s["en"], i, s["zh"], s["en"], chips)
    )

page = """<!doctype html>
<html lang="zh">
<meta charset="utf-8">
<title>MoniSwitch icon — 浅底配色方案</title>
<style>
  html,body{margin:0}
  body{background:#F2F3F6;font:13px/1.45 -apple-system,"SF Pro Text",system-ui,sans-serif;color:#1C1C1E;padding:28px 30px 34px}
  h1{font-size:15px;font-weight:600;margin:0 0 2px}
  p.sub{margin:0 0 20px;font-size:11.5px;color:#6B7280}
  .row{display:flex;gap:16px;align-items:flex-start}
  .card{margin:0;background:#fff;border-radius:14px;padding:14px 14px 12px;width:300px;
        box-shadow:0 1px 2px rgba(0,0,0,.05),0 8px 24px -12px rgba(0,0,0,.18)}
  .card img{display:block;border-radius:10px}
  figcaption{margin-top:12px;font-size:12px;display:flex;flex-direction:column;gap:3px}
  figcaption b{font-size:13px;font-weight:600}
  figcaption span{color:#6B7280;font-size:11px}
  .chips{display:flex;gap:4px;margin-top:6px}
  .chip{width:22px;height:9px;border-radius:3px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.07)}
</style>
<h1>MoniSwitch 图标 · 浅色底 5 组配色</h1>
<p class="sub">同几何、同材质，只换屏幕渐变与底盘微光；深色 bezel 保留以维持屏幕是唯一光源的叙事。</p>
<div class="row">%s</div>
</html>
""" % "".join(cards)

with open(os.path.join(HERE, "compare.html"), "w", encoding="utf-8") as f:
    f.write(page)

print("wrote", len(SCHEMES), "schemes")
