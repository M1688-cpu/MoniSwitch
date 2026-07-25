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
    case testBuildLabel         = "testBuildLabel"         // 测试版本

    // 设置 - 启动
    case groupStartup           = "groupStartup"           // 启动
    case launchAtLogin          = "launchAtLogin"          // 登录时启动 MoniSwitch

    // 设置 - 显示器
    case groupDisplays          = "groupDisplays"          // 显示器
    case autoRefresh            = "autoRefresh"            // 自动刷新显示器列表
    case refreshInterval        = "refreshInterval"        // 刷新间隔
    case intervalSeconds        = "intervalSeconds"        // N 秒
    case detailedMenuInfo       = "detailedMenuInfo"       // 菜单显示刷新率与 HiDPI

    // 设置 - 通知
    case groupNotifications     = "groupNotifications"     // 通知
    case notifyOnSwitch         = "notifyOnSwitch"         // 切换完成后发送通知

    // 通知正文（按操作类型）
    case notifPrimary           = "notifPrimary"           // 已切换主屏
    case notifMirror            = "notifMirror"            // 已镜像主屏
    case notifExtend            = "notifExtend"            // 已切换为扩展显示
    case notifMoveLeft          = "notifMoveLeft"          // 已移到主屏左侧
    case notifMoveRight         = "notifMoveRight"         // 已移到主屏右侧
    case notifPresetApplied     = "notifPresetApplied"     // 已应用预设
    case notifRefreshRate       = "notifRefreshRate"       // 已切换刷新率

    // 设置 - 预设
    case tabPresets             = "tabPresets"             // 预设
    case groupPresets           = "groupPresets"           // 预设
    case presetCaptureHint      = "presetCaptureHint"      // 保存当前显示器布局为预设
    case presetNamePlaceholder  = "presetNamePlaceholder"  // 预设名称
    case presetCaptureButton    = "presetCaptureButton"    // 保存预设
    case presetApplyButton      = "presetApplyButton"      // 应用
    case presetDeleteButton     = "presetDeleteButton"     // 删除
    case presetEmptyHint        = "presetEmptyHint"        // 还没有保存任何预设
    case presetApplyConfirm     = "presetApplyConfirm"     // 应用此预设？

    // 菜单 - 刷新率子菜单

    // 菜单 - 刷新率子菜单
    case refreshRateMenu        = "refreshRateMenu"        // 刷新率
    case hertzLabel             = "hertzLabel"             // Hz
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

    /// 取文案并用一个整数替换其中的 %d 占位符（如"N 秒"）。
    func t(_ key: TextKey, _ value: Int) -> String {
        let raw = (table[key]?[lang]) ?? key.rawValue
        return raw.replacingOccurrences(of: "%d", with: "\(value)")
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
        .testBuildLabel:   [.zh: "测试版本",                      .en: "Test Build"],

        .groupStartup:     [.zh: "启动",                          .en: "Startup"],
        .launchAtLogin:    [.zh: "登录时启动 MoniSwitch",         .en: "Launch MoniSwitch at login"],

        .groupDisplays:    [.zh: "显示器",                        .en: "Displays"],
        .autoRefresh:      [.zh: "自动刷新显示器列表",            .en: "Auto-refresh display list"],
        .refreshInterval:  [.zh: "刷新间隔",                      .en: "Refresh interval"],
        .intervalSeconds:  [.zh: "%d 秒",                         .en: "Every %ds"],
        .detailedMenuInfo: [.zh: "菜单显示刷新率与 HiDPI",        .en: "Show refresh rate & HiDPI in menu"],

        .groupNotifications:[.zh: "通知",                         .en: "Notifications"],
        .notifyOnSwitch:   [.zh: "切换完成后发送通知",            .en: "Notify after switching"],

        .notifPrimary:     [.zh: "已切换主屏",                    .en: "Primary display switched"],
        .notifMirror:      [.zh: "已镜像主屏",                    .en: "Mirrored to main display"],
        .notifExtend:      [.zh: "已切换为扩展显示",              .en: "Switched to extended display"],
        .notifMoveLeft:    [.zh: "已移到主屏左侧",                .en: "Moved to the left of main"],
        .notifMoveRight:   [.zh: "已移到主屏右侧",                .en: "Moved to the right of main"],
        .notifPresetApplied:[.zh: "已应用预设",                   .en: "Preset applied"],
        .notifRefreshRate:  [.zh: "已切换刷新率",                 .en: "Refresh rate changed"],

        .tabPresets:       [.zh: "预设",                          .en: "Presets"],
        .groupPresets:     [.zh: "预设",                          .en: "Presets"],
        .presetCaptureHint:[.zh: "保存当前显示器布局为预设",      .en: "Save current display layout as a preset"],
        .presetNamePlaceholder:[.zh: "预设名称",                  .en: "Preset name"],
        .presetCaptureButton:[.zh: "保存预设",                    .en: "Save Preset"],
        .presetApplyButton:[.zh: "应用",                          .en: "Apply"],
        .presetDeleteButton:[.zh: "删除",                         .en: "Delete"],
        .presetEmptyHint:  [.zh: "还没有保存任何预设",            .en: "No presets saved yet"],
        .presetApplyConfirm:[.zh: "应用此预设？",                 .en: "Apply this preset?"],

        .refreshRateMenu:  [.zh: "刷新率",                        .en: "Refresh Rate"],
        .hertzLabel:       [.zh: "Hz",                            .en: "Hz"],
    ]
}
