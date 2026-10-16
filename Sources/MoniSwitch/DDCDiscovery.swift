import Foundation
import IOKit
import CoreGraphics
import AppKit

/// 一块可通过 DDC/CI 控制的物理外接屏。
struct DDCDevice {
    /// CG 屏 ID（会话内稳定；跨插拔/重配可能变化，持久化用 identityKey）。
    let displayID: CGDirectDisplayID
    /// IOAVService（raw 指针，Create 规则持有；替换时经 PrivateAPI.release 释放）。
    let service: PrivateAPI.IOAVServiceRef
    /// I2C 芯片地址（0x37；MCDP29xx 走 0xB7）。
    let chipAddress: UInt32
    /// 注册表 ProductName（如 "DELL U2723QE"），兜底空串由 UI 层本地化。
    let name: String
    /// 持久化身份：优先注册表 EDID UUID（物理唯一），兜底 vendor:model:serial。
    let identityKey: String
    /// 全局显示空间边界（空间排序用）。
    let bounds: CGRect
}

/// 外接屏发现与 CGDirectDisplayID → IOAVService 映射。
///
/// 映射方法抄 m1ddc（MIT, waydabber）的精确绑定（sources/ioregistry.m）：
/// 在线屏列表 → CoreDisplay 私有信息字典取 IODisplayLocation → 注册表按路径
/// 取 adapter 项 → 其 RegistryEntryID → 单趟扫描 IOService 平面，把
/// 「External 位置的 DCPAVServiceProxy」挂到最近一个 IOMobileFramebuffer 项下
/// → RegistryEntryID 对上即绑定。比 MonitorControl 的 EDID 20 分评分法简单且确定。
/// 虚拟屏（Sidecar/AirPlay）没有 IODisplayLocation，自然被排除。
enum DDCDiscovery {
    /// 枚举全部可 DDC 控制的外接屏（按空间位置从左到右排序）。
    static func externalDevices() -> [DDCDevice] {
        var devices: [DDCDevice] = []
        guard let infoDictFn = PrivateAPI.displayCreateInfoDictionary,
              let createWithService = PrivateAPI.ioAVServiceCreateWithService else {
            return devices
        }

        // 第一遍：每块在线屏 → 信息字典 → adapter 注册表项与身份属性
        var adapters: [Adapter] = []
        var online = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &online, &count)
        for displayID in online.prefix(Int(count)) where displayID != 0 {
            guard let raw = infoDictFn(displayID) else { continue }
            let dict = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
            // 缺 UUID / IODisplayLocation 的是虚拟屏（Sidecar、AirPlay 等）
            guard dict["kCGDisplayUUID"] is String,
                  let ioLocation = dict["IODisplayLocation"] as? String else { continue }
            let adapterEntry = IORegistryEntryCopyFromPath(kIOMainPortDefault, ioLocation as CFString)
            guard adapterEntry != 0 else { continue }

            let displayAttrs = registryDictionary(adapterEntry, "DisplayAttributes")
            let productAttrs = displayAttrs?["ProductAttributes"] as? NSDictionary
            let productName = productAttrs?["ProductName"] as? String ?? ""
            let edidUUID = registryString(adapterEntry, "EDID UUID") ?? ""

            let identityKey: String
            if !edidUUID.isEmpty {
                identityKey = "edid:\(edidUUID)"
            } else {
                identityKey = "vms:\(CGDisplayVendorNumber(displayID)):\(CGDisplayModelNumber(displayID)):\(CGDisplaySerialNumber(displayID)):\(productName)"
            }

            adapters.append(Adapter(
                displayID: displayID,
                entry: adapterEntry,
                name: productName,
                identityKey: identityKey,
                bounds: CGDisplayBounds(displayID)
            ))
        }

