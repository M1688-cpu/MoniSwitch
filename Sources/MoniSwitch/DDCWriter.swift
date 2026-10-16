import Foundation
import IOKit
import CoreGraphics

/// DDC I/O 执行器：串行化全部 DDC 读写 + 写合并（拖滑条/按键重复风暴只发最后一次值）
/// + service 生命周期守卫 + 睡眠守卫。
///
/// 工程细节抄 MonitorControl 实战经验（MIT）：
/// - 每次写前 sleep 10ms（DDC 总线节流），失败重试；
/// - 全局串行访问 DDC（本 actor 即串行点），绝不并发轰同一显示器；
/// - 读尽力而为：写可靠、读不可靠是 DDC 的普遍形态，读只用于「面板打开时
///   同步一次真实值」，失败静默容忍。
///
/// service 生命周期守卫（2026-10 code-review 修复）：BrightnessManager 刷新屏
/// 配置会替换/释放旧 IOAVService；本执行器在途或迟到的写请求可能仍持旧指针。
/// 防线：写前校验 `liveServices`（manager 每轮刷新后声明存活集）+ 刷新方先
/// `waitForIdle()` 排空在途泵再释放——两道防线保证已释放的 service 永不被解引用。
actor DDCWriter {
    static let shared = DDCWriter()

    private struct PendingWrite {
        let service: PrivateAPI.IOAVServiceRef
        let chipAddress: UInt32
        let value: UInt16
    }

    /// displayID → 最新待写值（中间值在合并窗内被覆盖丢弃）。
    private var pending: [CGDirectDisplayID: PendingWrite] = [:]
    /// 正在跑泵的屏（泵结束移除；移除后再入队会重新 kick，无丢失）。
    private var running: Set<CGDirectDisplayID> = []
    /// 存活 service 指针集（BrightnessManager 每轮刷新后声明）；写前校验。
    private var liveServices: Set<UnsafeRawPointer> = []
    /// 睡眠守卫：系统睡眠期间挂起 DDC 写（屏睡眠时 I2C 总线常无响应），
    /// 唤醒后恢复并补发积压。
    private var suspended = false
    /// 合并窗：吸收连续事件的间隔（await 让出 actor，期间新值可入 pending）。
    private static let coalesceWindow: UInt64 = 20_000_000
    private static let writeAttempts = 3
    private static let preWriteWait: useconds_t = 10_000

    /// 设置某屏亮度（原始值 0...max）。立即返回；实际写按合并策略串行执行。
    func setBrightness(displayID: CGDirectDisplayID, service: PrivateAPI.IOAVServiceRef, chipAddress: UInt32, value: UInt16) {
        guard !suspended else { return }
        pending[displayID] = PendingWrite(service: service, chipAddress: chipAddress, value: value)
        kickIfNeeded(displayID)
    }

    /// 声明当前存活的 service 集（BrightnessManager 刷新完成后调用）：
    /// 立即丢弃已退役屏的待写；迟到的写请求由写前校验兜底。
    func updateLiveServices(_ services: Set<UnsafeRawPointer>) {
        liveServices = services
        pending = pending.filter { liveServices.contains(UnsafeRawPointer($0.value.service)) }
    }

    /// 等待全部在途泵排空（刷新方释放旧 service 前调用；泵最长 ~50ms）。
    func waitForIdle() async {
        while !running.isEmpty {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// 睡眠/唤醒守卫（NSWorkspace 睡眠通知转发；唤醒后补发积压）。
    func setSuspended(_ flag: Bool) {
        suspended = flag
        if !flag {
            // 补发睡眠期间被吞的待写（若有）
            for displayID in pending.keys {
                kickIfNeeded(displayID)
            }
        }
    }

    /// 尽力而为读某屏当前亮度：成功返回 (current, max)，失败返回 nil。
    func readBrightness(service: PrivateAPI.IOAVServiceRef, chipAddress: UInt32) -> (current: UInt16, max: UInt16)? {
        guard !suspended, let write = PrivateAPI.ioAVServiceWriteI2C, let read = PrivateAPI.ioAVServiceReadI2C else {
            return nil
        }
        let request = DDC.readRequestPacket(feature: DDC.featureLuminance)
        let readWait: useconds_t = chipAddress == DDC.chipAddressMCDP29XX ? 50_000 : 10_000
        for _ in 0..<2 {
            var req = request
            var reply = [UInt8](repeating: 0, count: DDC.replyLength)
            let reqLength = req.count
            let replyLength = reply.count
            let wrote: Bool = req.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return false }
                usleep(Self.preWriteWait)
                return write(service, chipAddress, DDC.dataAddress, base, UInt32(reqLength)) == KERN_SUCCESS
            }
            guard wrote else { continue }
            var parsed: (current: UInt16, max: UInt16)?
            reply.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                usleep(readWait)
                guard read(service, chipAddress, DDC.dataAddress, base, UInt32(replyLength)) == KERN_SUCCESS else { return }
                let bytes = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: replyLength)
                parsed = DDC.parseReadReply(Array(bytes))
            }
            if let parsed { return parsed }
        }
        return nil
    }

    // MARK: - 内部

    private func kickIfNeeded(_ displayID: CGDirectDisplayID) {
        guard !running.contains(displayID) else { return }
        running.insert(displayID)
        Task { await self.pump(displayID) }
    }

    private func pump(_ displayID: CGDirectDisplayID) async {
        // 合并窗：await 让出 actor，窗内到达的连续 set 只保留最后一次值
        try? await Task.sleep(nanoseconds: Self.coalesceWindow)
        while let next = pending[displayID] {
            pending[displayID] = nil
            // 写前校验存活集：迟到的旧 service 请求在此被丢弃（防 use-after-release）
            if liveServices.isEmpty || liveServices.contains(UnsafeRawPointer(next.service)) {
                writeLuminance(service: next.service, chipAddress: next.chipAddress, value: next.value)
            }
        }
        running.remove(displayID)
        // 竞态注记：running 移除后新入队的 set 会重新 kick pump，无丢失；
        // pump 运行中阻塞写期间到达的 set 会在 mailbox 排队，随后同样被消费。
    }

    /// 带重试的 DDC 写（阻塞本 actor 专属线程——串行 DDC I/O 即设计意图）。
    @discardableResult
    private func writeLuminance(service: PrivateAPI.IOAVServiceRef, chipAddress: UInt32, value: UInt16) -> Bool {
        guard let write = PrivateAPI.ioAVServiceWriteI2C else { return false }
        var packet = DDC.writePacket(feature: DDC.featureLuminance, value: value)
        let packetLength = packet.count
        return packet.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return false }
            for _ in 0..<Self.writeAttempts {
                usleep(Self.preWriteWait)
                if write(service, chipAddress, DDC.dataAddress, base, UInt32(packetLength)) == KERN_SUCCESS {
                    return true
                }
            }
            return false
        }
    }
}
