// DDC 常量锁定：这些值散布在显示器生态里（不是我们发明的），一旦漂移全部
// 亮度控制静默失效——锁定到参考实现的文档值（m1ddc ioregistry.h / IOKit
// ev_keymap.h），改这里必须带出处。
import Testing
@testable import MoniSwitch

@Suite struct SmokeTests {
    @Test("DDC 芯片地址与特征码（m1ddc ioregistry.h）")
    func ddcConstants() {
        #expect(DDC.chipAddressDefault == 0x37)
        #expect(DDC.chipAddressMCDP29XX == 0xB7)
        #expect(DDC.dataAddress == 0x51)
        #expect(DDC.featureLuminance == 0x10)
        #expect(DDC.replyLength == 11)
    }
}
