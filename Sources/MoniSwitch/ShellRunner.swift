import Foundation

/// 一次 shell 执行的结果。
struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// 封装对 displayplacer 二进制的调用。
///
/// 说明：MoniSwitch 把 displayplacer 二进制随 App 一起打包进 Resources/ 目录。
/// 运行时用 Bundle.main.url(forResource:) 定位它。所有调用都会：
///   - 在调用方线程同步执行（菜单动作里请用 DispatchQueue.global() 包裹）
///   - 捕获 stdout / stderr / 退出码
enum ShellRunner {

    /// 定位打包在 App 内的 displayplacer 二进制。
    /// - Returns: 二进制的文件 URL；若找不到返回 nil。
    static func locateDisplayPlacer() -> URL? {
        // 1. 打包后的 App：从 Bundle.main 的 Resources 取
        if let url = Bundle.main.url(forResource: "displayplacer", withExtension: nil) {
            return url
        }
        // 2. 开发/调试时：从项目源码目录的 Resources/ 取
        let devPath = "Resources/displayplacer"
        let devURL = URL(fileURLWithPath: devPath)
        if FileManager.default.isExecutableFile(atPath: devURL.path) {
            return devURL
        }
        return nil
    }

    /// 执行 displayplacer。
    /// - Parameter args: 参数数组（不含程序名本身）。
    /// - Returns: 执行结果。
    /// - Throws: 若无法定位二进制，或启动进程失败。
    static func run(_ args: [String]) throws -> ShellResult {
        guard let binURL = locateDisplayPlacer() else {
            throw NSError(
                domain: "MoniSwitch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 displayplacer 二进制。请确认 Resources/displayplacer 已随 App 打包。"]
            )
        }

        let process = Process()
        process.executableURL = binURL
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // 并发读两个管道、读完再等退出。管道缓冲区约 64KB，若「先 waitUntilExit
        // 再顺序读」，子进程输出超过缓冲区时 write() 阻塞、进程永远退不出，
        // 与等待退出的线程互锁（调用方串行队列随之卡死）。displayplacer 的
        // list 输出随屏的模式数增长，多模式屏可能逼近/超过缓冲区。
        // DataBox 用 class 包装：闭包跨线程写各自实例的属性，信号量同步后读取。
        final class DataBox { var data = Data() }
        let outBox = DataBox()
        let errBox = DataBox()
        let semaphore = DispatchSemaphore(value: 0)
        let ioQueue = DispatchQueue.global(qos: .utility)
        ioQueue.async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            semaphore.signal()
        }
        ioQueue.async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            semaphore.signal()
        }
        semaphore.wait()
        semaphore.wait()
        process.waitUntilExit()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outBox.data, encoding: .utf8) ?? "",
            stderr: String(data: errBox.data, encoding: .utf8) ?? ""
        )
    }
}
