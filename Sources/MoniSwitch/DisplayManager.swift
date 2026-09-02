import Foundation

/// 显示器管理核心：解析 `displayplacer list` 输出，并提供
/// 切换主屏 / 移动外接屏左右 / 镜像-扩展 的操作。
///
/// 所有切换操作最终都转换成一条 `displayplacer "id:... ..."` 命令调用。
/// displayplacer 的核心规则：
///   - origin 为 (0,0) 的屏即为主显示器（系统设置里白条所在屏）
///   - 镜像用 `id:A+B` 语法，A 为基准屏，B 被镜像到 A
final class DisplayManager {

    // 单例，方便 UI 直接引用
    static let shared = DisplayManager()

    private init() {}

    /// 最近一次解析时记录的镜像组。
    /// 判定依据：origin 完全相同的屏视为同一镜像组（见 detectMirrorGroups）。
    /// 每个元素是一组共享 origin 的屏幕 id，供 isMirroring / unmirror 查询。
    private(set) var mirrorGroups: [[String]] = []

    // MARK: - 解析

    /// 运行 `displayplacer list` 并解析出当前所有屏幕。
    /// - Returns: 屏幕信息数组。失败时返回空数组。
    func currentDisplays() -> [DisplayInfo] {
        let result: ShellResult
        do {
            result = try ShellRunner.run(["list"])
        } catch {
            return []
        }
        guard result.succeeded else { return [] }
        return parseList(result.stdout)
    }

    /// 抓取当前显示器布局的 displayplacer 参数快照，供预设保存使用。
    ///
    /// 关键：必须感知镜像组。displayplacer 的镜像用 `id:基准+副1+副2` 语法
    /// （合并成一条 arg，整组共用基准屏的 res/scaling/origin），而非把每块屏
    /// 各拼一条 origin 相同的独立 arg——后者会被 displayplacer 当成"两块独立屏
    /// 叠在 (0,0)"，导致后执行的 arg 把副屏设为主屏（这是预设失效的根因）。
    ///
    /// - 非 mirrorGroups 里的屏：逐条拼（与 makeScreenArg 同源）。
    /// - 镜像组内的屏：合并成一条 arg，基准屏在首位，副屏用 + 追加。
    /// - Returns: 参数数组；失败返回空数组。
    func currentSnapshotArgs() -> [String] {
        let displays = currentDisplays()
        guard !displays.isEmpty else { return [] }

        // 收集所有已归入镜像组的 id，避免后面又被当作独立屏拼一次。
        var mirroredIDs = Set<String>()
        for group in mirrorGroups {
            mirroredIDs.formUnion(group)
        }

        var args: [String] = []

        // 1. 先处理镜像组：每个组生成一条合并 arg。
        for group in mirrorGroups {
            // 组里找出基准屏（主屏优先；都不是主屏则取第一个）。
            // 镜像态下副屏的 res/scaling 等无意义，整组用基准屏的配置。
            let members = displays.filter { group.contains($0.id) }
            guard let base = members.first(where: { $0.isMain }) ?? members.first else { continue }
            let others = members.filter { $0.id != base.id }

            // id:基准+副1+副2，共用基准屏的 res/hz/scaling/origin。
            let combinedID = [base.id] + others.map { $0.id }
            args.append(makeScreenArg(
                id: combinedID.joined(separator: "+"),
                res: base.resolution,
                hz: base.hertz,
                colorDepth: base.colorDepth,
                scaling: base.scalingOn,
                origin: base.origin,
                degree: base.degree
            ))
        }

        // 2. 再处理不在任何镜像组里的独立屏。
        for d in displays where !mirroredIDs.contains(d.id) {
            args.append(makeScreenArg(
                id: d.id,
                res: d.resolution,
                hz: d.hertz,
                colorDepth: d.colorDepth,
                scaling: d.scalingOn,
                origin: d.origin,
                degree: d.degree
            ))
        }

        return args
    }

    /// 应用一组 displayplacer 参数（预设回放）。
    /// - Parameter args: 每块屏一条裸配置串（与 currentSnapshotArgs 输出同格式）。
    /// - Returns: 是否执行成功。
    @discardableResult
    func applyArgs(_ args: [String]) -> Bool {
        runConfig(args)
    }

