# 在 ZCode 客户端把工作区切换到 MoniSwitch 子目录

## 背景

当前 ZCode 客户端的工作区根目录是：

```
/Users/millersun/ZCodeProject
```

MoniSwitch 项目实际位于其子目录：

```
/Users/millersun/ZCodeProject/MoniSwitch
```

把工作区根目录切到 `MoniSwitch` 子目录后，所有相对路径（如 `Sources/...`、`Support/...`、`swift build`、`bash Support/build-app.sh`）都会以 MoniSwitch 为根来解析，操作更直观，也不会误触父目录里其他项目。

下面给出三种方法，**推荐方法一**。

---

## 方法一：用 `/cwd`（或 `/init`）直接重设工作目录（推荐）

ZCode 客户端内置了重设当前工作目录的能力，无需重启。

1. 在输入框输入并执行：

   ```
   /cwd /Users/millersun/ZCodeProject/MoniSwitch
   ```

   或（不同版本命令名略有差异）：

   ```
   /init /Users/millersun/ZCodeProject/MoniSwitch
   ```

2. 执行后，当前会话的工作目录即变为 MoniSwitch 子目录。

3. 验证（可让助手执行或自己在终端确认）：

   ```bash
   pwd
   # 期望输出：/Users/millersun/ZCodeProject/MoniSwitch
   ```

> 如果 `/cwd`、`/init` 命令在你的客户端版本中不存在，可执行 `/help` 查看可用命令列表，或改用下面的方法二 / 方法三。

---

## 方法二：重新打开一个会话并指定目录

适合想要彻底以新根目录开始的情况。

1. 关闭当前会话，或点击「新建会话 / New Session」。
2. 在新建会话时，把「工作目录 / Workspace / Folder」字段填为：

   ```
   /Users/millersun/ZCodeProject/MoniSwitch
   ```

   或在系统文件选择器里逐层进入：`ZCodeProject` → `MoniSwitch` → 打开。

3. 新会话启动后即以 MoniSwitch 为根目录。

---

## 方法三：修改工作区配置文件（持久化）

如果上面两种临时方法不生效，或希望「以后每次打开这个工作区都默认是 MoniSwitch」，可改工作区配置。

1. 在你的 ZCode 配置目录下找到当前工作区的配置（常见路径示例，按实际安装位置为准）：

   ```
   ~/.zcode/projects/<工作区配置目录>/
   ```

   或工作区根下的（若支持）：

   ```
   /Users/millersun/ZCodeProject/.zcode/
   ```

2. 找到形如下面的字段（字段名以实际为准，常见为 `cwd` / `workspaceRoot` / `folder`），把它从父目录改到子目录：

   ```jsonc
   {
     // 改前
     "cwd": "/Users/millersun/ZCodeProject"

     // 改后
     "cwd": "/Users/millersun/ZCodeProject/MoniSwitch"
   }
   ```

3. 保存后，重启 ZCode 客户端或重新加载该工作区使配置生效。

> 配置文件的具体路径和字段名随客户端版本变化。若不确定位置，可让助手执行：
> ```bash
> grep -rl "ZCodeProject" ~/.zcode 2>/dev/null
> ```
> 来定位引用了旧根目录的配置文件。

---

## 验证切换成功

切换后，执行以下任一检查：

```bash
pwd
ls Package.swift            # 应能看到文件（确认在 SwiftPM 根目录）
swift build                 # 应正常编译
bash Support/build-app.sh   # 应正常打包
```

期望结果：

- `pwd` 输出 `/Users/millersun/ZCodeProject/MoniSwitch`
- 能直接看到并运行 `Package.swift`、`Sources/`、`Support/` 等 MoniSwitch 专属文件

---

## 常见问题

**Q：切到子目录后，之前对父目录其他项目的改动会不会丢？**
A：不会。切换工作目录只是改变 ZCode 解析相对路径的基准，不会移动或删除任何文件。父目录里的其他项目仍原样存在于磁盘上，需要时再切回去即可。

**Q：可以让助手以后一直把 MoniSwitch 当根目录吗？**
A：可以。用方法三把工作区配置里的根目录固定为子目录，或为 MoniSwitch 单独建一个工作区会话。

**Q：切换后 `git` 命令还在项目内吗？**
A：MoniSwitch 自身是 git 仓库（`.git` 在 `MoniSwitch/` 下）。切到子目录后，`git status` 等命令自然作用于 MoniSwitch 仓库，更符合预期。
