import Foundation

/// A GGUF tensor type, by its numeric type id (the GGUF v3 wire value).
/// A raw-value struct (not an exhaustive enum) so any type id is representable;
/// the named constants are the ones the Mellum contract cares about.
public struct GGUFType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let f32 = GGUFType(rawValue: 0)
    public static let q5_0 = GGUFType(rawValue: 6)
    public static let q8_0 = GGUFType(rawValue: 8)
    public static let q8_1 = GGUFType(rawValue: 9)
    /// Laguna S 2.1's routed experts on layers 1–20 (`RoutedQ2_K` in the
    /// filename); GGUF v3 type id 10.
    public static let q2_k = GGUFType(rawValue: 10)
    public static let q3_k = GGUFType(rawValue: 11)
    public static let q4_k = GGUFType(rawValue: 12)

    public var name: String {
        switch rawValue {
        case 0: return "f32"
        case 6: return "q5_0"
        case 8: return "q8_0"
        case 9: return "q8_1"
        case 10: return "q2_k"
        case 11: return "q3_k"
        case 12: return "q4_k"
        default: return "type(\(rawValue))"
        }
    }
}

/// The GGUF v3 facts a variant contract is verified against: the architecture
/// string, the rope scaling type and frequency base, and every tensor's type.
public struct GGUFMetadata: Equatable, Sendable {
    public var architecture: String?
    public var ropeScalingType: String?
    public var ropeFreqBase: Double?
    public var tensorTypes: [String: GGUFType]

    public init(
        architecture: String? = nil,
        ropeScalingType: String? = nil,
        ropeFreqBase: Double? = nil,
        tensorTypes: [String: GGUFType] = [:]
    ) {
        self.architecture = architecture
        self.ropeScalingType = ropeScalingType
        self.ropeFreqBase = ropeFreqBase
        self.tensorTypes = tensorTypes
    }
}

/// Parses GGUF v3 header + metadata + tensor directory (no weights). Reads only
/// the byte ranges the header describes — never the tensor payload, never mmaps.
public enum GGUFMetadataReader {
    public struct ReadError: Error, Equatable, Sendable {
        public var path: String
        public var reason: String

        public init(path: String, reason: String) {
            self.path = path
            self.reason = reason
        }
    }

    // GGUF v3 metadata value types.
    private static let uint8: UInt32 = 0
    private static let int8: UInt32 = 1
    private static let uint16: UInt32 = 2
    private static let int16: UInt32 = 3
    private static let uint32: UInt32 = 4
    private static let int32: UInt32 = 5
    private static let float32: UInt32 = 6
    private static let bool: UInt32 = 7
    private static let string: UInt32 = 8
    private static let array: UInt32 = 9
    private static let uint64: UInt32 = 10
    private static let int64: UInt32 = 11
    private static let float64: UInt32 = 12

    private static let magicGGUF: UInt32 = 0x4655_4747  // "GGUF" little-endian

