<h1 align="center">
  <img src="Resources/AppIcon-source.png?v=0.1.4" width="56" alt="MoniSwitch" align="middle"> MoniSwitch
</h1>

<p align="center">
  一个 macOS 菜单栏小工具，不用进「系统设置 → 显示器」就能切换主显示器、调整外接屏的左右位置，以及切换外接屏的扩展/镜像。
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文 · <a href="https://m1688-cpu.github.io/MoniSwitch/">官网</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="platform">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="arch">
  <img src="https://img.shields.io/badge/version-0.1.5-blue" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- 菜单栏常驻：点击图标弹出气泡卡片面板，原生 popover 观感（箭头指向图标、在图标上居中、展开动画），点击面板外任意位置即收起
- 在面板里点任意显示器，即可把它设为主显示器（白条所在屏）
- 展开某块屏的参数组，可把外接屏放到主屏的左边或右边
- 排列卡可折叠：每块屏的 位置/分辨率/刷新率 折叠在屏名行下，默认收起、同时只展开一块屏；点击布局图中的屏块可直接定位展开
- 面板高度随内容自适应（不再内部滚动）；展开/收起为平滑弹簧动画，卡片悬停时轻微浮起
- 一键把外接屏在「扩展显示」和「镜像主屏」之间切换，面板会标注镜像目标屏
- 一键自动排列：所有屏横向排开、消除重叠，镜像组保持完整
- 布局预设：把整套显示器配置（主屏+位置+镜像）保存为预设，一键恢复（如「办公」「演示」）
- 与当前布局一致的预设自动带「当前」角标；比对依据是分辨率/刷新率/位置/镜像态，屏幕 id 漂移不影响判断
- 显示器重插拔导致 persistent id 变化时，自动按分辨率/屏数重映射，预设不会失效
- 面板内直接切换任意屏（含主屏）的刷新率（如 60Hz ↔ 120Hz）与分辨率
- 分辨率选项标注 HiDPI / 低分辨率变体，重选分辨率不再丢失 HiDPI 缩放（4K 屏不再出现「选完分辨率图标变小」）
- 给每个预设绑定一个全局快捷键（Carbon `RegisterEventHotKey`，无需任何权限），按下即应用对应布局
- 布局预览按真实比例绘制；点击屏块选中并联动展开该屏参数组，悬停列表行时对应屏块高亮
- 切换进行中显示进度条并防连点；失败会弹系统通知
- 面板与设置窗口随「系统设置 → 外观 → 强调色」实时刷新，无固定品牌色
- 设置窗口涵盖：中英双语、开机自启动、自动刷新列表（可选刷新间隔）、切换后通知
- 界面语言一键切换，重启后保持

## 截图

> 界面语言一键切换（中文 / English），下列截图以中文界面为准。

<table>
  <tr>
    <td align="center">
      <img src="screenshots/zh/panel-overview.png?v=0.1.5" alt="面板全貌">
      <br><b>面板全貌</b> · 主屏切换 / 排列与镜像 / 预设 / 布局预览 / 底部工具栏
      <br><sub>气泡卡片面板，跟随系统强调色</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/zh/panel-arrange.png?v=0.1.5" alt="排列展开">
      <br><b>排列展开</b> · 位置/分辨率/刷新率参数组 + 镜像/扩展
      <br><sub>点击屏名行展开参数组，分辨率行可再展开选项列表（含 HiDPI 标注）</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/zh/settings-general.png" width="420" alt="设置-通用">
      <br><b>设置 · 通用</b> · 语言 / 自启动 / 自动刷新 / 通知
      <br><sub>开启自动刷新后显示刷新间隔选择器</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/zh/settings-presets.png" width="420" alt="设置-预设">
      <br><b>设置 · 预设</b> · 保存 / 应用 / 删除 + 全局快捷键绑定
      <br><sub>每个预设可录制一个快捷键（Esc 取消）</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/zh/settings-about.png?v=0.1.5" width="420" alt="设置-关于">
      <br><b>设置 · 关于</b> · 图标 / 简介 / 版本号
    </td>
  </tr>
</table>

## 安装

### 方式一：下载 DMG（普通用户推荐）

<p align="center">
  <img src="screenshots/dmg-install.png" width="560" alt="DMG 拖拽安装">
  <br><sub>双击打开 DMG，把左边的 MoniSwitch 拖到右边的 Applications</sub>
</p>

1. 前往 [Releases 页面](../../releases)，下载最新的 `MoniSwitch.dmg`
2. 双击打开，把 MoniSwitch 拖入 Applications 文件夹
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
2. 点击图标弹出面板，看到当前所有显示器与布局预览
3. 主屏卡：点击任意显示器名称，即可设为主屏
4. 排列与镜像卡：点击屏名行展开该屏的参数组，可调整左右位置、分辨率、刷新率；外接屏在此切换镜像/扩展，或一键自动排列
5. 预设卡：点击预设名一键恢复整套布局，与当前布局一致的预设带「当前」角标
6. 点击面板外任意位置即可收起面板

