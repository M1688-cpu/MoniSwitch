import Foundation

// DDC/CI 协议纯逻辑：包构造、校验和、读回复解析。
// 全部为无副作用纯函数，已知向量见 Tests/MoniSwitchTests/DDCTests.swift。
//
// 协议格式参考（MIT，两处独立实现交叉验证）：
//  - m1ddc（waydabber）sources/i2c.m
//  - MonitorControl Arm64DDC.swift（MonitorControl 项目，MIT）
// DDC/CI 语义：I2C 从机 7 位地址 0x37（即 8 位 0x6E>>1），数据子地址 0x51；
// 写包 = [0x80|len+1, len, feature, hi, lo, checksum]，读请求 = [0x82, 0x01, feature, checksum]；
// 校验和种子：写含 0x51（0x6E^0x51）、读不含（0x6E）；读回复 11 字节，
// [6..7]=max、[8..9]=current（大端），[10]=前 10 字节以 0x50 为种子的 XOR。

/// DDC/CI 常量与纯协议函数。
enum DDC {
    /// IOAVService I2C 调用的芯片地址（7 位形式）。
    static let chipAddressDefault: UInt32 = 0x37
    /// MCDP29xx 芯片（部分 DP 转换器/坞）的非标芯片地址。
    static let chipAddressMCDP29XX: UInt32 = 0xB7
    /// DDC 数据子地址。
    static let dataAddress: UInt32 = 0x51
    /// VCP feature：亮度（luminance）。
    static let featureLuminance: UInt8 = 0x10
    /// 读回复固定 11 字节。
    static let replyLength = 11

    /// 异或校验和：seed 逐字节 XOR。
    static func checksum(seed: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }

    /// 构造 DDC 写包（6 字节）：设置 feature 为指定值。
    static func writePacket(feature: UInt8, value: UInt16) -> [UInt8] {
        var packet: [UInt8] = [0x84, 0x03, feature, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = checksum(seed: 0x6E ^ UInt8(dataAddress), Array(packet[0...4]))
        return packet
    }

    /// 构造 DDC 读请求包（4 字节）：查询 feature 当前值。
    /// 注意读请求的校验和种子不含 0x51（与写包不对称，两处参考实现一致）。
    static func readRequestPacket(feature: UInt8) -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, feature, 0]
        packet[3] = checksum(seed: 0x6E, Array(packet[0...2]))
        return packet
    }

    /// 解析 DDC 读回复（11 字节）。校验和不符 / 长度不足 / 全零回复均返回 nil
    /// （全零是 DDC 读失败的常见形态，天然被校验和拦截）。
    static func parseReadReply(_ reply: [UInt8]) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        guard checksum(seed: 0x50, Array(reply[0...9])) == reply[10] else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, max)
    }

    /// 亮度键单次步进量：max/16 向下取整、至少 1（MonitorControl 默认手感）。
    static func brightnessStep(maxValue: UInt16) -> Int {
        Swift.max(Int(maxValue) / 16, 1)
    }
}
