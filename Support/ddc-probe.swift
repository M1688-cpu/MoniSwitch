// DDC 探针（v2 验收/诊断工具，独立于 App 运行）：
//   swiftc -O Support/ddc-probe.swift -o /tmp/ddc-probe
//   /tmp/ddc-probe get          # 读第一块外接屏当前亮度（尽力而为）
//   /tmp/ddc-probe set 30       # 写亮度 30（0-100）
//   /tmp/ddc-probe discover     # 只列外接屏与 AVService 绑定
// 与 App 同源逻辑（PrivateAPI/DDC/DDCDiscovery 的精简单文件版），
// 用于「App 之外」验证 DDC 通路（knock-first 征得同意后运行）。

import Foundation
import IOKit
import CoreGraphics

// MARK: - 私有 API（dlopen）

private func load<P>(_ dylib: String, _ symbol: String) -> P? {
    guard let handle = dlopen(dylib, RTLD_LAZY), let sym = dlsym(handle, symbol) else { return nil }
    return unsafeBitCast(sym, to: P.self)
}

typealias CreateWithServiceFn = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
typealias ReadI2CFn = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
typealias WriteI2CFn = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
typealias InfoDictFn = @convention(c) (CGDirectDisplayID) -> UnsafeMutableRawPointer?

let createWithService = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceCreateWithService") as CreateWithServiceFn?
let readI2C = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceReadI2C") as ReadI2CFn?
let writeI2C = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceWriteI2C") as WriteI2CFn?
let infoDict = load("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", "CoreDisplay_DisplayCreateInfoDictionary") as InfoDictFn?
let allocator = kCFAllocatorDefault.map { Unmanaged.passUnretained($0).toOpaque() }

// MARK: - DDC 纯逻辑（与 Sources/MoniSwitch/DDC.swift 同源）

func writePacket(feature: UInt8, value: UInt16) -> [UInt8] {
    var p: [UInt8] = [0x84, 0x03, feature, UInt8(value >> 8), UInt8(value & 0xFF), 0]
    p[5] = p[0...4].reduce(0x6E ^ 0x51) { $0 ^ $1 }
    return p
}

func readRequest(feature: UInt8) -> [UInt8] {
    var p: [UInt8] = [0x82, 0x01, feature, 0]
    p[3] = p[0...2].reduce(0x6E) { $0 ^ $1 }
    return p
}

func parseReply(_ r: [UInt8]) -> (current: UInt16, max: UInt16)? {
    guard r.count >= 11 else { return nil }
    let chk = r[0...9].reduce(into: UInt8(0x50)) { acc, b in acc ^= b }
    guard chk == r[10] else { return nil }
    return (UInt16(r[8]) << 8 | UInt16(r[9]), UInt16(r[6]) << 8 | UInt16(r[7]))
}

// MARK: - 发现（m1ddc 精确绑定法的精简版：单趟扫描）

