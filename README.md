<h1 align="center">
  <img src="Resources/AppIcon-source.png" width="56" alt="MoniSwitch" align="middle"> MoniSwitch
</h1>

<p align="center">
  一个简洁的 macOS 菜单栏小工具，让你不用进「系统设置 → 显示器」就能快速切换主显示器、调整外接屏的左右位置、以及在外接屏上切换扩展/镜像。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="platform">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="arch">
  <img src="https://img.shields.io/badge/version-0.1.3-blue" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- 🖥️ **菜单栏常驻**：点击菜单栏图标即弹出气泡卡片面板（悬浮毛玻璃圆角卡片）
- 🔀 **一键切主屏**：在面板里点任意显示器，立即把它设为主显示器（白条所在屏）
- ↔️ **左右移动外接屏**：展开外接屏行，把外接屏放到主屏的左边或右边
- 🪞 **扩展 / 镜像切换**：把外接屏在「扩展显示」和「镜像主屏」之间一键切换
- 📦 **布局预设**：把整套显示器配置（主屏+位置+镜像）保存为预设，一键切换（如「办公」「演示」）
- 🔄 **菜单切换刷新率**：面板内直接切换外接屏刷新率（如 60Hz ↔ 120Hz）
- ⌨️ **全局快捷键**：给每个预设绑定一个全局快捷键（Carbon `RegisterEventHotKey`，零权限依赖），按下即应用对应布局
- 🗺️ **布局预览**：面板内按真实比例绘制显示器位置示意图，一眼看清当前排列
- 🎨 **跟随系统强调色**：面板与设置窗口随「系统设置 → 外观 → 强调色」实时刷新，无固定品牌色
- ⚙️ **设置窗口**：中英双语、开机自启动、自动刷新列表（可选刷新间隔）、切换后通知
- 🌐 **中英双语**：界面语言一键切换，重启后保持

## 截图

<table>
  <tr>
    <th width="50%">中文</th>
    <th width="50%">English</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><b>面板全貌</b> · 主屏切换 / 排列与镜像 / 预设 / 布局预览 / 底部工具栏<br><sub>气泡卡片面板，跟随系统强调色</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="screenshots/zh/panel-overview.png" alt="面板全貌（中文）"></td>
    <td width="50%" align="center"><img src="screenshots/en/panel-overview.png" alt="Panel overview (English)"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><b>排列展开</b> · 左/右移动 + 刷新率切换 + 镜像/扩展<br><sub>展开外接屏行，露出胶囊按钮</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="screenshots/zh/panel-arrange.png" alt="排列展开（中文）"></td>
    <td width="50%" align="center"><img src="screenshots/en/panel-arrange.png" alt="Arrange detail (English)"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><b>设置 — 通用</b> · 语言 / 自启动 / 自动刷新 / 通知<br><sub>开启自动刷新后显示刷新间隔选择器</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="screenshots/zh/settings-general.png" width="360" alt="设置-通用（中文）"></td>
    <td width="50%" align="center"><img src="screenshots/en/settings-general.png" width="360" alt="Settings — General (English)"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><b>设置 — 预设</b> · 保存 / 应用 / 删除 + 全局快捷键绑定<br><sub>每个预设可录制一个快捷键（Esc 取消）</sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="screenshots/zh/settings-presets.png" width="360" alt="设置-预设（中文）"></td>
    <td width="50%" align="center"><img src="screenshots/en/settings-presets.png" width="360" alt="Settings — Presets (English)"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><b>设置 — 关于</b> · 图标 / 简介 / 版本号</td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="screenshots/zh/settings-about.png" width="360" alt="设置-关于（中文）"></td>
    <td width="50%" align="center"><img src="screenshots/en/settings-about.png" width="360" alt="Settings — About (English)"></td>
  </tr>
</table>

## 安装

### 方式一：下载 DMG（普通用户推荐）

