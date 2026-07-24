import Foundation
import SwiftUI
import ServiceManagement
import UserNotifications

/// 操作类型，用于发送切换完成通知时选择正文文案。
enum OpKind {
    case primary       // 切换主屏
    case mirror        // 镜像主屏
    case extend        // 扩展显示（取消镜像）
    case moveLeft      // 移到主屏左侧
    case moveRight     // 移到主屏右侧
}

/// 全局用户偏好（单例 + @Published + UserDefaults 持久化）。
///
/// 与 `L10n` 分离：L10n 只管语言，AppSettings 只管行为偏好。
/// 所有 @Published 的 didSet 都同步写入 UserDefaults，下次启动自动恢复。
/// 设置窗口打开时调一次 `syncLaunchAtLoginStatus()`，避免用户在"系统设置 > 登录项"
/// 里手动改动后导致开关与真实状态不同步。
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - UserDefaults keys

    private enum Key {
        static let launchAtLogin      = "launchAtLogin"
        static let autoRefreshEnabled = "autoRefreshEnabled"
        static let autoRefreshInterval = "autoRefreshInterval"
        static let detailedMenuInfo   = "detailedMenuInfo"
        static let notificationsEnabled = "notificationsEnabled"
    }

    /// 可选的自动刷新间隔（秒）。Picker 直接遍历它。
    static let refreshIntervalOptions = [5, 10, 30]

    // MARK: - Published 偏好

    /// 登录时启动 MoniSwitch（SMAppService.mainApp）。
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            // isApplying=true 表示这是副作用失败后的程序化回滚，跳过再次 apply。
            guard !isApplying else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// 自动刷新显示器列表（外接屏热插拔时菜单自动更新）。
    @Published var autoRefreshEnabled: Bool {
        didSet {
            guard oldValue != autoRefreshEnabled else { return }
            UserDefaults.standard.set(autoRefreshEnabled, forKey: Key.autoRefreshEnabled)
        }
    }

    /// 自动刷新的轮询间隔（秒）。
    @Published var autoRefreshInterval: Int {
        didSet {
            guard oldValue != autoRefreshInterval else { return }
            UserDefaults.standard.set(autoRefreshInterval, forKey: Key.autoRefreshInterval)
        }
    }

    /// 菜单项里显示刷新率与 HiDPI 状态。
    @Published var detailedMenuInfo: Bool {
        didSet {
            guard oldValue != detailedMenuInfo else { return }
            UserDefaults.standard.set(detailedMenuInfo, forKey: Key.detailedMenuInfo)
        }
    }

    /// 切换显示器后发送系统通知。
    @Published var notificationsEnabled: Bool {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            UserDefaults.standard.set(notificationsEnabled, forKey: Key.notificationsEnabled)
            // 仅在用户打开时请求授权；程序化回滚（isApplying）不再触发。
            guard !isApplying, notificationsEnabled else { return }
            Task { await ensureNotificationAuthorization() }
        }
    }

    /// 防止副作用（SMAppService/通知授权）失败回滚设值时再次触发 didSet 里的副作用。
    private var isApplying = false

    // MARK: - 初始化

    private init() {
        let defaults = UserDefaults.standard
        self.launchAtLogin       = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        self.autoRefreshEnabled  = defaults.object(forKey: Key.autoRefreshEnabled) as? Bool ?? false
        self.autoRefreshInterval = defaults.object(forKey: Key.autoRefreshInterval) as? Int ?? 10
        self.detailedMenuInfo    = defaults.object(forKey: Key.detailedMenuInfo) as? Bool ?? false
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false
    }

    // MARK: - 开机自启动

    /// 设置窗口打开时调用：把 launchAtLogin 与 SMAppService 的真实状态对齐。
    /// 用户可能在"系统设置 > 通用 > 登录项"里手动移除了本 App，这里读真实状态回填开关。
    func syncLaunchAtLoginStatus() {
        let real = (SMAppService.mainApp.status == .enabled)
        if real != launchAtLogin {
            // 用 isApplying 包起来：同步是程序化更新，不应再触发 register/unregister。
            isApplying = true
            launchAtLogin = real
            isApplying = false
        }
    }

    /// 实际注册/注销 SMAppService；失败时静默回滚开关，不弹错误对话框。
    private func applyLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册/注销失败（debug 未签名、被 MDM 禁用等）：回滚开关，避免 UI 误导。
            // 用 isApplying=true 标记此次为程序化回滚，阻止 didSet 再次 apply。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isApplying = true
                self.launchAtLogin = !on
                self.isApplying = false
            }
        }
    }

    // MARK: - 通知

    /// 打开通知开关时请求系统授权；若用户拒绝则回滚开关。
    /// 返回是否成功授权（调用方一般无需处理返回值，失败已在内部回滚）。
    @discardableResult
    func ensureNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }

        do {
            let granted = try await center.requestAuthorization(options: [.alert])
            if !granted {
                // 用户拒绝：用 isApplying 标记程序化回滚，阻止 didSet 再次请求。
                await MainActor.run {
                    self.isApplying = true
                    self.notificationsEnabled = false
                    self.isApplying = false
                }
            }
            return granted
        } catch {
            await MainActor.run {
                self.isApplying = true
                self.notificationsEnabled = false
                self.isApplying = false
            }
            return false
        }
    }

    /// 发送一条切换完成通知。若用户未开启则直接忽略。
    /// - Parameter kind: 操作类型，决定通知正文文案。
    func sendSwitchNotification(_ kind: OpKind) {
        guard notificationsEnabled else { return }
        let l10n = L10n.shared
        let body: String
        switch kind {
        case .primary:    body = l10n.t(.notifPrimary)
        case .mirror:     body = l10n.t(.notifMirror)
        case .extend:     body = l10n.t(.notifExtend)
        case .moveLeft:   body = l10n.t(.notifMoveLeft)
        case .moveRight:  body = l10n.t(.notifMoveRight)
        }

        let content = UNMutableNotificationContent()
        content.title = "MoniSwitch"
        content.body = body
        content.sound = nil   // 切换通知不打扰，静默即可

        let request = UNNotificationRequest(
            identifier: "moniswitch.switch.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
