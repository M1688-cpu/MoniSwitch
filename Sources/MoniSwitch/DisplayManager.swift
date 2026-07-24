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

    /// 最近一次解析时记录的镜像对（id 对）。
    /// 当 displayplacer list 输出形如 "Persistent screen id: A+B" 时，
    /// 表示 A、B 处于镜像组，记为 (A, B)。供 isMirroring() 查询。
    private(set) var mirroredPairs: [(String, String)] = []

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

    /// 解析 `displayplacer list` 的纯文本输出。
    func parseList(_ text: String) -> [DisplayInfo] {
        var displays: [DisplayInfo] = []
        mirroredPairs = []  // 每次解析重置

        // 用 "Persistent screen id:" 切分成多个屏块
        let blocks = text.components(separatedBy: "Persistent screen id:")

        for block in blocks {
            // 第一个 block 是 list 末尾的提示文本（在第一个 "Persistent" 之前），跳过
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.contains("Resolution:") else { continue }

            // 把块第一行（ID 本身）拼回来
            let fullBlock = "Persistent screen id:" + block
            if let info = parseBlock(fullBlock) {
                displays.append(info)
            }

            // 检测镜像：原始 id 行若含 "+"（如 "A+B+C"），记录所有两两组合
            if let idLine = value(of: "Persistent screen id:", in: fullBlock)?
                .trimmingCharacters(in: .whitespaces) {
                let ids = idLine.components(separatedBy: "+")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if ids.count >= 2 {
                    // 基准屏是 ids[0]，其余都是被镜像的
                    for other in ids.dropFirst() {
                        mirroredPairs.append((ids[0], other))
                    }
                }
            }
        }
        return displays
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
        let enabled = (value(of: "Enabled:", in: block)?.localizedCaseInsensitiveContains("true")) ?? true

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
            enabled: enabled
        )
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

    /// 判断两块屏当前是否处于镜像状态。
    /// 用最近一次解析时记录的镜像分组集合判定（见 parseList）。
    func isMirroring(_ a: DisplayInfo, _ b: DisplayInfo) -> Bool {
        mirroredPairs.contains { pair in
            (pair.0 == a.id && pair.1 == b.id) ||
            (pair.0 == b.id && pair.1 == a.id)
        }
    }

    /// 取消镜像，恢复为扩展（并排）布局：主屏在左 (0,0)，外接屏在右。
    @discardableResult
    func unmirror(main: DisplayInfo, external: DisplayInfo) -> Bool {
        let mainArg = makeScreenArg(
            id: main.id,
            res: main.resolution,
            hz: main.hertz,
            colorDepth: main.colorDepth,
            scaling: main.scalingOn,
            origin: (0, 0),
            degree: main.degree
        )
        let extArg = makeScreenArg(
            id: external.id,
            res: external.resolution,
            hz: external.hertz,
            colorDepth: external.colorDepth,
            scaling: external.scalingOn,
            origin: (main.resolution.width, 0),
            degree: external.degree
        )
        return runConfig([mainArg, extArg])
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
