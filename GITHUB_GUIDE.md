# 🍎 MoniSwitch · GitHub 维护手册

这份文档专为你（项目作者）准备，手把手教你完成 GitHub 的所有操作。
**不需要任何 Git 经验**，照着复制粘贴命令即可。

---

## 📋 目录

- [一次性准备：安装并登录 GitHub CLI](#一次性准备安装并登录-github-cli)
- [🚀 第一次上传项目到 GitHub](#-第一次上传项目到-github)
- [🔄 每次更新 App 版本（日常维护）](#-每次更新-app-版本日常维护)
- [📦 发布 Release（让别人下载 DMG）](#-发布-release让别人下载-dmg)
- [🆘 常见问题](#-常见问题)

---

## 一次性准备：安装并登录 GitHub CLI

只需要做**一次**。

### 第 1 步：确认 `gh` 命令可用

打开「终端」，输入：
```bash
gh --version
```
- 如果显示版本号（如 `gh version 2.x.x`）→ ✅ 已安装，跳到「登录」
- 如果提示 `command not found` → 用 Homebrew 安装：
  ```bash
  brew install gh
  ```

### 第 2 步：登录 GitHub 账号

```bash
gh auth login
```
按提示操作（推荐选）：
1. `GitHub.com`
2. `HTTPS`
3. 用浏览器登录（会自动打开网页让你授权）

登录成功后，验证：
```bash
gh auth status
```
显示 `Logged in to github.com as 你的用户名` 即可。

---

## 🚀 第一次上传项目到 GitHub

### 第 1 步：创建 `.gitignore`（已为你准备好）

项目根目录已有 `.gitignore`，它会自动忽略编译产物（`.build/`、`*.dmg`、`MoniSwitch.app` 等），避免把大文件塞进仓库。

### 第 2 步：把代码交给 Git 管理 + 推送到 GitHub

在**项目根目录**（`MoniSwitch/`）执行下面**这一条命令**：

```bash
gh repo create MoniSwitch --public --source=. --remote=origin --push --description "macOS 菜单栏显示器快捷切换工具"
```

这条命令会**一次完成**：
- ✅ 在 GitHub 上创建名为 `MoniSwitch` 的公开仓库
- ✅ 本地 `git init` 初始化
- ✅ 把所有文件提交为第一次 commit
- ✅ 推送到 GitHub

执行完，打开浏览器访问 `https://github.com/你的用户名/MoniSwitch` 就能看到代码了。

> 💡 想要私有仓库？把 `--public` 改成 `--private`。

### 第 3 步：验证

```bash
git log --oneline        # 应能看到第一次提交
git remote -v            # 应能看到 origin 指向 GitHub
```

---

## 🔄 每次更新 App 版本（日常维护）

无论是修 bug、加功能，还是改文案，流程都是这三步：

### 第 1 步：查看改了什么
```bash
git status
```
红色 = 改动过但还没记录；绿色 = 已记录待上传。

### 第 2 步：记录改动并上传
```bash
git add .
git commit -m "这里写本次改了什么，用中文即可"
git push
```

- `git add .` — 把所有改动加入待提交清单
- `git commit -m "说明"` — 把改动打包成一个版本快照，引号里写说明
- `git push` — 上传到 GitHub

**就这么简单。** 三条命令，复制粘贴即可。

---

## 📦 发布 Release（让别人下载 DMG）

Release 是 GitHub 上让人下载安装包（`.dmg`）的地方。
**每次有新版本想发布给别人用时**，执行以下步骤：

### 第 1 步：先打包 DMG

在项目根目录：
```bash
bash Support/build-app.sh
```
确认 `Support/MoniSwitch.dmg` 已生成。

### 第 2 步：打标签（Tag）

标签是版本号的标记。版本号建议用 `v主.次.修订` 格式，例如 `v1.0.0`。

```bash
git tag v1.0.0
git push origin v1.0.0
```

> 发新版本时数字递增：`v1.0.0` → `v1.0.1`（修小 bug）→ `v1.1.0`（加新功能）→ `v2.0.0`（大改）

### 第 3 步：创建 Release 并上传 DMG

```bash
gh release create v1.0.0 ./Support/MoniSwitch.dmg \
    --title "MoniSwitch 1.0.0" \
    --notes "第一个正式版本，支持切换主屏、左右移动外接屏、扩展/镜像切换。"
```

执行完，别人就能在 `https://github.com/你的用户名/MoniSwitch/releases` 看到 DMG 下载链接了。

### 后续发布新版本时

重复上面三步，把版本号递增即可。例如发 v1.0.1：

```bash
bash Support/build-app.sh
git tag v1.0.1
git push origin v1.0.1
gh release create v1.0.1 ./Support/MoniSwitch.dmg \
    --title "MoniSwitch 1.0.1" \
    --notes "修复了 xxx 问题。"
```

---

## 🆘 常见问题

### Q: `git push` 报错 `failed to push some refs`？
A: 可能是远程有了你本地没有的改动。先同步：
```bash
git pull --rebase origin main
git push
```

### Q: 不小心提交了不该提交的大文件？
A: `.dmg` 和 `.app` 已在 `.gitignore` 里被忽略，正常不会误传。如果真传了，告诉我帮你清理。

### Q: 想撤销最近的提交？
A:
```bash
git reset HEAD~1          # 撤销最近一次提交，但保留文件改动
```

### Q: 忘了这次改了什么？
A:
```bash
git log --oneline -5      # 看最近 5 次提交
git diff                  # 看当前未提交的具体改动
```

### Q: 想给项目加个开源协议？
A: 已经有了 —— 本项目用 MIT License（见 README）。

---

## 📌 速查表（贴在显示器边上）

| 场景 | 命令 |
|------|------|
| 上传日常改动 | `git add . && git commit -m "说明" && git push` |
| 看改了什么 | `git status` |
| 看历史 | `git log --oneline` |
| 重新打包 | `bash Support/build-app.sh` |
| 发布新版本 | `git tag vX.Y.Z && git push origin vX.Y.Z` 然后 `gh release create ...` |

---

记住：**不确定的时候，先别执行破坏性命令，把命令发给我，我帮你确认。** 🛡️
