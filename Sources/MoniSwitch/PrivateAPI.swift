import Foundation
import IOKit
import CoreGraphics

/// 私有 API 运行时桥接：dlopen + dlsym 取函数指针。
///
/// 用运行时解析而非链接期符号（@_silgen_name / bridging header）的原因：
/// ① 纯 SPM 无 bridging header（项目约定，早年 UCKeyTranslate 因此弃用）；
/// ② 符号缺失时优雅降级为 nil，App 永不因系统私有 API 变动而启动失败/链接失败。
///
/// CF 对象在函数指针签名里一律用 UnsafeMutableRawPointer 表示（ABI 上 CF 对象
/// 就是指针；Swift 的 CFTypeRef=Any 不能进 @convention(c)）。释放走 dlsym 的
/// CFRelease（同 ABI），创建走 Create 规则由调用方持有。
enum PrivateAPI {
    /// IOAVService（opaque CF 对象）的指针形式。
    typealias IOAVServiceRef = UnsafeMutableRawPointer

    typealias IOAVServiceCreateWithServiceFn = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> IOAVServiceRef?
    typealias IOAVServiceReadI2CFn = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias IOAVServiceWriteI2CFn = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias DisplayCreateInfoDictionaryFn = @convention(c) (CGDirectDisplayID) -> UnsafeMutableRawPointer?
    typealias CFReleaseFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    static let ioAVServiceCreateWithService: IOAVServiceCreateWithServiceFn? = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceCreateWithService")
    static let ioAVServiceReadI2C: IOAVServiceReadI2CFn? = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceReadI2C")
    static let ioAVServiceWriteI2C: IOAVServiceWriteI2CFn? = load("/System/Library/Frameworks/IOKit.framework/IOKit", "IOAVServiceWriteI2C")
    static let displayCreateInfoDictionary: DisplayCreateInfoDictionaryFn? = load("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CoreDisplay_DisplayCreateInfoDictionary")
    static let cfRelease: CFReleaseFn? = load("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFRelease")

    /// kCFAllocatorDefault 的指针形式（Create 函数的首参）。
    static let defaultAllocator: UnsafeMutableRawPointer? = kCFAllocatorDefault.map { Unmanaged.passUnretained($0).toOpaque() }

    private static func load<P>(_ dylib: String, _ symbol: String) -> P? {
        guard let handle = dlopen(dylib, RTLD_LAZY), let sym = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(sym, to: P.self)
    }

    /// 释放 Create 规则持有的 CF 对象（raw 指针形式）。
    static func release(_ ref: UnsafeMutableRawPointer?) {
        if let ref { cfRelease?(ref) }
    }
}
