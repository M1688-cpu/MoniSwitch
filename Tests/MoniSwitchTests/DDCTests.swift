// DDC 协议纯逻辑测试。向量全部手算自两处独立参考实现
// （m1ddc sources/i2c.m 与 MonitorControl Arm64DDC.swift，均 MIT），
// 非由实现反推——期望值即协议规格的独立来源。
import Testing
@testable import MoniSwitch

@Suite("DDC 协议纯逻辑")
struct DDCTests {
    // MARK: 写包

    @Test("写包：亮度 0x10 值 100")
    func writePacketLuminance100() {
        #expect(DDC.writePacket(feature: 0x10, value: 100) == [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
    }

    @Test("写包：值 0 与 255 边界")
    func writePacketBounds() {
        #expect(DDC.writePacket(feature: 0x10, value: 0) == [0x84, 0x03, 0x10, 0x00, 0x00, 0xA8])
        #expect(DDC.writePacket(feature: 0x10, value: 255) == [0x84, 0x03, 0x10, 0x00, 0xFF, 0x57])
    }

    @Test("写包：值超 255 时拆高低字节")
    func writePacketSplitsHighByte() {
        #expect(DDC.writePacket(feature: 0x10, value: 256) == [0x84, 0x03, 0x10, 0x01, 0x00, 0xA9])
    }

    // MARK: 读请求包

    @Test("读请求包：亮度 0x10（校验和种子不含 0x51）")
    func readRequestPacketLuminance() {
        #expect(DDC.readRequestPacket(feature: 0x10) == [0x82, 0x01, 0x10, 0xFD])
    }

    // MARK: 读回复解析

    /// 构造合法回复：max=100（[6..7]=00 64）、current=50（[8..9]=00 32）、
    /// 末字节 = 0x50 ^ 前 10 字节 = 0xFC（手算）。
    static let validReply: [UInt8] = [0x6E, 0x02, 0x84, 0x02, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xFC]

    @Test("读回复：合法回复解析出 current/max")
    func parseValidReply() {
        let parsed = DDC.parseReadReply(Self.validReply)
        #expect(parsed?.current == 50)
        #expect(parsed?.max == 100)
    }

    @Test("读回复：校验和错误返回 nil")
    func parseBadChecksum() {
        var corrupted = Self.validReply
        corrupted[9] = 0x33
        #expect(DDC.parseReadReply(corrupted) == nil)
    }

    @Test("读回复：长度不足返回 nil")
    func parseShortReply() {
        #expect(DDC.parseReadReply(Array(Self.validReply[0...9])) == nil)
    }

    @Test("读回复：全零回复（常见失败形态）返回 nil")
    func parseZeroReply() {
        #expect(DDC.parseReadReply([UInt8](repeating: 0, count: DDC.replyLength)) == nil)
    }

    // MARK: 步进

    @Test("亮度步进：max/16 向下取整、至少 1")
    func brightnessStepValues() {
        #expect(DDC.brightnessStep(maxValue: 100) == 6)
        #expect(DDC.brightnessStep(maxValue: 255) == 15)
        #expect(DDC.brightnessStep(maxValue: 16) == 1)
        #expect(DDC.brightnessStep(maxValue: 10) == 1)
        #expect(DDC.brightnessStep(maxValue: 32) == 2)
    }
}