        // 第二遍：注册表单趟扫描建立 framebuffer → External 代理映射，再按 ID 绑定
        let proxies = externalProxiesByFramebuffer()
        defer { proxies.values.forEach { IOObjectRelease($0.entry) } }
        for adapter in adapters {
            defer { IOObjectRelease(adapter.entry) }
            var adapterID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(adapter.entry, &adapterID) == KERN_SUCCESS,
                  let proxy = proxies[adapterID],
                  let service = createWithService(PrivateAPI.defaultAllocator, proxy.entry) else {
                continue
            }
            devices.append(DDCDevice(
                displayID: adapter.displayID,
                service: service,
                chipAddress: proxy.chipAddress,
                name: adapter.name,
                identityKey: adapter.identityKey,
                bounds: adapter.bounds
            ))
        }

        devices.sort { ($0.bounds.minX, $0.bounds.minY) < ($1.bounds.minX, $1.bounds.minY) }
        return devices
    }

    /// 是否存在内置屏（HUD「智能显示」判断用：有内置屏时 F1/F2 已有系统 OSD）。
    static func hasBuiltInDisplay() -> Bool {
        var online = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &online, &count)
        return online.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    // MARK: - 内部

    private struct Adapter {
        let displayID: CGDirectDisplayID
        let entry: io_registry_entry_t
        let name: String
        let identityKey: String
        let bounds: CGRect
    }

    /// 单趟扫描 IOService 平面：返回 framebuffer RegistryEntryID → 该 framebuffer 下
    /// 第一个 Location == "External" 的 DCPAVServiceProxy（m1ddc 语义：代理挂最近一个
    /// IOMobileFramebuffer 项下）。调用方负责释放返回的 entry。
    private static func externalProxiesByFramebuffer() -> [UInt64: (entry: io_service_t, chipAddress: UInt32)] {
        var result: [UInt64: (entry: io_service_t, chipAddress: UInt32)] = [:]
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return result }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            IOObjectRelease(root)
            return result
        }
        defer {
            IOObjectRelease(iterator)
            IOObjectRelease(root)
        }

        var currentFramebuffer: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            if IOObjectConformsTo(service, "IOMobileFramebuffer") != 0 {
                var framebufferID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &framebufferID) == KERN_SUCCESS {
                    currentFramebuffer = framebufferID
                }
                IOObjectRelease(service)
                continue
            }
            if entryName(service) == "DCPAVServiceProxy",
               currentFramebuffer != 0,
               result[currentFramebuffer] == nil,
               registryString(service, "Location") == "External" {
                let chip = isMCDP29XXProxy(service) ? DDC.chipAddressMCDP29XX : DDC.chipAddressDefault
                result[currentFramebuffer] = (service, chip)
                // entry 的 send right 移交 result，本循环不释放
            } else {
                IOObjectRelease(service)
            }
        }
        return result
    }

    /// MCDP29xx 芯片（部分 DP 转换器/坞）DDC 走非标芯片地址 0xB7：
    /// 判据 = 代理父项的 EPICProviderClass == "AppleDCPMCDP29XX"（m1ddc 同款）。
    private static func isMCDP29XXProxy(_ proxy: io_service_t) -> Bool {
        var parent = io_registry_entry_t()
        guard IORegistryEntryGetParentEntry(proxy, "IOService", &parent) == KERN_SUCCESS, parent != 0 else {
            return false
        }
        defer { IOObjectRelease(parent) }
        return registryString(parent, "EPICProviderClass") == "AppleDCPMCDP29XX"
    }

    /// 读注册表项的字符串属性（递归搜索）。
    private static func registryString(_ entry: io_service_t, _ key: String) -> String? {
        IORegistryEntrySearchCFProperty(entry, "IOService", key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? String
    }

    /// 读注册表项的字典属性（递归搜索）。
    private static func registryDictionary(_ entry: io_service_t, _ key: String) -> NSDictionary? {
        IORegistryEntrySearchCFProperty(entry, "IOService", key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? NSDictionary
    }

    /// 注册表项名（导入签名要 UnsafeMutablePointer<CChar>，直接开缓冲最稳）。
    private static func entryName(_ entry: io_service_t) -> String {
        let name = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        name.initialize(repeating: 0, count: 128)
        defer {
            name.deinitialize(count: 128)
            name.deallocate()
        }
        guard IORegistryEntryGetName(entry, name) == KERN_SUCCESS else { return "" }
        return String(cString: name)
    }
}
