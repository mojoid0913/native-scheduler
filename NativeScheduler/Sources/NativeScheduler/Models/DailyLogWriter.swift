// NativeScheduler/Sources/NativeScheduler/Models/DailyLogWriter.swift
// Binary log format: 16-byte header + heatmap slot table + variable category map
// Slot lookup: O(1) via seek to 16 + slotIndex * 8

import Foundation

struct DailyLogWriter {
    static let magic: UInt32 = 0x4E534C47  // "NSLG"
    static let version: UInt32 = 2
    static let headerSize = 16
    static let slotSize   = 8
    static let slotCount  = 24 * HeatmapSlot.rowsPerHour

    // MARK: - Write

    enum WriteError: Error {
        case unavailableLogDirectory
    }

    static func write(
        slots: [HeatmapSlotData],
        date: Date,
        categories: [CategoryData]
    ) throws {
        guard let url = logURL(for: date) else {
            throw WriteError.unavailableLogDirectory
        }
        let data = encode(slots: slots, date: date, categories: categories)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func encode(
        slots: [HeatmapSlotData],
        date: Date,
        categories: [CategoryData]
    ) -> Data {
        var data = Data(capacity: headerSize + slotCount * slotSize + 512)

        // Header
        data.append(uint32: magic)
        data.append(uint32: version)
        data.append(uint32: daysSinceEpoch(date))
        data.append(uint32: 0) // reserved

        // Slot table (one entry per heatmap slot).
        let slotMap = Dictionary(uniqueKeysWithValues: slots.map { ($0.index, $0) })
        for i in 0..<slotCount {
            if let s = slotMap[i] {
                data.append(s.categoryIndex)
                data.append(s.dominantMinutes)
            } else {
                data.append(0) // default/gray
                data.append(0)
            }
            data.append(contentsOf: [0, 0, 0, 0, 0, 0]) // reserved
        }

        // Category index map
        data.append(UInt8(min(categories.count, 255)))
        for cat in categories.prefix(255) {
            data.append(cat.index)
            let hexBytes = Array(cat.colorHex.prefix(6).utf8)
            data.append(contentsOf: hexBytes + Array(repeating: 0, count: max(0, 6 - hexBytes.count)))
            let nameBytes = Array(cat.name.utf8.prefix(255))
            data.append(UInt8(nameBytes.count))
            data.append(contentsOf: nameBytes)
        }

        return data
    }

    // MARK: - Read

    static func read(date: Date) -> [Int: HeatmapSlotData]? {
        guard let url = logURL(for: date) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> [Int: HeatmapSlotData]? {
        guard data.count >= headerSize + slotCount * slotSize else { return nil }

        // Validate magic
        let readMagic = data.uint32(at: 0)
        guard readMagic == magic else { return nil }
        guard data.uint32(at: 4) == version else { return nil }

        var result: [Int: HeatmapSlotData] = [:]
        for i in 0..<slotCount {
            let offset = headerSize + i * slotSize
            let categoryIndex  = data[offset]
            let dominantMinutes = data[offset + 1]
            if dominantMinutes > 0 {
                result[i] = HeatmapSlotData(index: i, categoryIndex: categoryIndex, dominantMinutes: dominantMinutes)
            }
        }
        return result
    }

    // MARK: - URL

    static func logURL(for date: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "\(formatter.string(from: date))_log.bin"
        guard let directory = resolveLogDirectory(
            environment: ProcessInfo.processInfo.environment,
            applicationSupportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
            fileExists: FileManager.default.fileExists(atPath:)
        ) else { return nil }
        return directory.appendingPathComponent(name)
    }

    static func resolveLogDirectory(
        environment: [String: String],
        applicationSupportDirectory: URL,
        fileExists: (String) -> Bool
    ) -> URL? {
        guard environment["NATIVE_SCHEDULER_SMOKE_AUTOSTART"] == "1" else {
            return applicationSupportDirectory
                .appendingPathComponent("NativeScheduler/logs", isDirectory: true)
        }
        guard let rootPath = environment["NATIVE_SCHEDULER_SMOKE_STORE_ROOT"],
              rootPath.hasPrefix("/"), rootPath != "/" else { return nil }
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        guard root.path == rootPath,
              fileExists(root.appendingPathComponent(".native-scheduler-isolated-qa").path) else { return nil }
        return root.appendingPathComponent("logs", isDirectory: true)
    }

    private static func daysSinceEpoch(_ date: Date) -> UInt32 {
        let epoch = Date(timeIntervalSince1970: 0)
        return UInt32(Calendar.current.dateComponents([.day], from: epoch, to: date).day ?? 0)
    }
}

// MARK: - Supporting types

struct HeatmapSlotData {
    let index: Int
    let categoryIndex: UInt8 // 0 = default, 1–12 = user category
    let dominantMinutes: UInt8
}

struct CategoryData {
    let index: UInt8
    let colorHex: String
    let name: String
}

// MARK: - Data helpers

private extension Data {
    mutating func append(uint32 value: UInt32) {
        var v = value.bigEndian
        append(Data(bytes: &v, count: 4))
    }

    func uint32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { ptr in
            copyBytes(to: ptr, from: offset..<(offset + 4))
        }
        return UInt32(bigEndian: value)
    }
}
