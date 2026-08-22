import Foundation
import Darwin

// Minimal HTTP Range server for P3 integration tests. Committed test infra
// (not an engine fake). Serves one file with byte-range support and logs every
// served range to a file so tests can assert what was actually downloaded.
// Usage: RangeFileServer --port N --file F --log L

let args = CommandLine.arguments
guard let pi = args.firstIndex(of: "--port"), args.count > pi + 1, let port = Int(args[pi + 1]),
      let fi = args.firstIndex(of: "--file"), args.count > fi + 1,
      let li = args.firstIndex(of: "--log"), args.count > li + 1 else {
    FileHandle.standardError.write(Data("usage: RangeFileServer --port N --file F --log L\n".utf8))
    exit(2)
}
let fileURL = URL(fileURLWithPath: args[fi + 1])
let logURL = URL(fileURLWithPath: args[li + 1])
let data = try! Data(contentsOf: fileURL)

func logRange(_ r: ClosedRange<Int>) {
    // Append (not overwrite): the log accumulates every served range.
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
    defer { try? handle.close() }
    try? handle.seekToEnd()
    try? handle.write(contentsOf: Data("\(r.lowerBound)-\(r.upperBound)\n".utf8))
}

signal(SIGPIPE, SIG_IGN)

let sock = socket(AF_INET, SOCK_STREAM, 0)
var opt: Int32 = 1
setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = in_port_t(port).bigEndian
addr.sin_addr.s_addr = inet_addr("127.0.0.1")
_ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
_ = listen(sock, 8)
FileHandle.standardError.write(Data("range-file-server: listening on http://127.0.0.1:\(port)\n".utf8))

while true {
    let c = Darwin.accept(sock, nil, nil)
    guard c >= 0 else { continue }
    var request = Data()
    var readBuffer = [UInt8](repeating: 0, count: 4096)
    var headerDone = false
    while !headerDone {
        let n = Darwin.read(c, &readBuffer, readBuffer.count)
        if n <= 0 { break }
        request.append(contentsOf: readBuffer[0..<n])
        if let r = request.range(of: Data("\r\n\r\n".utf8)) {
            request.removeSubrange(r.upperBound..<request.endIndex)
            headerDone = true
        }
    }
    let text = String(decoding: request, as: UTF8.self)
    let lines = text.split(separator: "\r\n").map(String.init)
    let isHead = lines.first?.hasPrefix("HEAD") ?? false
    let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
    var body: Data
    var status = "200 OK"
    if let range = rangeHeader, let eq = range.firstIndex(of: "=") {
        let value = String(range[range.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if let dash = value.firstIndex(of: "-") {
            let fromText = String(value[..<dash]).trimmingCharacters(in: .whitespaces)
            let toText = String(value[value.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
            let from = Int(fromText) ?? 0
            let to = min(Int(toText) ?? (data.count - 1), data.count - 1)
            body = data.subdata(in: from..<(to + 1))
            status = "206 Partial Content"
            logRange(from...to)
        } else {
            body = data
            logRange(0...(data.count - 1))
        }
    } else {
        body = data
        logRange(0...(data.count - 1))
    }
    let bodyForReply = isHead ? Data() : body
    let head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\r\n"
    var out = Data(head.utf8)
    out.append(bodyForReply)
    _ = out.withUnsafeBytes { Darwin.write(c, $0.baseAddress!, $0.count) }
    Darwin.close(c)
}