    /// 解析 `displayplacer list` 的纯文本输出。
    ///
    /// 关于镜像态的输出格式（经 displayplacer 源码 DisplayPlacer.c 核实）：
    ///   - 每块屏（含被镜像的副屏）都会独立打印一个完整 block；
    ///   - `Persistent screen id:` 行永远只有一个 UUID，**不会**带加号；
    ///   - 镜像组的主副屏**共享完全相同的 origin**（源码用 CGDisplayBounds 取值，
    ///     镜像态下主副屏 bounds 一致）。
    /// 因此镜像检测的正确依据是：多块屏 origin 相同 → 属于同一镜像组。
    func parseList(_ text: String) -> [DisplayInfo] {
        var displays: [DisplayInfo] = []
        mirrorGroups.removeAll()        // 每次解析重置

        // 用 "Persistent screen id:" 切分成多个屏块
        let blocks = text.components(separatedBy: "Persistent screen id:")

        for block in blocks {
            // 第一个 block 是 list 末尾的提示文本（在第一个 "Persistent" 之前），跳过
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.contains("Resolution:") else { continue }

            // 把块第一行（ID 本身）拼回来，解析为单块屏
            let fullBlock = "Persistent screen id:" + block
            if let info = parseBlock(fullBlock) {
                displays.append(info)
            }
        }

        // —— 镜像组检测：origin 完全相同的屏归为一组 ——
        // 扩展模式下每块屏 origin 各不相同；镜像模式下主副屏 origin 一致。
        detectMirrorGroups(in: displays)

        return displays
    }

    /// 按 origin 对屏幕分组：同一 origin 上有多块屏即视为镜像组。
    /// 只记录 size >= 2 的组，写入 mirrorGroups 供 isMirroring / unmirror 使用。
    private func detectMirrorGroups(in displays: [DisplayInfo]) {
        // 用 "x,y" 字符串作字典 key（元组不能直接做 Dictionary key）
        var byOrigin: [String: [String]] = [:]
        for d in displays {
            let key = "\(d.origin.x),\(d.origin.y)"
            byOrigin[key, default: []].append(d.id)
        }
        for (_, ids) in byOrigin where ids.count >= 2 {
            mirrorGroups.append(ids)
        }
    }