## 关于未公证提示

MoniSwitch 采用「DMG 直链分发」而非 Mac App Store，因此没有 Apple 公证。
这是开源/免费小工具的常见做法，App 本身安全（代码完全开源可审查）。
首次打开按上述步骤在「隐私与安全性」放行即可，之后不会再提示。

## 工作原理

MoniSwitch 是一个图形界面，底层调用 [displayplacer](https://github.com/jakehilborn/displayplacer)（MIT License，© Jake Hilborn）完成实际的显示器配置。
displayplacer 二进制随 App 一起打包，开箱即用。

- 切换主屏：把目标屏的 `origin` 平移到 `(0,0)`，其余屏按相同向量平移以保持左右关系
- 左/右移动：调整外接屏的 `origin.x`
- 镜像/扩展：使用 displayplacer 的 `id:A+B` 镜像语法 / 还原为并排扩展布局

## 技术栈

- 语言：Swift 6
- UI：SwiftUI + AppKit（`NSStatusItem` + `NSPopover` 菜单栏面板，macOS 13+）
- 构建：Swift Package Manager（纯文本 `Package.swift`，命令行即可编译）
- 类型：纯菜单栏 App（`LSUIElement = YES`，无 Dock 图标）
- 分发：非沙盒，本地 ad-hoc 签名，DMG 直链

## 项目结构

```
MoniSwitch/
├── Package.swift                  # SPM 构建配置
├── Sources/MoniSwitch/
│   ├── MoniSwitchApp.swift        # @main 入口（AppDelegate 启动菜单栏图标 + ⌘, 命令）
│   ├── PanelController.swift      # 菜单栏面板控制器（NSStatusItem + NSPopover 承载 PanelView）
│   ├── AppState.swift             # UI 状态对象（显示器列表 + 全部切换操作 + 进行中状态）
│   ├── PanelView.swift            # 菜单栏气泡卡片面板（主屏/排列/预设/交互式布局预览）
│   ├── Components.swift           # 全站共享视觉组件（BubbleCard/RowButton/ActivePill 等）
│   ├── BubbleMetrics.swift        # 圆角/字号/间距刻度 + 气泡背景色
│   ├── Models.swift               # 显示器数据模型
│   ├── ShellRunner.swift          # displayplacer 调用封装
│   ├── DisplayManager.swift       # 解析 + 切换算法（镜像组检测/自动排列/id 漂移重映射/稳定检测）
│   ├── AppSettings.swift          # 用户偏好单例（自启动/通知/自动刷新）
│   ├── PresetManager.swift        # 显示器布局预设管理（保存/应用/删除/快捷键绑定）
│   ├── HotkeyManager.swift        # 全局快捷键（Carbon RegisterEventHotKey，零权限）
│   ├── DockPolicyManager.swift    # Dock 策略 + 设置窗口宿主（NSWindow）
│   ├── SettingsView.swift         # 设置窗口骨架（边栏 + 悬浮标题 + 滚动毛玻璃）
│   ├── SettingsTabs.swift         # 设置窗口三个标签页（通用/预设/关于）
│   └── Localization.swift         # 中英双语（L10n 类 + TextKey 枚举）
├── Resources/
│   ├── displayplacer              # 打包的显示控制二进制（不入库）
│   ├── AppIcon.icns               # 应用图标
│   └── AppIcon-source.png         # 图标源图（make-app-icon-design.swift 自绘产物）
├── Support/
│   ├── Info.plist                 # App 元信息（LSUIElement 等）
│   ├── build-app.sh               # 一键打包脚本
│   └── make-app-icon.sh           # 重建 AppIcon.icns（默认纯代码自绘）
├── screenshots/                   # README 截图（en/zh 两套，文件名一一对应）
├── README.md                      # 默认 README（英文）
├── README.zh-CN.md                # 简体中文 README（本文件）
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
- [x] 纯代码自绘应用图标（Liquid Glass 风格显示器）
- [x] 操作进行中反馈（进度条 + 防连点）与失败通知
- [x] 一键自动排列（横向排开、消除重叠、保持镜像组）
- [x] 预设 id 漂移自动重映射
- [x] HiDPI 分辨率保真切换（变体标注，不再误入低分辨率模式）
- [x] 排列卡折叠交互（屏参数组折叠、布局图点击联动展开）
- [x] 预设「当前」角标
- [x] 面板 NSPopover 化（箭头/居中/展开动画/点外部收起）
- [ ] 适配 Intel 芯片
- [ ] 多屏（>2）场景优化
- [ ] Apple 公证

## License

MIT License。本仓库代码 © MoniSwitch 作者。
随包分发的 displayplacer © Jake Hilborn，同样为 MIT License。

## 致谢

- [displayplacer](https://github.com/jakehilborn/displayplacer)，本项目的底层显示器控制由它完成。
