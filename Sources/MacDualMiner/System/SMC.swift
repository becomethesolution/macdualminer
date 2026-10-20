import Foundation
import IOKit

/// Minimal read-only client for the Apple System Management Controller.
/// Used to read "PSTR" – total system power in watts – without root on Apple Silicon.
final class SMCReader {
    private var connection: io_connect_t = 0

    // Mirrors the kernel's SMCKeyData_t (80 bytes). The explicit `padding` keeps
    // Swift's layout identical to the C struct's.
    private struct KeyData {
        struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PowerLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var key: UInt32 = 0
        var version = Version()
        var powerLimit = PowerLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let kernelIndex: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Reads a float ("flt ") key such as PSTR. Returns nil if the key is missing.
    func readFloat(_ key: String) -> Double? {
        guard let reading = read(key), reading.bytes.count >= 4,
              reading.type == Self.fourCC("flt ") else { return nil }
        let bytes = reading.bytes
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }

    private func read(_ key: String) -> (type: UInt32, bytes: [UInt8])? {
        var input = KeyData()
        var output = KeyData()
        input.key = Self.fourCC(key)
        input.data8 = Self.cmdReadKeyInfo
        guard call(&input, &output), output.result == 0 else { return nil }

        let size = output.keyInfo.dataSize
        let type = output.keyInfo.dataType
        guard size > 0, size <= 32 else { return nil }

        input.keyInfo.dataSize = size
        input.data8 = Self.cmdReadBytes
        output = KeyData()
        guard call(&input, &output), output.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(size))) }
        return (type, bytes)
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> Bool {
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.kernelIndex,
            &input, MemoryLayout<KeyData>.stride,
            &output, &outputSize
        )
        return result == kIOReturnSuccess
    }

    static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
