import Foundation
import SwiftUI

/// 支持的语言。
enum Language: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }

    /// 菜单里显示的语言名称（用各自语言书写，方便辨认）。
    var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 所有需要翻译的文案 key。
enum TextKey: String {
    // 菜单
    case displaysSection        = "displaysSection"        // 主显示器（点击切换）
    case noDisplays             = "noDisplays"             // 未检测到显示器
    case externalSection        = "externalSection"        // 扩展显示器
    case moveLeft               = "moveLeft"               // 移到主屏左侧
    case moveRight              = "moveRight"              // 移到主屏右侧
    case mirrorMain             = "mirrorMain"             // 镜像主屏
    case extendDisplay          = "extendDisplay"          // 扩展显示（取消镜像）
    case refreshList            = "refreshList"            // 刷新列表
    case settings               = "settings"               // 设置…
    case quit                   = "quit"                   // 退出 MoniSwitch

    // 显示器名称
    case builtInDisplay         = "builtInDisplay"         // MacBook 内置屏
    case externalDisplay        = "externalDisplay"        // 扩展显示器 / 副显示器
    case inch                   = "inch"                   // 英寸 / -inch

    // 设置窗口
    case settingsTitle          = "settingsTitle"          // 设置
    case tabGeneral             = "tabGeneral"             // 通用
    case tabAbout               = "tabAbout"               // 关于
    case groupLanguage          = "groupLanguage"          // 语言
    case languageLabel          = "languageLabel"          // 界面语言
    case appDescription         = "appDescription"         // 一句话简介
    case versionLabel           = "versionLabel"           // 版本
}

/// 轻量国际化中心：持有当前语言（@Published），切换时所有 UI 自动刷新。
/// 语言持久化到 UserDefaults，下次启动自动恢复。
final class L10n: ObservableObject {

    static let shared = L10n()

    @Published var lang: Language {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? Language.zh.rawValue
        lang = Language(rawValue: raw) ?? .zh
    }

    /// 取某条文案的当前语言版本。
    func t(_ key: TextKey) -> String {
        (table[key]?[lang]) ?? key.rawValue
    }

    /// 翻译表。
    private let table: [TextKey: [Language: String]] = [
        .displaysSection:  [.zh: "主显示器（点击切换）",          .en: "Primary display (click to switch)"],
        .noDisplays:       [.zh: "未检测到显示器",                .en: "No displays detected"],
        .externalSection:  [.zh: "扩展显示器",                    .en: "Extended displays"],
        .moveLeft:         [.zh: "移到主屏左侧",                  .en: "Move to left of main"],
        .moveRight:        [.zh: "移到主屏右侧",                  .en: "Move to right of main"],
        .mirrorMain:       [.zh: "镜像主屏",                      .en: "Mirror main display"],
        .extendDisplay:    [.zh: "扩展显示（取消镜像）",          .en: "Extend display (stop mirroring)"],
        .refreshList:      [.zh: "刷新列表",                      .en: "Refresh list"],
        .settings:         [.zh: "设置…",                         .en: "Settings…"],
        .quit:             [.zh: "退出 MoniSwitch",               .en: "Quit MoniSwitch"],

        .builtInDisplay:   [.zh: "MacBook 内置屏",                .en: "MacBook built-in display"],
        .externalDisplay:  [.zh: "扩展显示器",                    .en: " extended display"],
        .inch:             [.zh: "英寸",                          .en: "-inch"],

        .settingsTitle:    [.zh: "设置",                          .en: "Settings"],
        .tabGeneral:       [.zh: "通用",                          .en: "General"],
        .tabAbout:         [.zh: "关于",                          .en: "About"],
        .groupLanguage:    [.zh: "语言",                          .en: "Language"],
        .languageLabel:    [.zh: "界面语言",                      .en: "Interface language"],
        .appDescription:   [.zh: "菜单栏里的显示器快捷切换小工具", .en: "A menu bar tool to switch displays quickly"],
        .versionLabel:     [.zh: "版本",                          .en: "Version"],
    ]
}
