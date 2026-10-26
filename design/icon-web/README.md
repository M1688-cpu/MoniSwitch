# MoniSwitch — 图标 / Icon

浅色底、单色相屏幕的图标，**跟随设置里的面板主题**。SVG 是主文件，PNG 由脚本渲染。

## 文件

| 文件 | 用途 |
| --- | --- |
| `moniswitch-icon.svg` | 主文件（1024×1024）。= 跟随系统（蓝强调色），也是 bundle 里 `.icns` 的来源 |
| `moniswitch-icon-1024.png` | 主图标 1024 PNG（透明底） |
| `sizes/icon-{512,256,128,64,32,16}.png` | 尺寸检查用栅格图 |
| `theme-icons/` | 7 个内置主题 + 8 档系统强调色的 SVG 源；`generate.py` 是唯一色值入口 |
| `theme-icons/preview.html` | 8 套主题预览（档 1 底板） |
| `theme-icons/tiers.html` | 底板深浅三档对比（历史选型；定档 = 档 1） |
| `candidates/` | 早期「彩虹渐变换色」研究（历史存档，未采用） |
| `index.html` | 预览页：主题画廊、尺寸阶梯、取色规则 |

## 设计

> 一块屏幕，一个开关。

- **浅色底**：824 px squircle，顶 `#F8F6F7` 左近白 → 底略深的同色相淡染，一圈 5–13% 的细边；显示器下方叠同色相的极淡反光。
- **单色相屏幕**：渐变只用主题色一个色相——主题浅色派生的**实心档（L\*40）→ 高亮档（L\*80）**，两端再各外扩一档（深端 L\*30、亮端 L\*92）。没有第二个色相，因此没有彩虹。
- **深色 bezel 保留**：浅底上仍是一台深色显示器，屏幕是唯一光源；16 px 下仍读得出「亮着的屏 + 一个开关」。
- **跟随主题**：7 个内置主题（玫瑰红/鼠尾草绿/橙/棕褐/蓝/蓝灰/青灰）各一张；「跟随系统」按系统 8 档强调色各一张（多彩/未知按蓝）。

取色不是手挑的：`generate.py` 调的是与 App 内 `PanelTheme.lightDerived()` 相同的算法（HSL + L\* 二分），色值由 `Tests/MoniSwitchTests/PanelThemeTests.swift` 锁定。

## 规格

- 画布 1024 × 1024，透明留白 100 px；实体 824 × 824 squircle（圆角 185 px）
- 屏幕区域 532 × 312（圆角 20），bezel 560 × 340（圆角 34）
- 底板（档 1）：顶 L\*97 → 底 L\*91，S = 主题 bg 的 S
- 屏幕渐变：135°，5 个停靠点，见上
- 开关：白色玻璃轨 + 白色旋钮；下边框一颗暖色电源灯（`#FFF0E2`）

## 重新生成

改色/改几何 → 跑生成器（`design/icon-web/theme-icons/generate.py`）→ 渲染资源：

```bash
cd design/icon-web/theme-icons
python3 generate.py                 # 重写 SVG（含 ../moniswitch-icon.svg）

cd ../../..
bash Support/render-theme-icons.sh  # Chrome 渲染 → Resources/AppIconThemes/*.png
                                    # + 主图标 PNG/尺寸阶梯/AppIcon-source.png
                                    # + 重建 Resources/AppIcon.icns
bash Support/build-app.sh           # 打包
```

`render-theme-icons.sh` 需要 Google Chrome（headless 截图），可用 `CHROME=/path/to/chrome` 覆盖。

## 运行时怎么跟随主题

打包只带一张静态 `AppIcon.icns`（= 跟随系统蓝）。运行中：

- `AppIconController` 监听主题切换 / App 激活 / 系统强调色变化，
- 按「主题 id + `AppleAccentColor`」选 `Resources/AppIconThemes/theme-<id>.png` 或 `system-<accent>.png`，
- 设 `NSApp.applicationIconImage` —— 设置窗口打开时 Dock 里的图标即时跟着换，关于页也显示同一张。

Finder 里 `.app` 文件的图标、通知横幅用的都是 bundle 里的静态 icns（macOS 限制，运行时不改）。
