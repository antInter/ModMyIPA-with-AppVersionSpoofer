import Foundation

// Reads bounded headers/load commands, never maps an entire executable into RAM.
// Detection only: does not modify encryption flags or decrypt any executable.
enum MachOInspector {
    static func isEncrypted(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            guard offset <= fileSize, UInt64(count) <= fileSize - offset else { throw IPAError("Truncated Mach-O executable.") }
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { throw IPAError("Unable to read executable header.") }
            return data
        }
        func integer(_ data: Data, _ offset: Int, _ count: Int, _ little: Bool) -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<count {
                let byte = data[offset + (little ? count - 1 - index : index)]
                value = (value << 8) | UInt64(byte)
            }
            return value
        }
        func thin(_ offset: UInt64, _ size: UInt64) throws -> Bool {
            guard size >= 28 else { throw IPAError("Invalid executable header.") }
            let header = try read(offset, 28)
            let magic = integer(header, 0, 4, false)
            let little = magic == 0xcefaedfe || magic == 0xcffaedfe
            let is64 = magic == 0xcffaedfe || magic == 0xfeedfacf
            guard little || magic == 0xfeedface || magic == 0xfeedfacf else {
                throw IPAError("Bundle executable is not a supported Mach-O file.")
            }
            let headerSize: UInt64 = is64 ? 32 : 28
            let commands = integer(header, 16, 4, little)
            let commandBytes = integer(header, 20, 4, little)
            guard size >= headerSize, commandBytes <= size - headerSize,
                  commandBytes <= 64 * 1024 * 1024, commands <= 16384 else { throw IPAError("Invalid Mach-O load commands.") }
            var position = headerSize
            let end = headerSize + commandBytes
            var encrypted = false
            for _ in 0..<commands {
                guard position <= end, end - position >= 8 else { throw IPAError("Truncated Mach-O load command.") }
                let command = try read(offset + position, 8)
                let kind = integer(command, 0, 4, little)
                let length = integer(command, 4, 4, little)
                guard length >= 8, length <= end - position else { throw IPAError("Invalid Mach-O command size.") }
                if kind == 0x21 || kind == 0x2c { // LC_ENCRYPTION_INFO / LC_ENCRYPTION_INFO_64
                    guard length >= (kind == 0x2c ? 24 : 20) else { throw IPAError("Invalid encryption load command.") }
                    let info = try read(offset + position, 20)
                    if integer(info, 16, 4, little) != 0 { encrypted = true }
                }
                position += length
            }
            guard position == end else { throw IPAError("Mach-O command count and size disagree.") }
            return encrypted
        }
        let header = try read(0, 8)
        let magic = integer(header, 0, 4, false)
        let fat = [UInt64(0xcafebabe), 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic)
        if !fat { return try thin(0, fileSize) }
        let little = magic == 0xbebafeca || magic == 0xbfbafeca
        let fat64 = magic == 0xcafebabf || magic == 0xbfbafeca
        let count = integer(header, 4, 4, little)
        guard count > 0, count <= 32 else { throw IPAError("Invalid universal executable slice count.") }
        let stride = fat64 ? 32 : 20
        let tableEnd = 8 + count * UInt64(stride)
        var encrypted = false
        for index in 0..<count {
            let arch = try read(8 + index * UInt64(stride), stride)
            let offset = integer(arch, 8, fat64 ? 8 : 4, little)
            let size = integer(arch, fat64 ? 16 : 12, fat64 ? 8 : 4, little)
            guard offset >= tableEnd, offset <= fileSize, size <= fileSize - offset else { throw IPAError("Invalid universal executable slice bounds.") }
            if try thin(offset, size) { encrypted = true }
        }
        return encrypted
    }
}