    /// 解析单个屏块。
    private func parseBlock(_ block: String) -> DisplayInfo? {
        let id = value(of: "Persistent screen id:", in: block)?
            .trimmingCharacters(in: .whitespaces)

        // 处理可能的 "id:A+B" 镜像形式：取第一个 ID 作为该块代表
        let cleanID = id?.components(separatedBy: "+").first?.trimmingCharacters(in: .whitespaces)
        guard let cleanID, !cleanID.isEmpty else { return nil }

        let typeName = value(of: "Type:", in: block)?.trimmingCharacters(in: .whitespaces) ?? "Unknown display"

        let resolution = parseResolution(value(of: "Resolution:", in: block))
        let origin = parseOrigin(value(of: "Origin:", in: block))
        let isMain = block.localizedCaseInsensitiveContains("main display")
        let scalingOn = (value(of: "Scaling:", in: block)?.localizedCaseInsensitiveContains("on")) ?? false
        let hertz = Int(value(of: "Hertz:", in: block)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 60
        let colorDepth = Int(value(of: "Color Depth:", in: block)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 8
        let degree = Int(value(of: "Rotation:", in: block)?
            .components(separatedBy: .whitespaces).first ?? "") ?? 0

        // 解析当前分辨率下可选的刷新率：从 "Resolutions for rotation" 段的
        // "mode N: res:WxH hz:X" 行里，筛出与当前分辨率相同的模式，收集 hz 去重升序。
        let availableRates = parseRefreshRates(for: resolution, in: block)
        // 解析该屏所有可选分辨率（去重，保持首次出现顺序）。
        let availableResolutions = parseResolutions(in: block)

        return DisplayInfo(
            id: cleanID,
            typeName: typeName,
            resolution: resolution,
            origin: origin,
            isMain: isMain,
            scalingOn: scalingOn,
            hertz: hertz,
            colorDepth: colorDepth,
            degree: degree,
            availableRefreshRates: availableRates,
            availableResolutions: availableResolutions
        )
    }

    /// 解析屏块里出现的所有分辨率（去重，保持 displayplacer 输出顺序）。
    /// 解析 "mode N: res:WxH hz:X" 行，收集全部 (W,H)，不去重为单维度，按 "WxH" 字符串去重。
    private func parseResolutions(in block: String) -> [(width: Int, height: Int)] {
        // 与 parseRefreshRates 共用正则，但不过滤当前分辨率。
        let pattern = #"res:(\d+)x(\d+)\s+hz:(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(block.startIndex..., in: block)
        var seen = Set<String>()
        var result: [(width: Int, height: Int)] = []
        regex.enumerateMatches(in: block, options: [], range: range) { match, _, _ in
            guard let match,
                  let wRange = Range(match.range(at: 1), in: block),
                  let hRange = Range(match.range(at: 2), in: block) else { return }
            let w = Int(block[wRange]) ?? 0
            let h = Int(block[hRange]) ?? 0
            guard w > 0, h > 0 else { return }
            let key = "\(w)x\(h)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append((width: w, height: h))
        }
        return result
    }

    /// 从屏块里解析与指定分辨率匹配的所有刷新率。
    /// 解析 "mode N: res:WxH hz:X" 行，只保留 res 等于目标分辨率的 hz，去重升序。
    private func parseRefreshRates(for targetRes: (width: Int, height: Int),
                                   in block: String) -> [Int] {
        guard targetRes.width > 0, targetRes.height > 0 else { return [] }
        // 匹配 "res:WxH hz:X"，捕获 H 的数字部分
        let pattern = #"res:(\d+)x(\d+)\s+hz:(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(block.startIndex..., in: block)
        var rates = Set<Int>()
        regex.enumerateMatches(in: block, options: [], range: range) { match, _, _ in
            guard let match,
                  let wRange = Range(match.range(at: 1), in: block),
                  let hRange = Range(match.range(at: 2), in: block),
                  let hzRange = Range(match.range(at: 3), in: block) else { return }
            let w = Int(block[wRange]) ?? 0
            let h = Int(block[hRange]) ?? 0
            // 只收当前分辨率下的刷新率
            guard w == targetRes.width && h == targetRes.height else { return }
            if let hz = Int(block[hzRange]) {
                rates.insert(hz)
            }
        }
        return rates.sorted()
    }

    /// 从 block 中取 "Key: value" 的 value 部分。
    private func value(of key: String, in block: String) -> String? {
        guard let range = block.range(of: key) else { return nil }
        let afterKey = block[range.upperBound...]
        // 取到该行结尾为止
        let lineEnd = afterKey.firstIndex(where: { $0 == "\n" || $0 == "\r" }) ?? afterKey.endIndex
        return String(afterKey[..<lineEnd])
    }

    private func parseResolution(_ raw: String?) -> (Int, Int) {
        guard let raw else { return (0, 0) }
        // 形如 "3440x1440"
        let parts = raw.trimmingCharacters(in: .whitespaces).components(separatedBy: "x")
        if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1].filter(\.isNumber)) {
            return (w, h)
        }
        return (0, 0)
    }

