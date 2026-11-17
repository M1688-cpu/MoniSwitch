import Foundation

/// 面板目标与几何的纯逻辑；选择目标不代表修改主显示器。
enum PanelDisplayContext {
    static func selectedID(preferred: String?, in displays: [DisplayInfo]) -> String? {
        if let preferred, displays.contains(where: { $0.id == preferred }) { return preferred }
        return displays.first(where: \.isMain)?.id ?? displays.first?.id
    }

    static func name(for display: DisplayInfo, in displays: [DisplayInfo], baseName: String) -> String {
        let peers = displays.filter { $0.typeName == display.typeName }.map(\.id).sorted()
        guard peers.count > 1, let index = peers.firstIndex(of: display.id) else { return baseName }
        return "\(baseName) (\(index + 1))"
    }

    /// DisplayInfo 的 Equatable 只比较 id；菜单必须另外检查所有配置字段。
    static func configurationID(_ displays: [DisplayInfo]) -> String {
        displays.map { d in
            "\(d.id)|\(d.typeName)|\(d.resolution)|\(d.origin)|\(d.isMain)|\(d.scalingOn)|\(d.hertz)|\(d.colorDepth)|\(d.degree)"
        }.sorted().joined(separator: ";")
    }

    static func viewportHeight(content: CGFloat, available: CGFloat) -> CGFloat {
        max(1, min(content, available))
    }
}