    public static func parse(at url: URL) throws -> GGUFMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ReadError(path: url.path, reason: "cannot open file")
        }
        defer { try? handle.close() }

        let r = Reader(handle: handle, path: url.path)

        // Header: magic u32, version u32, n_tensors u64, n_kv u64. Validate
        // magic and version before reading further, so a bad file is refused by
        // name (not masked as a truncation).
        let magic = try r.readU32()
        guard magic == magicGGUF else {
            throw ReadError(path: url.path, reason: "not a GGUF file (bad magic)")
        }
        let version = try r.readU32()
        guard version == 3 else {
            throw ReadError(path: url.path, reason: "GGUF version \(version) not supported (expected 3)")
        }
        let nTensors = try r.readU64()
        let nKV = try r.readU64()

        var architecture: String?
        var ropeScalingType: String?
        var ropeFreqBase: Double?

        // Metadata key/value pairs. Unknown keys are skipped correctly so the
        // cursor stays honest; a malformed value type is a named refusal.
        for _ in 0..<nKV {
            let key = try r.readString()
            let type = try r.readU32()
            switch key {
            case "general.architecture":
                guard type == string else {
                    throw ReadError(path: url.path, reason: "general.architecture is not a string")
                }
                architecture = try r.readString()
            case "mellum.rope.scaling.type":
                guard type == string else {
                    throw ReadError(path: url.path, reason: "mellum.rope.scaling.type is not a string")
                }
                ropeScalingType = try r.readString()
            case "mellum.rope.freq_base":
                guard type == float32 else {
                    throw ReadError(path: url.path, reason: "mellum.rope.freq_base is not f32")
                }
                ropeFreqBase = try r.readF32()
            case "laguna.rope.scaling.type":
                guard type == string else {
                    throw ReadError(path: url.path, reason: "laguna.rope.scaling.type is not a string")
                }
                ropeScalingType = try r.readString()
            case "laguna.rope.freq_base":
                guard type == float32 else {
                    throw ReadError(path: url.path, reason: "laguna.rope.freq_base is not f32")
                }
                ropeFreqBase = try r.readF32()
            default:
                try r.skipValue(type: type)
            }
        }

        // Tensor directory: name, ndim, ndim x u64 dims, type u32, offset u64.
        var tensorTypes: [String: GGUFType] = [:]
        for _ in 0..<nTensors {
            let name = try r.readString()
            let ndim = try r.readU32()
            for _ in 0..<ndim { _ = try r.readU64() }
            let type = try r.readU32()
            _ = try r.readU64()  // relative offset, ignored
            tensorTypes[name] = GGUFType(rawValue: type)
        }

        return GGUFMetadata(
            architecture: architecture,
            ropeScalingType: ropeScalingType,
            ropeFreqBase: ropeFreqBase,
            tensorTypes: tensorTypes
        )
    }

    /// Sequential, little-endian, alignment-safe reader over a FileHandle.
    /// Owns the handle transitively (the caller owns it; this only reads).
    private struct Reader {
        let handle: FileHandle
        let path: String

        func readExactly(_ count: Int) throws -> Data {
            var out = Data()
            while out.count < count {
                let chunk = try handle.read(upToCount: count - out.count) ?? Data()
                if chunk.isEmpty {
                    throw ReadError(path: path, reason: "truncated file (unexpected EOF)")
                }
                out.append(chunk)
            }
            return out
        }

        func readU32() throws -> UInt32 {
            let d = try readExactly(4)
            let i = d.startIndex
            return UInt32(d[i])
                | (UInt32(d[i + 1]) << 8)
                | (UInt32(d[i + 2]) << 16)
                | (UInt32(d[i + 3]) << 24)
        }

        func readU64() throws -> UInt64 {
            let d = try readExactly(8)
            var v: UInt64 = 0
            for k in 0..<8 {
                v |= UInt64(d[d.startIndex + k]) << (8 * k)
            }
            return v
        }

        func readF32() throws -> Double {
            let bits = try readU32()
            return Double(Float(bitPattern: bits))
        }

        func readString() throws -> String {
            let len = try readU64()
            guard len <= 1_048_576 else {
                throw ReadError(path: path, reason: "unreasonable string length \(len)")
            }
            let bytes = try readExactly(Int(len))
            guard let s = String(data: bytes, encoding: .utf8) else {
                throw ReadError(path: path, reason: "non-UTF-8 string")
            }
            return s
        }

        func skipValue(type: UInt32) throws {
            switch type {
            case uint8, int8, bool:
                _ = try readExactly(1)
            case uint16, int16:
                _ = try readExactly(2)
            case uint32, int32, float32:
                _ = try readExactly(4)
            case uint64, int64, float64:
                _ = try readExactly(8)
            case string:
                _ = try readString()
            case array:
                let itemType = try readU32()
                let count = try readU64()
                if itemType == string {
                    for _ in 0..<count { _ = try readString() }
                } else {
                    let size = scalarSize(itemType)
                    guard size > 0 else {
                        throw ReadError(path: path, reason: "unknown array item type \(itemType)")
                    }
                    _ = try readExactly(Int(count) * size)
                }
            default:
                throw ReadError(path: path, reason: "unknown metadata value type \(type)")
            }
        }

        func scalarSize(_ type: UInt32) -> Int {
            switch type {
            case uint8, int8, bool: return 1
            case uint16, int16: return 2
            case uint32, int32, float32: return 4
            case uint64, int64, float64: return 8
            default: return 0
            }
        }
    }
}
