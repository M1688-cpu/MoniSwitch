import Foundation
import IOKit
import CoreGraphics

/// DDC I/O 执行器：串行化全部 DDC 读写 + 写合并（拖滑条/按键重复风暴只发最后一次值）。
///
/// 工程细节抄 MonitorControl 实战经验（MIT）：
/// - 每次写前 sleep 10ms（DDC 总线节流），失败重试；
/// - 全局串行访问 DDC（本 actor 即串行点），绝不并发轰同一显示器；
/// - 读尽力而为：写可靠、读不可靠是 DDC 的普遍形态，读只用于「面板打开时
///   同步一次真实值」，失败静默容忍。
actor DDCWriter {
    static let shared = DDCWriter()

    private struct PendingWrite {
        let service: PrivateAPI.IOAVServiceRef
        let chipAddress: UInt32
        let value: UInt16
    }

    /// displayID → 最新待写值（中间值在合并窗内被覆盖丢弃）。
    private var pending: [CGDirectDisplayID: PendingWrite] = [:]
    private var running: Set<CGDirectDisplayID> = []
    /// 合并窗：吸收连续事件的间隔（await 让出 actor，期间新值可入 pending）。
    private static let coalesceWindow: UInt64 = 20_000_000
    private static let writeAttempts = 3
    private static let preWriteWait: useconds_t = 10_000

    /// 设置某屏亮度（原始值 0...max）。立即返回；实际写按合并策略串行执行。
    func setBrightness(displayID: CGDirectDisplayID, service: PrivateAPI.IOAVServiceRef, chipAddress: UInt32, value: UInt16) {
        pending[displayID] = PendingWrite(service: service, chipAddress: chipAddress, value: value)
        guard !running.contains(displayID) else { return }
        running.insert(displayID)
        Task { await self.pump(displayID) }
    }

    /// 尽力而为读某屏当前亮度：成功返回 (current, max)，失败返回 nil。
    func readBrightness(service: PrivateAPI.IOAVServiceRef, chipAddress: UInt32) -> (current: UInt16, max: UInt16)? {
        guard let write = PrivateAPI.ioAVServiceWriteI2C, let read = PrivateAPI.ioAVServiceReadI2C else {
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

    private func pump(_ displayID: CGDirectDisplayID) async {
        // 合并窗：await 让出 actor，窗内到达的连续 set 只保留最后一次值
        try? await Task.sleep(nanoseconds: Self.coalesceWindow)
        while let next = pending[displayID] {
            pending[displayID] = nil
            writeLuminance(service: next.service, chipAddress: next.chipAddress, value: next.value)
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