1. 前往 [Releases 页面](../../releases)，下载最新的 `MoniSwitch.dmg`
2. 双击打开，把 **MoniSwitch** 拖入 **Applications** 文件夹
3. 首次打开时，macOS 可能提示「无法打开，因为来自身份不明的开发者」
   - 这是因为本 App 未做 Apple 公证（见下方[说明](#关于未公证提示)）
   - 解决：打开「系统设置 → 隐私与安全性」，点击「仍要打开」即可

### 方式二：自行编译（开发者）

```bash
# 1. 克隆仓库
git clone https://github.com/<你的用户名>/MoniSwitch.git
cd MoniSwitch

# 2. 放置 displayplacer 二进制（见 Resources/README.md）
cp /path/to/displayplacer-apple-v140 ./Resources/displayplacer
chmod +x ./Resources/displayplacer

# 3. 一键打包（编译 + 组装 .app + 签名 + 生成 .dmg）
bash Support/build-app.sh

# 4. 产物在 Support/ 目录下
#    - Support/MoniSwitch.app
#    - Support/MoniSwitch.dmg
```

## 使用

1. 打开 MoniSwitch 后，菜单栏会出现一个显示器图标
2. 点击图标，看到当前所有显示器列表
3. **点击任意显示器名称** → 立即设为主屏
4. 展开「外接显示器」子菜单 → 左/右移动、镜像、扩展

## 关于未公证提示

MoniSwitch 采用「DMG 直链分发」而非 Mac App Store，因此没有 Apple 公证。
这是开源/免费小工具的常见做法，App 本身安全（代码完全开源可审查）。
首次打开按上述步骤在「隐私与安全性」放行即可，之后不会再提示。

## 工作原理

MoniSwitch 是一个友好的图形界面，底层调用 [displayplacer](https://github.com/jakehilborn/displayplacer)（MIT License，© Jake Hilborn）完成实际的显示器配置。
displayplacer 二进制随 App 一起打包，**开箱即用，无需额外安装**。

- 切换主屏：把目标屏的 `origin` 平移到 `(0,0)`，其余屏按相同向量平移以保持左右关系
- 左/右移动：调整外接屏的 `origin.x`
- 镜像/扩展：使用 displayplacer 的 `id:A+B` 镜像语法 / 还原为并排扩展布局

## 技术栈

- **语言**：Swift 6
- **UI**：SwiftUI `MenuBarExtra`（macOS 13+ 原生菜单栏 API）
- **构建**：Swift Package Manager（纯文本 `Package.swift`，命令行即可编译）
- **类型**：纯菜单栏 App（`LSUIElement = YES`，无 Dock 图标）
- **分发**：非沙盒，本地 ad-hoc 签名，DMG 直链

## 项目结构

```
MoniSwitch/
├── Package.swift                  # SPM 构建配置
├── Sources/MoniSwitch/
│   ├── MoniSwitchApp.swift        # 菜单栏 UI 入口 + 面板宿主（MenuBarExtra .window）
│   ├── PanelView.swift            # 菜单栏气泡卡片面板（主屏/排列/预设/布局预览）
│   ├── Models.swift               # 显示器数据模型
│   ├── ShellRunner.swift          # displayplacer 调用封装
│   ├── DisplayManager.swift       # 解析 + 切换算法（含镜像组检测）
│   ├── AppSettings.swift          # 用户偏好单例（自启动/通知/自动刷新）
│   ├── PresetManager.swift        # 显示器布局预设管理（保存/应用/删除/快捷键绑定）
│   ├── HotkeyManager.swift        # 全局快捷键（Carbon RegisterEventHotKey，零权限）
│   ├── ScreenCaptureProvider.swift # 屏幕捕获接口（画面预览预留，暂未启用）
│   ├── DockPolicyManager.swift    # Dock 策略 + 设置窗口（NSWindow + NSToolbar）
│   ├── SettingsView.swift         # 设置窗口 SwiftUI 视图（通用/预设/关于）
│   └── Localization.swift         # 中英双语（L10n 类 + TextKey 枚举）
├── Resources/
│   ├── displayplacer              # 打包的显示控制二进制（不入库）
│   ├── AppIcon.icns               # 应用图标
│   └── AppIcon-source.png         # 图标源图
├── Support/
│   ├── Info.plist                 # App 元信息（LSUIElement 等）
│   └── build-app.sh               # 一键打包脚本
├── screenshots/                   # README 截图（zh/ 与 en/ 各一套）
├── README.md                      # 本文件
└── GITHUB_GUIDE.md                # 维护者的 GitHub 操作手册
```

## 路线图

- [x] 显示器列表 + 切换主屏
- [x] 外接屏左/右移动
- [x] 扩展 / 镜像切换
- [x] 自定义 App 图标
- [x] 中英双语界面切换
- [x] 设置窗口（通用 / 预设 / 关于）
- [x] 开机自启动选项
- [x] 切换后系统通知
- [x] 自动刷新显示器列表
- [x] 菜单显示刷新率与 HiDPI
- [x] 显示器布局预设（一键保存/切换整套配置）
- [x] 菜单内切换外接屏刷新率
- [x] 全局快捷键（每个预设绑定一个快捷键）
- [x] 气泡卡片面板 UI（替换原生文字菜单）
- [x] 面板内布局预览（按真实比例绘制显示器位置）
- [x] 跟随系统强调色
- [ ] 适配 Intel 芯片
- [ ] 多屏（>2）场景优化
- [ ] Apple 公证

## License

MIT License。本仓库代码 © MoniSwitch 作者。
随包分发的 displayplacer © Jake Hilborn，同样为 MIT License。

## 致谢

- [displayplacer](https://github.com/jakehilborn/displayplacer) — 没有这个优秀的命令行工具，本项目就无法实现底层显示器控制。