    private func parseOrigin(_ raw: String?) -> (Int, Int) {
        guard let raw else { return (0, 0) }
        // 形如 "(0,0) - main display" 或 "(-1512,0)"
        guard let paren = raw.range(of: "("),
              let close = raw.range(of: ")", range: paren.upperBound..<raw.endIndex) else {
            return (0, 0)
        }
        let nums = String(raw[paren.upperBound..<close.lowerBound]) // "0,0"
        let parts = nums.components(separatedBy: ",")
        let x = Int(parts.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        let y = (parts.count > 1) ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        return (x, y)
    }

    // MARK: - 稳定检测

    /// 轮询 `displayplacer list`，直到配置输出连续两次一致或超时，返回稳定后的屏幕列表。
    ///
    /// 存在原因：displayplacer 进程退出 ≠ 系统显示器配置已生效。CoreGraphics 的
    /// 重配（display mode 切换 + origin 变更）是异步的，镜像/扩展类操作全程约
    /// 1.2~1.5 秒。期间：
    ///   - 立即 currentDisplays() 会读到重配未完成的旧值（面板高亮不跟随）；
    ///   - 立即提交 UNUserNotificationCenter 请求会被系统中断/丢弃（通知不弹出）。
    /// 用「连续两次读取结果一致」判定重配结束，替代按操作类型猜固定延迟的盲等。
    ///
    /// - Parameters:
    ///   - pollInterval: 轮询间隔（秒）。
    ///   - maxWait: 最长等待（秒），超时返回最后一次读取结果。
    /// - Returns: 稳定后的屏幕列表。必须在后台线程调用（内部同步跑 shell 并 sleep）。
    func waitForStableDisplays(pollInterval: TimeInterval = 0.25,
                               maxWait: TimeInterval = 3.0) -> [DisplayInfo] {
        var last = currentDisplays()
        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            let next = currentDisplays()
            // 比对关键字段签名（DisplayInfo 的 == 只比 id，不能直接用数组判等）
            if displayListSignature(last) == displayListSignature(next) {
                return next
            }
            last = next
        }
        return last
    }

    /// 屏幕列表的配置签名：每屏取 id/分辨率/origin/刷新率/主屏位拼接，排序后合并。
    /// 两次签名一致即认为系统配置已稳定。
    private func displayListSignature(_ displays: [DisplayInfo]) -> String {
        displays
            .map { "\($0.id)|\($0.resolution.width)x\($0.resolution.height)|\($0.origin.x),\($0.origin.y)|\($0.hertz)|\($0.isMain)" }
            .sorted()
            .joined(separator: ";")
    }

    // MARK: - 预设 id 漂移兜底

    /// 尝试把预设 args 里的旧 persistent id 重映射到当前屏，抵御 id 漂移。
    ///
    /// 背景：外接屏唤醒/重插拔/换屏后 displayplacer 的 persistent id 可能变化，
    /// 导致预设里的旧 id 找不到屏、回放失效。兜底策略（保守，宁缺毋滥）：
    ///   1. 所有旧 id 仍存在 → 无漂移，返回 nil（调用方按原 args 应用）；
    ///   2. 旧 id 总数 ≠ 当前屏数 → 环境已实质变化，返回 nil（不猜）；
    ///   3. 按条目匹配：分辨率一致的未分配屏中依序取用；镜像合并条目（id:A+B）
    ///      按段逐一映射；分辨率全部对不上但剩余屏恰好一一对应时兜底直配。
    ///   4. 任一条目无法完整匹配 → 返回 nil（按原样应用，行为与旧版一致）。
    /// - Returns: 需要改写且能完整改写时返回新 args；否则 nil。
    func remappedArgsIfDrifted(_ args: [String], current: [DisplayInfo]) -> [String]? {
        guard !args.isEmpty, !current.isEmpty else { return nil }

        // 每条 arg 的 (id 列表, 分辨率)
        var entries: [(ids: [String], res: (Int, Int))] = []
        for arg in args {
            guard let ids = idTokens(of: arg), let res = resToken(of: arg) else { return nil }
            entries.append((ids, res))
        }

        // 全部旧 id 仍有效 → 无漂移。
        let currentIDs = Set(current.map(\.id))
        let argIDs = entries.flatMap(\.ids)
        guard !argIDs.allSatisfy({ currentIDs.contains($0) }) else { return nil }

        // 屏数量必须一致（镜像合并条目的段数也计入），否则视为环境已实质变化。
        guard argIDs.count == current.count else { return nil }

        // 逐条目分配屏。
        var used = Set<String>()
        var mapping: [String: String] = [:]   // 旧 id → 新 id
        for entry in entries {
            var candidates = current.filter { !used.contains($0.id) && $0.resolution == entry.res }
            if candidates.isEmpty {
                // 分辨率也变了（如外接换了档位）：仅在剩余屏与条目段数恰好一一对应时兜底。
                let rest = current.filter { !used.contains($0.id) }
                guard entry.ids.count == rest.count else { return nil }
                candidates = rest
            }
            guard candidates.count >= entry.ids.count else { return nil }
            for (i, oldID) in entry.ids.enumerated() {
                mapping[oldID] = candidates[i].id
                used.insert(candidates[i].id)
            }
        }

        // 改写每条 arg 的 id 段（其余字段原样保留）。
        return args.map { replacingIDs(in: $0, mapping: mapping) }
    }

