# Resources 目录

本目录存放随 App 一起打包的资源文件。

## 应用图标

- `AppIcon-source.png`：1024×1024 源图（透明留白），设计源在 `design/icon-web/moniswitch-icon.svg`。
- `AppIcon.icns`：由 `bash Support/make-app-icon.sh` 从 source 生成；`build-app.sh` 会把它拷进 .app。
- 换图标：导出新的 1024 PNG → 覆盖 `AppIcon-source.png` → 重建 icns → 重新打包。

## displayplacer 二进制

`displayplacer` 是 MoniSwitch 用来实际切换显示器的核心依赖。
它**不纳入 git 版本控制**（见根目录 `.gitignore`），因为：
1. 二进制文件不适合放 git 仓库
2. 不同架构（Apple Silicon arm64 / Intel x86_64）需要不同二进制

### 如何获取并放置

```bash
# 方式 A：从你已有的下载文件复制（Apple Silicon 版本）
cp /Users/millersun/Downloads/displayplacer-apple-v140 ./Resources/displayplacer

# 方式 B：用 Homebrew 获取（会自动匹配你的芯片架构）
brew install displayplacer
cp $(brew --prefix displayplacer)/bin/displayplacer ./Resources/displayplacer

# 方式 C：从 GitHub Release 下载
# https://github.com/jakehilborn/displayplacer/releases
```

放置后赋予可执行权限：

```bash
chmod +x ./Resources/displayplacer
```

打包脚本 `Support/build-app.sh` 会自动清除其 macOS 隔离标记并重新签名。

### 版本要求

- displayplacer **v1.4.0** 或更高
- Apple Silicon Mac：下载 `displayplacer-apple-vXXX`
- Intel Mac：下载 `displayplacer-intel-vXXX`

### License

displayplacer 由 Jake Hilborn 开发，采用 MIT License。
详见：https://github.com/jakehilborn/displayplacer