func registryString(_ entry: io_service_t, _ key: String) -> String? {
    IORegistryEntrySearchCFProperty(entry, "IOService", key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? String
}

func discoverFirstExternal() -> (service: UnsafeMutableRawPointer, name: String)? {
    guard let infoDict, let createWithService else { return nil }
    var online = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(32, &online, &count)

    var adapter: io_registry_entry_t = 0
    var name = ""
    for id in online.prefix(Int(count)) where id != 0 {
        guard let raw = infoDict(id) else { continue }
        let dict = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
        guard let location = dict["IODisplayLocation"] as? String else { continue }
        let entry = IORegistryEntryCopyFromPath(kIOMainPortDefault, location as CFString)
        guard entry != 0 else { continue }
        if let attrs = IORegistryEntrySearchCFProperty(entry, "IOService", "DisplayAttributes" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? NSDictionary,
           let product = attrs["ProductAttributes"] as? NSDictionary,
           let productName = product["ProductName"] as? String {
            name = productName
        }
        adapter = entry
        break
    }
    guard adapter != 0 else { return nil }
    defer { IOObjectRelease(adapter) }

    var adapterID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(adapter, &adapterID) == KERN_SUCCESS else { return nil }

    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != 0 else { return nil }
    var iter = io_iterator_t()
    guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else {
        IOObjectRelease(root)
        return nil
    }
    defer { IOObjectRelease(iter); IOObjectRelease(root) }

    var currentFB: UInt64 = 0
    while true {
        let service = IOIteratorNext(iter)
        guard service != 0 else { break }
        if IOObjectConformsTo(service, "IOMobileFramebuffer") != 0 {
            var fbID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &fbID) == KERN_SUCCESS { currentFB = fbID }
            IOObjectRelease(service)
            continue
        }
        // io_name_t 元组在 swiftc 下会触发编译器哑火 bug，直接用 CChar 缓冲
        let nm = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        nm.initialize(repeating: 0, count: 128)
        defer {
            nm.deinitialize(count: 128)
            nm.deallocate()
        }
        if IORegistryEntryGetName(service, nm) == KERN_SUCCESS,
           String(cString: nm) == "DCPAVServiceProxy",
           currentFB == adapterID,
           registryString(service, "Location") == "External",
           let av = createWithService(allocator, service) {
            print("已绑定: \(name.isEmpty ? "external display" : name)")
            return (av, name)
        }
        IOObjectRelease(service)
    }
    return nil
}

// MARK: - 读写

func writeBrightness(_ service: UnsafeMutableRawPointer, _ value: UInt16) -> Bool {
    guard let writeI2C else { return false }
    var packet = writePacket(feature: 0x10, value: value)
    let len = packet.count
    return packet.withUnsafeMutableBytes { buf in
        guard let base = buf.baseAddress else { return false }
        // m1ddc 语义：连续写 DDC_ITERATIONS=2 次（10ms 间隔，同进程），部分屏忽略单次写
        var anyOk = false
        for _ in 0..<2 {
            usleep(10_000)
            if writeI2C(service, 0x37, 0x51, base, UInt32(len)) == KERN_SUCCESS { anyOk = true }
        }
        return anyOk
    }
}

func readBrightness(_ service: UnsafeMutableRawPointer) -> (UInt16, UInt16)? {
    guard let writeI2C, let readI2C else { return nil }
    var req = readRequest(feature: 0x10)
    let reqLen = req.count
    let wrote: Bool = req.withUnsafeMutableBytes { buf in
        guard let base = buf.baseAddress else { return false }
        usleep(10_000)
        return writeI2C(service, 0x37, 0x51, base, UInt32(reqLen)) == KERN_SUCCESS
    }
    guard wrote else { return nil }
    var reply = [UInt8](repeating: 0, count: 11)
    let replyLen = reply.count
    var parsed: (UInt16, UInt16)?
    reply.withUnsafeMutableBytes { buf in
        guard let base = buf.baseAddress else { return }
        usleep(20_000)
        guard readI2C(service, 0x37, 0x51, base, UInt32(replyLen)) == KERN_SUCCESS else { return }
        let bytes = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: replyLen)
        parsed = parseReply(Array(bytes))
    }
    return parsed
}

// MARK: - main

guard let device = discoverFirstExternal() else {
    FileHandle.standardError.write("未发现可 DDC 控制的外接屏\n".data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "get" {
case "get", "read":
    if let (current, max) = readBrightness(device.service) {
        print("当前亮度: \(current)/\(max)")
    } else {
        print("读失败（DDC 读不可靠属常态；写通常仍可用）")
        exit(2)
    }
case "set", "write":
    let value = UInt16(args.count > 2 ? Int(args[2]) ?? 50 : 50)
    let ok = writeBrightness(device.service, value)
    print(ok ? "已写亮度 \(value) ✔" : "写失败 ✘")
    exit(ok ? 0 : 3)
case "discover":
    print("发现外接屏: \(device.name.isEmpty ? "(未命名)" : device.name)")
default:
    print("用法: ddc-probe [get | set <0-100> | discover]")
}