    /// 解析 arg 的 id 段：`id:A+B+C res:…` → ["A","B","C"]。
    private func idTokens(of arg: String) -> [String]? {
        guard arg.hasPrefix("id:") else { return nil }
        let rest = arg.dropFirst(3)
        let segment = rest.prefix(while: { $0 != " " })
        let ids = segment.split(separator: "+").map(String.init)
        return ids.isEmpty ? nil : ids
    }

    /// 解析 arg 的分辨率段：`… res:3440x1440 …` → (3440, 1440)。
    private func resToken(of arg: String) -> (Int, Int)? {
        guard let range = arg.range(of: "res:") else { return nil }
        let segment = arg[range.upperBound...].prefix(while: { $0 != " " })
        let parts = segment.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
        return (w, h)
    }

    /// 把 arg 的 id 段按映射表替换（镜像合并结构 id:A+B 逐段替换），其余原样保留。
    private func replacingIDs(in arg: String, mapping: [String: String]) -> String {
        guard arg.hasPrefix("id:") else { return arg }
        let rest = arg.dropFirst(3)
        let segment = rest.prefix(while: { $0 != " " })
        let tail = rest.dropFirst(segment.count)
        let newIDs = segment
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { mapping[String($0)] ?? String($0) }
        return "id:" + newIDs.joined(separator: "+") + tail
    }

    // MARK: - 操作

    /// 切换主显示器：把目标屏 origin 平移到 (0,0)，其余屏按相同向量平移，
    /// 保持它们之间的物理左右关系不变。
    /// - Parameter displays: 当前屏幕列表（来自 currentDisplays()）
    /// - Parameter target: 要设为主屏的那个屏幕
    /// - Returns: 执行是否成功
    @discardableResult
    func setPrimary(_ target: DisplayInfo, in displays: [DisplayInfo]) -> Bool {
        let dx = -target.origin.x
        let dy = -target.origin.y

        // displayplacer 要求每块屏都给完整配置；我们尽量保留各自原有 res/scaling。
        let args = displays.map { d -> String in
            let newX = d.origin.x + dx
            let newY = d.origin.y + dy
            return makeScreenArg(
                id: d.id,
                res: d.resolution,
                hz: d.hertz,
                colorDepth: d.colorDepth,
                scaling: d.scalingOn,
                origin: (newX, newY),
                degree: d.degree
            )
        }
        return runConfig(args)
    }

    /// 把外接屏放到主屏的左侧或右侧（扩展模式，非镜像）。
    ///
    /// 处理两种主屏情况：
    /// - 主屏是内置屏：常规情况，把外接屏挪到主屏左/右
    /// - 主屏是外接屏本身（即 external 就是主屏）：此时"移动"等价于把另一块屏
    ///   （通常是内置屏）整体平移到外接屏的对侧，外接屏保持 (0,0) 不变
    /// - Parameter side: .left 或 .right
    @discardableResult
    func moveExternal(_ external: DisplayInfo,
                      side: HorizontalSide,
                      in displays: [DisplayInfo]) -> Bool {
        guard let main = displays.first(where: { $0.isMain }) else { return false }

        // 情况 A：外接屏本身就是主屏 → 移动它无意义，应改为平移所有"其他屏"
        if external.isMain {
            return moveOthersRelative(to: external, side: side, in: displays)
        }

        // 情况 B：常规——外接是非主屏，挪到主屏左/右
        let newOriginX: Int
        switch side {
        case .left:
            // 外接右边缘紧贴主屏左边缘
            newOriginX = main.origin.x - external.resolution.width
        case .right:
            // 外接左边缘紧贴主屏右边缘
            newOriginX = main.origin.x + main.resolution.width
        }
        // y 轴与主屏顶部对齐
        let newOriginY = main.origin.y

        let args = displays.map { d -> String in
            if d.id == external.id {
                return makeScreenArg(
                    id: d.id,
                    res: d.resolution,
                    hz: d.hertz,
                    colorDepth: d.colorDepth,
                    scaling: d.scalingOn,
                    origin: (newOriginX, newOriginY),
                    degree: d.degree
                )
            } else {
                return makeScreenArg(
                    id: d.id,
                    res: d.resolution,
                    hz: d.hertz,
                    colorDepth: d.colorDepth,
                    scaling: d.scalingOn,
                    origin: d.origin,
                    degree: d.degree
                )
            }
        }
        return runConfig(args)
    }

