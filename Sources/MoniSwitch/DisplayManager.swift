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

        // 用 "Persistent screen id:" 切分成多个屏块
        let blocks = text.components(separatedBy: "Persistent screen id:")

        for block in blocks {
            // 第一个 block 是 list 末尾的提示文本（在第一个 "Persistent" 之前），跳过
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(trimmed.first.map(String.init) ?? "") ,
                  !trimmed.isEmpty,
                  trimmed.contains("Resolution:") else { continue }

            // 把块第一行（ID 本身）拼回来
            let fullBlock = "Persistent screen id:" + block
            if let info = parseBlock(fullBlock) {
                displays.append(info)
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
    /// - Parameter side: .left 或 .right
    @discardableResult
    func moveExternal(_ external: DisplayInfo,
                      side: HorizontalSide,
                      in displays: [DisplayInfo]) -> Bool {
        guard let main = displays.first(where: { $0.isMain }) else { return false }

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

    /// 镜像：把 external 镜像到 main（id:main+external）。
    /// 镜像时无法独立设分辨率，采用主屏分辨率。
    @discardableResult
    func mirror(_ external: DisplayInfo, to main: DisplayInfo) -> Bool {
        let arg = "id:\(main.id)+\(external.id) " +
                  "res:\(main.resolution.width)x\(main.resolution.height) " +
                  "scaling:\(main.scalingOn ? "on" : "off") " +
                  "origin:(0,0) degree:0"
        return runConfig([arg])
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
