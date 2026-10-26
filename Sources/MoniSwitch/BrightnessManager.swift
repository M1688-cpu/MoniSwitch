import Foundation
import Observation
import CoreGraphics
import AppKit

/// 亮度状态中枢：外接屏发现、每屏亮度值（0...1）、持久化、F1/F2 步进调节。
///
/// 值策略（DDC「写可靠读不可靠」的对策）：
/// - 面板打开/屏配置变化时发现一次 + 尽力读一次真实值（失败容忍）；
/// - 读失败 → 上次持久化百分比 → 兜底 50%；max 单独走「合法读 → 上次成功
///   读到的 max → 100」，绝不退化成 1（否则单步 = 100%，F1 一按即最暗）；
/// - 屏睡眠/暗唤醒时不读（I2C 常无响应），只沿用缓存；
/// - 所有调节（滑条/按键）本地乐观更新 + 异步合并写，按 identityKey 持久化
///   （EDID UUID 身份，免疫 CG 屏 ID 跨插拔漂移——与预设漂移重映射同理）。
@MainActor
@Observable
final class BrightnessManager {
    static let shared = BrightnessManager()

    /// 一块外接屏在面板里的展示条目。
    struct Entry: Identifiable {
        let id: CGDirectDisplayID
        let identityKey: String
        /// 注册表 ProductName；空串时 UI 层用本地化「外接显示器」。
        let name: String
        let chipAddress: UInt32
        let service: PrivateAPI.IOAVServiceRef
        var maxValue: UInt16
        var percent: Double

        /// 当前 DDC 原始值。
        var rawValue: UInt16 {
            BrightnessValue.rawValue(percent: percent, maxValue: maxValue)
        }
    }

    /// 全部外接屏条目（空间从左到右）。空 = 无可调外接屏（单内置屏等场景）。
    private(set) var entries: [Entry] = []

    private let persistenceKey = "moniswitch.brightness.byIdentity"
    private var persisted: [String: Double] {
        didSet { UserDefaults.standard.set(persisted, forKey: persistenceKey) }
    }
    /// 每块屏上次成功读到的 DDC max（身份键）。读失败时绝不再退化成 1，
    /// 否则单步 = 100%，F1 会直接写到最暗、F2 写回的 1 仍是同一档。
    private static let maxPersistenceKey = "moniswitch.brightnessMax.byIdentity"
    private var persistedMax: [String: Int] {
        didSet { UserDefaults.standard.set(persistedMax, forKey: Self.maxPersistenceKey) }
    }

    /// 单例与 App 同生命周期（不 deinit、不移除观察者）。
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        persisted = UserDefaults.standard.dictionary(forKey: persistenceKey) as? [String: Double] ?? [:]
        let storedMax = UserDefaults.standard.dictionary(forKey: Self.maxPersistenceKey) ?? [:]
        persistedMax = storedMax.compactMapValues { ($0 as? NSNumber)?.intValue }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // 睡眠守卫：睡眠期间挂起 DDC 写（I2C 总线常无响应），唤醒后恢复并刷新
        // （外接屏可能重配 / persistent id 可能漂移，顺带同步新 service 绑定）
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        sleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await DDCWriter.shared.setSuspended(true) }
        }
        wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 不捕获 self（Sendable 闭包约束下直接引用单例，保持零警告基线）
            Task {
                await DDCWriter.shared.setSuspended(false)
                await MainActor.run {
                    BrightnessManager.shared.refresh()
                }
            }
        }
        refresh()
    }

    /// 重新发现外接屏并同步真实亮度值（面板打开时调用；屏配置变化自动触发）。
    func refresh() {
        Task {
            let devices = await Task.detached(priority: .utility) {
                DDCDiscovery.externalDevices()
            }.value

            var newEntries: [Entry] = []
            for device in devices {
                // 屏睡眠/暗唤醒时 DDC 总线常无响应：不读，沿用上次成功值与持久化
                // 百分比（读失败本身无害，害的是把 max 兜底成 1）。
                let read: (current: UInt16, max: UInt16)?
                if CGDisplayIsAsleep(device.displayID) != 0 {
                    read = nil
                } else {
                    read = await DDCWriter.shared.readBrightness(service: device.service, chipAddress: device.chipAddress)
                }
                let cachedMax = persistedMax[device.identityKey].flatMap { UInt16(exactly: $0) }
                let maxValue = BrightnessValue.resolvedMax(readMax: read?.max, cachedMax: cachedMax)
                let percent = BrightnessValue.resolvedPercent(
                    readCurrent: read?.current,
                    readMax: read?.max,
                    savedPercent: persisted[device.identityKey]
                )
                if let read, read.max >= BrightnessValue.minimumValidMaxValue {
                    persistedMax[device.identityKey] = Int(read.max)
                }
                newEntries.append(Entry(
                    id: device.displayID,
                    identityKey: device.identityKey,
                    name: device.name,
                    chipAddress: device.chipAddress,
                    service: device.service,
                    maxValue: maxValue,
                    percent: min(max(percent, 0), 1)
                ))
            }

            // service 生命周期守卫（2026-10 code-review 修复）：先声明存活集 +
            // 排空 DDCWriter 在途写（防 use-after-release），随后才释放被替换的旧 service
            let newServices = Set(newEntries.map { UnsafeRawPointer($0.service) })
            await DDCWriter.shared.updateLiveServices(newServices)
            await DDCWriter.shared.waitForIdle()
            for old in entries where !newServices.contains(UnsafeRawPointer(old.service)) {
                PrivateAPI.release(old.service)
            }
            entries = newEntries
            // 事件 tap 的「要不要吞事件」判定跑在 tap 专属队列，不能读 MainActor
            // 状态；这里把可控制屏集合同步进线程安全快照（无外接屏 = 空集）。
            BrightnessControlRegistry.shared.update(Set(newEntries.map(\.id)))
        }
    }

    /// 滑条调节：本地乐观更新 + 异步合并写 + 按身份持久化。
    func setPercent(_ percent: Double, for id: CGDirectDisplayID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(percent, 0), 1)
        entries[index].percent = clamped
        persisted[entries[index].identityKey] = clamped
        let entry = entries[index]
        Task {
            await DDCWriter.shared.setBrightness(
                displayID: entry.id,
                service: entry.service,
                chipAddress: entry.chipAddress,
                value: entry.rawValue
            )
        }
    }

    /// 裸按 F1/F2：只调「鼠标所在屏」（按 displayID 精确瞄准）。
    /// 返回该屏新百分比供 HUD 显示；该屏已不在可调列表（刷新竞态）返回 nil。
    @discardableResult
    func adjustBrightness(up: Bool, for displayID: CGDirectDisplayID) -> Double? {
        guard let index = entries.firstIndex(where: { $0.id == displayID }) else { return nil }
        let entry = entries[index]
        let target = BrightnessValue.adjusted(percent: entry.percent, up: up, maxValue: entry.maxValue)
        setPercent(target, for: displayID)
        return target
    }

    /// ⌥+F1/F2：同步调节全部外接屏（MonitorControl 手感：各屏按同一步长整体移动）。
    /// 返回代表屏（空间最左）的新百分比供 HUD 显示；无可调外接屏返回 nil。
    @discardableResult
    func adjustAllExternal(up: Bool) -> Double? {
        guard !entries.isEmpty else { return nil }
        var representative: Double?
        for entry in entries {
            let target = BrightnessValue.adjusted(percent: entry.percent, up: up, maxValue: entry.maxValue)
            setPercent(target, for: entry.id)
            if representative == nil {
                representative = target
            }
        }
        return representative
    }
}
