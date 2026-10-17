# MoniSwitch — 新图标 / Icon study

MoniSwitch 的深色图标概念，以 Web 可用的 **SVG** 为主文件，附 1024 PNG 和多尺寸栅格图。

> 已接入：`Resources/AppIcon-source.png` 和 `Resources/AppIcon.icns` 已更新，`Support/make-app-icon.sh` 默认直接使用现成源图生成 icns。

## 文件

| 文件 | 用途 |
| --- | --- |
| `moniswitch-icon.svg` | 主文件，1024×1024，可无损缩放 |
| `moniswitch-icon-1024.png` | 透明底 1024 PNG（由 SVG 导出） |
| `sizes/icon-{512,256,128,64,32,16}.png` | 尺寸检查用栅格图 |
| `index.html` | 预览页：Dock 语境、尺寸阶梯、设计拆解、色板 |
| `README.md` | 本文件 |

## 概念

> 一块屏幕，一个开关。

- **屏幕 = Moni**：一块宽屏显示器，支架、摄像头、下边框电源灯都在，但只保留最必要的硬件线索。
- **开关 = Switch**：屏幕正中的磨砂玻璃 toggle。它是整枚图标唯一的“操作”，也是 App 名字的字面翻译。
- **黑场**：824 px squircle，近黑底 + 一圈极细 rim light。原生深色图标的做法，让屏幕成为唯一光源。
- **极光屏**：青蓝 → 靛蓝 → 紫 → 洋红 → 珊瑚的五段渐变，叠顶部柔光、斜向高光和底部暗角。屏幕是“亮着的”，不是贴上去的。
- **一个暖点**：下边框上的电源灯是唯一的暖色。它不负责识别，只负责让机器看起来醒着。

参考图里借的是**方法**，不是图形：

- 苹果原生深色图标 → 黑场、单一母题、无文字、居中的强轮廓。
- BongoCat → 大量负空间，以及一个很小的、有人味的暖色细节。
- Compositor → 高饱和极光渐变 + 玻璃高光。
- Alcove → 深色边框包住发光屏幕，屏幕边缘有内发光。

## 规格

- 画布：1024 × 1024，透明留白 100 px
- 实体：824 × 824 squircle，圆角 185 px
- 屏幕渐变：`#4FD0FF → #5B70FF 24% → #A241FF 55% → #FF47AB 80% → #FF9866`，135°
- 深色底：`#17171F → #0B0B11 → #050507`
- 电源灯：`#FFF0E2`
- 开关：白色玻璃轨 + 白色旋钮，未使用额外的品牌色

## 重新导出 PNG

macOS 上已装 Chrome 时：

```bash
cd design/icon-web

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 \
  --default-background-color=00000000 \
  --screenshot=moniswitch-icon-1024.png \
  --window-size=1024,1024 \
  "file://$PWD/moniswitch-icon.svg"

mkdir -p sizes
for s in 512 256 128 64 32 16; do
  sips -z "$s" "$s" moniswitch-icon-1024.png --out "sizes/icon-$s.png" >/dev/null
done
```

预览页的主视觉直接使用 SVG；`sizes/` 只服务于尺寸阶梯的栅格检查。

## 已接入 App

`Resources/AppIcon-source.png` 已替换为本图的 1024 PNG，`Resources/AppIcon.icns` 已重建；`Support/make-app-icon.sh` 默认直接使用现成源图，不再调用旧版 Swift 自绘。

以后改图：

1. 改 `moniswitch-icon.svg`，重新导出 `moniswitch-icon-1024.png`（命令见上）。
2. 覆盖 `Resources/AppIcon-source.png`。
3. `bash Support/make-app-icon.sh` → 重建 `Resources/AppIcon.icns`。
4. `bash Support/build-app.sh` → 重新生成 `Support/MoniSwitch.app` / `.dmg`。

旧版蓝色显示器自绘仍保留在 `Support/make-app-icon-design.swift`，只能通过 `bash Support/make-app-icon.sh --redraw` 走实验路径；默认流程不会再用它。

如果 Finder / Dock 仍显示旧图标，重启应用或重新打包；系统图标缓存偶尔需要重新登录（或 `killall Dock`）才会刷新。