    /// 外接屏为主屏时：把它当作锚点，把所有其他屏移到它的左/右侧。
    /// 外接屏自身保持 (0,0)，其他屏放到 (外接宽, 0)（右侧）或 (-其他宽, 0)（左侧）。
    private func moveOthersRelative(to mainExternal: DisplayInfo,
                                    side: HorizontalSide,
                                    in displays: [DisplayInfo]) -> Bool {
        let args = displays.map { d -> String in
            if d.id == mainExternal.id {
                // 主屏外接保持 (0,0)
                return makeScreenArg(
                    id: d.id, res: d.resolution, hz: d.hertz,
                    colorDepth: d.colorDepth, scaling: d.scalingOn,
                    origin: (0, 0), degree: d.degree
                )
            }
            // 其他屏根据 side 放到主屏外接的左/右
            let x: Int
            switch side {
            case .left:  x = -d.resolution.width              // 在主屏左侧
            case .right: x = mainExternal.resolution.width    // 在主屏右侧
            }
            return makeScreenArg(
                id: d.id, res: d.resolution, hz: d.hertz,
                colorDepth: d.colorDepth, scaling: d.scalingOn,
                origin: (x, 0), degree: d.degree
            )
        }
        return runConfig(args)
    }

    /// 镜像：以当前主屏为基准，把 external 镜像成与主屏相同的内容。
    ///
    /// displayplacer 语法 `id:基准+被镜像`：
    /// - 基准屏放第一个，作为"优化对象"，并固定 origin (0,0)
    /// - 被镜像屏（external）跟在 + 号后
    /// - 镜像时共用基准屏的分辨率
    ///
    /// 这样无论内置还是外接是主屏，点"镜像主屏"都能让外接显示与主屏一致的内容。
    @discardableResult
    func mirror(_ external: DisplayInfo, to main: DisplayInfo) -> Bool {
        let arg = "id:\(main.id)+\(external.id) " +
                  "res:\(main.resolution.width)x\(main.resolution.height) " +
                  "scaling:\(main.scalingOn ? "on" : "off") " +
                  "origin:(0,0) degree:0"
        return runConfig([arg])
    }

    /// 判断某块屏当前是否处于镜像组中。
    /// - Parameter display: 要查询的屏；与主屏一并用于检测，任一在镜像组即视为镜像态。
    /// - Parameter main: 当前主屏（可省略，内部会查 mirrorGroups 是否同时包含两者）。
    ///
    /// 实现：只要 display.id 出现在任意一个 mirrorGroup 里，就认为处于镜像态。
    /// 这样无论 display 是基准屏还是被镜像屏都能正确判定。
    func isMirroring(_ display: DisplayInfo, _ main: DisplayInfo) -> Bool {
        // 两块屏同时落在同一个镜像组 → 确定镜像关系
        if mirrorGroups.contains(where: { $0.contains(display.id) && $0.contains(main.id) }) {
            return true
        }
        // display 单独在某个镜像组里 → 也算镜像态（main 可能是补造的占位屏）
        return mirrorGroups.contains { $0.contains(display.id) }
    }

    /// 取消镜像，恢复为扩展（并排）布局：主屏在左 (0,0)，其余屏依次排在右侧。
    ///
    /// - Parameter main: 当前主屏（镜像态下的基准屏）。
    /// - Parameter external: 触发取消镜像的外接屏（保留入参兼容旧调用，实际遍历全表）。
    /// - Parameter displays: 当前完整屏幕列表；会遍历它生成每块屏的独立 arg，
    ///   避免"只发两块屏 arg、漏掉第三块"导致 displayplacer 把漏掉的屏禁用。
    @discardableResult
    func unmirror(main: DisplayInfo, external: DisplayInfo, in displays: [DisplayInfo]) -> Bool {
        var cursorX = 0   // 下一块屏的 origin.x，主屏右侧开始累加
        let args = displays.map { d -> String in
            let origin: (Int, Int)
            if d.id == main.id {
                // 主屏固定 (0,0)
                origin = (0, 0)
                cursorX = d.resolution.width
            } else {
                // 其余屏依次排在右侧，y 与主屏顶对齐
                origin = (cursorX, 0)
                cursorX += d.resolution.width
            }
            return makeScreenArg(
                id: d.id,
                res: d.resolution,
                hz: d.hertz,
                colorDepth: d.colorDepth,
                scaling: d.scalingOn,
                origin: origin,
                degree: d.degree
            )
        }
        return runConfig(args)
    }

    /// 切换某块屏的刷新率，其余屏保持不变。
    ///
    /// 实现方式：遍历所有屏生成 args，仅目标屏用新的 hz 值（分辨率/位置等不变）。
    /// - Parameters:
    ///   - hz: 目标刷新率。
    ///   - display: 要切换刷新率的屏。
    ///   - displays: 当前完整屏幕列表。
    /// - Returns: 是否执行成功。
    @discardableResult
    func setRefreshRate(hz: Int, for display: DisplayInfo, in displays: [DisplayInfo]) -> Bool {
        let args = displays.map { d -> String in
            makeScreenArg(
                id: d.id,
                res: d.resolution,
                hz: d.id == display.id ? hz : d.hertz,
                colorDepth: d.colorDepth,
                scaling: d.scalingOn,
                origin: d.origin,
                degree: d.degree
            )
        }
        return runConfig(args)
    }

    /// 切换某块屏的分辨率，其余屏保持不变。
    ///
    /// 实现方式：遍历所有屏生成 args，仅目标屏用新的 res（刷新率/位置等不变）。
    /// 注意：切换分辨率后该屏的可用刷新率集合可能变化，UI 刷新会通过 currentDisplays() 重读得到。
    /// - Parameters:
    ///   - res: 目标分辨率。
    ///   - display: 要切换分辨率的屏。
    ///   - displays: 当前完整屏幕列表。
    /// - Returns: 是否执行成功。
    @discardableResult
    func setResolution(_ res: (width: Int, height: Int), for display: DisplayInfo, in displays: [DisplayInfo]) -> Bool {
        let args = displays.map { d -> String in
            makeScreenArg(
                id: d.id,
                res: d.id == display.id ? res : d.resolution,
                hz: d.hertz,
                colorDepth: d.colorDepth,
                scaling: d.scalingOn,
                origin: d.origin,
                degree: d.degree
            )
        }
        return runConfig(args)
    }

    // MARK: - 底层

    /// 拼接一块屏的 displayplacer 参数字符串。
    private func makeScreenArg(id: String,
                               res: (width: Int, height: Int),
                               hz: Int,
                               colorDepth: Int,
                               scaling: Bool,
                               origin: (x: Int, y: Int),
                               degree: Int) -> String {
        "id:\(id) " +
        "res:\(res.width)x\(res.height) " +
        "hz:\(hz) " +
        "color_depth:\(colorDepth) " +
        "scaling:\(scaling ? "on" : "off") " +
        "origin:(\(origin.x),\(origin.y)) " +
        "degree:\(degree)"
    }

    /// 执行一条 displayplacer 配置命令。
    private func runConfig(_ args: [String]) -> Bool {
        do {
            let result = try ShellRunner.run(args)
            if !result.succeeded {
                fputs("displayplacer 失败: \(result.stderr)\n", stderr)
            }
            return result.succeeded
        } catch {
            fputs("调用 displayplacer 出错: \(error)\n", stderr)
            return false
        }
    }
}

enum HorizontalSide {
    case left, right
}
