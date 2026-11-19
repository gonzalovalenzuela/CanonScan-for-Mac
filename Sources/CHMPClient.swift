// CHMPClient.swift
// Cliente del protocolo CHMP de Canon (escaneo por HTTP, puerto 80).
// Canon CHMP protocol client (scanning over HTTP, port 80).
//
// Basado en chmp_scan.py de dfrancio-DF/canon-g3010-sane, derivado de
// wailun42/canon-g3010-chmp-scanner (licencia MIT, ver LICENSES.txt).
// Based on chmp_scan.py from dfrancio-DF/canon-g3010-sane, derived from
// wailun42/canon-g3010-chmp-scanner (MIT license, see LICENSES.txt).

import Foundation
import Darwin

enum CHMPError: LocalizedError {
    case connection(String)
    case http(String)
    case protocolError(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .connection(let m): return L("No se pudo conectar con la impresora: %@", m)
        case .http(let m): return L("Respuesta HTTP inesperada: %@", m)
        case .protocolError(let m): return L("Error del escáner: %@", m)
        case .timeout(let m): return L("Tiempo de espera agotado: %@", m)
        }
    }
}

/// Parámetros de un escaneo / Scan parameters
struct ScanSettings {
    var dpi: Int          // 150, 300 o 600
    var grayscale: Bool
}

/// Conexión CHMP bloqueante; usar siempre fuera del hilo principal.
/// Blocking CHMP connection; always use off the main thread.
final class CHMPClient {
    private static let endpoint = "/canon/ij/command2/port3"
    private static let chmpVersion = "1.4.0"

    private let host: String
    private var fd: Int32 = -1
    private var buffer = [UInt8]()   // bytes leídos y aún no consumidos / read-ahead bytes

    init(host: String, timeout: TimeInterval = 30) throws {
        self.host = host
        try connect(timeout: timeout)
    }

    deinit { close() }

    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    // MARK: - Socket

    private func connect(timeout: TimeInterval) throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, "80", &hints, &res)
        guard rc == 0, let first = res else {
            throw CHMPError.connection(String(cString: gai_strerror(rc)))
        }
        defer { freeaddrinfo(res) }

        var lastError = L("sin direcciones")
        var ai: UnsafeMutablePointer<addrinfo>? = first
        while let a = ai {
            let s = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if s >= 0 {
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var one: Int32 = 1
                setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
                setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                if Darwin.connect(s, a.pointee.ai_addr, a.pointee.ai_addrlen) == 0 {
                    fd = s
                    return
                }
                lastError = String(cString: strerror(errno))
                Darwin.close(s)
            }
            ai = a.pointee.ai_next
        }
        throw CHMPError.connection(lastError)
    }

    private func sendAll(_ data: [UInt8]) throws {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress! + sent, data.count - sent, 0)
            }
            if n <= 0 { throw CHMPError.connection(L("envío fallido (%@)", String(cString: strerror(errno)))) }
            sent += n
        }
    }

    /// Llena el buffer con al menos un byte más / Fill buffer with at least one more byte
    private func fill() throws {
        var tmp = [UInt8](repeating: 0, count: 65536)
        let n = tmp.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress!, 65536, 0) }
        if n == 0 { throw CHMPError.connection(L("la impresora cerró la conexión")) }
        if n < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { throw CHMPError.timeout(L("sin respuesta de la impresora")) }
            throw CHMPError.connection(String(cString: strerror(errno)))
        }
        buffer.append(contentsOf: tmp[0..<n])
    }

    private func readUntil(_ marker: [UInt8]) throws -> [UInt8] {
        var searchFrom = 0
        while true {
            if buffer.count >= marker.count {
                let last = buffer.count - marker.count
                if searchFrom <= last {
                    for i in searchFrom...last where buffer[i..<(i + marker.count)].elementsEqual(marker) {
                        let out = Array(buffer[0..<(i + marker.count)])
                        buffer.removeFirst(i + marker.count)
                        return out
                    }
                    searchFrom = last + 1
                }
            }
            try fill()
        }
    }

    private func readExactly(_ count: Int) throws -> [UInt8] {
        while buffer.count < count { try fill() }
        let out = Array(buffer[0..<count])
        buffer.removeFirst(count)
        return out
    }

    // MARK: - HTTP

    private static let crlf: [UInt8] = [13, 10]
    private static let headerEnd: [UInt8] = [13, 10, 13, 10]

    private func readResponse() throws -> [UInt8] {
        let head = String(decoding: try readUntil(Self.headerEnd), as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let status = lines.first ?? ""
        var headers = [String: String]()
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }
        let isChunked = headers["transfer-encoding"]?.lowercased().contains("chunked") ?? false
        let body: [UInt8]
        if isChunked {
            body = try readChunked()
        } else {
            body = try readExactly(Int(headers["content-length"] ?? "0") ?? 0)
        }
        let parts = status.split(separator: " ")
        guard parts.count >= 2, parts[1] == "200" else { throw CHMPError.http(status) }
        return body
    }

    private func readChunked() throws -> [UInt8] {
        var body = [UInt8]()
        while true {
            let line = String(decoding: try readUntil(Self.crlf), as: UTF8.self)
            let sizeText = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ";").first.map(String.init) ?? ""
            if sizeText.isEmpty { continue }
            guard let size = Int(sizeText, radix: 16) else {
                throw CHMPError.http(L("tamaño de bloque inválido"))
            }
            if size == 0 {
                _ = try readUntil(Self.crlf)
                return body
            }
            body.append(contentsOf: try readExactly(size))
            guard try readUntil(Self.crlf) == Self.crlf else {
                throw CHMPError.http(L("delimitador de bloque inválido"))
            }
        }
    }

    private func post(_ body: [UInt8]) throws {
        let header = "POST \(Self.endpoint) HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "X-CHMP-Version: \(Self.chmpVersion)\r\n"
            + "X-CHMP-Timeout: 20\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: Keep-Alive\r\n\r\n"
        try sendAll(Array(header.utf8) + body)
        _ = try readResponse()
    }

    private func get() throws -> [UInt8] {
        let header = "GET \(Self.endpoint) HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Connection: Keep-Alive\r\n"
            + "X-CHMP-Version: \(Self.chmpVersion)\r\n\r\n"
        try sendAll(Array(header.utf8))
        return try readResponse()
    }

    /// Envía un comando y lee su respuesta / Send a command and read its reply
    private func exchange(_ body: [UInt8]) throws -> [UInt8] {
        try post(body)
        return try get()
    }

    // MARK: - Comandos del escáner / Scanner commands

    private static func hex(_ s: String) -> [UInt8] {
        var out = [UInt8]()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    private static let cmdStartSession = hex("db200001000000000000000000000000")
    private static let cmdAbortSession = hex("ef200000000000000000000000000000")
    private static let cmdCapability   = hex("f3200000000000000000000000000010")
    private static let cmdDimensions   = hex("dc200000000000000000000000000008")
    private static let cmdScanStart    = hex("d9200001000000000000000000000000")
    private static let cmdStatus       = hex("da200000000000000000000000000008")

    private static func cmdReadImage() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 16)
        b[0] = 0xd4; b[1] = 0x20
        b[12] = 0x00; b[13] = 0x20   // bloque de 0x20 × 64 KiB / block size
        return b
    }

    private static let xmlHead = #"<?xml version="1.0" encoding="utf-8" ?><cmd xmlns:ivec="http://www.canon.com/ns/cmd/2008/07/common/""#
    private static let xmlVcn = #" xmlns:vcn="http://www.canon.com/ns/cmd/2008/07/canon/""#

    private static func xmlModeShift(jobID: String) -> [UInt8] {
        Array((xmlHead + xmlVcn + "><ivec:contents><ivec:operation>VendorCmd</ivec:operation><ivec:param_set servicetype=\"scan\"><ivec:jobID>\(jobID)</ivec:jobID><vcn:ijoperation>ModeShift</vcn:ijoperation><vcn:ijmode>1</vcn:ijmode></ivec:param_set></ivec:contents></cmd>").utf8)
    }

    private static let xmlStartJob = Array((xmlHead + "><ivec:contents><ivec:operation>StartJob</ivec:operation><ivec:param_set servicetype=\"scan\"><ivec:jobID>00000001</ivec:jobID><ivec:bidi>1</ivec:bidi></ivec:param_set></ivec:contents></cmd>").utf8)

    private static let xmlEndJob = Array((xmlHead + "><ivec:contents><ivec:operation>EndJob</ivec:operation><ivec:param_set servicetype=\"scan\"><ivec:jobID>00000001</ivec:jobID></ivec:param_set></ivec:contents></cmd>").utf8)

    /// Comando de parámetros para A4 completo / Parameter command for full A4
    private static func cmdScanParams(_ s: ScanSettings) -> [UInt8] {
        let width = (Int(210.0 / 25.4 * Double(s.dpi)) + 31) & ~31
        let height = Int(297.0 / 25.4 * Double(s.dpi))
        var d = [UInt8](repeating: 0, count: 0x38)
        d[0x00] = 0x01; d[0x01] = 0x01; d[0x02] = 0x01
        let res = UInt16(s.dpi) | 0x8000
        d[0x08] = UInt8(res >> 8); d[0x09] = UInt8(res & 0xff)
        d[0x0A] = UInt8(res >> 8); d[0x0B] = UInt8(res & 0xff)
        putBE32(&d, 0x14, UInt32(width))
        putBE32(&d, 0x18, UInt32(height))
        if s.grayscale { d[0x1C] = 0x04; d[0x1D] = 8 } else { d[0x1C] = 0x08; d[0x1D] = 24 }
        d[0x1F] = 0x01; d[0x20] = 0xFF; d[0x21] = 0x82
        d[0x23] = 0x02; d[0x24] = 0x01; d[0x30] = 0x01
        // Último byte: suma de control / Last byte: checksum
        let sum = d[0..<(d.count - 1)].reduce(0) { $0 &+ Int($1) }
        d[d.count - 1] = UInt8((-sum) & 0xFF)
        var cmd = [UInt8](repeating: 0, count: 16)
        cmd[0] = 0xD8; cmd[1] = 0x20
        cmd[14] = UInt8(d.count >> 8); cmd[15] = UInt8(d.count & 0xff)
        return cmd + d
    }

    private static func putBE32(_ d: inout [UInt8], _ at: Int, _ v: UInt32) {
        d[at] = UInt8(v >> 24); d[at + 1] = UInt8((v >> 16) & 0xff)
        d[at + 2] = UInt8((v >> 8) & 0xff); d[at + 3] = UInt8(v & 0xff)
    }

    private static func requireOK(_ r: [UInt8], _ label: String) throws {
        guard r.count >= 2, r[0] == 0x06, r[1] == 0x06 else {
            throw CHMPError.protocolError(L("%@ rechazado", L(label)))
        }
    }

    private static func containsOK(_ r: [UInt8]) -> Bool {
        String(decoding: r, as: UTF8.self).contains("OK")
    }

    // MARK: - Escaneo / Scan

    /// Escanea una página y devuelve el JPEG que entrega la impresora.
    /// Scans one page and returns the JPEG produced by the printer.
    /// - Parameter progress: bytes recibidos / bytes received (se llama desde este hilo)
    func scan(_ settings: ScanSettings, progress: (String) -> Void) throws -> Data {
        var sessionOpen = false
        defer {
            // Limpieza: cierra sesión y trabajo aunque haya fallado.
            // Cleanup: close session and job even after a failure.
            if sessionOpen { _ = try? exchange(Self.cmdAbortSession) }
            _ = try? exchange(Self.xmlEndJob)
            _ = try? exchange([0x00])
        }

        progress(L("Conectando con el escáner…"))
        _ = try exchange([0x00])
        _ = try exchange([0x00])
        guard Self.containsOK(try exchange(Self.xmlModeShift(jobID: " "))) else {
            throw CHMPError.protocolError(L("la impresora no aceptó el modo escáner (¿está ocupada?)"))
        }
        _ = try exchange(Self.cmdCapability)
        guard Self.containsOK(try exchange(Self.xmlStartJob)) else {
            throw CHMPError.protocolError(L("la impresora rechazó el trabajo de escaneo"))
        }
        guard Self.containsOK(try exchange(Self.xmlModeShift(jobID: "00000001"))) else {
            throw CHMPError.protocolError(L("la impresora rechazó el cambio de modo"))
        }
        try Self.requireOK(try exchange(Self.cmdStartSession), "Inicio de sesión")
        sessionOpen = true
        _ = try exchange(Self.cmdCapability)
        try Self.requireOK(try exchange(Self.cmdScanParams(settings)), "Parámetros")
        try Self.requireOK(try exchange(Self.cmdScanStart), "Inicio de escaneo")

        progress(L("Escaneando…"))
        let readyDeadline = Date().addingTimeInterval(180)
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            let r = try exchange(Self.cmdStatus)
            try Self.requireOK(r, "Estado")
            let state = r.count > 8 ? r[8] : 0xFF
            if state == 0x03 { break }
            guard state == 0x00 || state == 0x02 else {
                throw CHMPError.protocolError(L("estado inesperado 0x%02x", state))
            }
            if Date() > readyDeadline { throw CHMPError.timeout(L("el escáner no terminó de leer la página")) }
        }

        _ = try exchange(Self.cmdDimensions)

        // Lee bloques hasta la marca de fin; límite por tiempo, no por cantidad,
        // porque a 600 dpi en color hay cientos de bloques.
        // Read blocks until the end flag; time-limited rather than count-limited,
        // since 600 dpi color yields hundreds of blocks.
        var image = Data()
        let readDeadline = Date().addingTimeInterval(600)
        while true {
            let r = try exchange(Self.cmdReadImage())
            try Self.requireOK(r, "Lectura de imagen")
            guard r.count >= 16 else { throw CHMPError.protocolError(L("bloque de imagen incompleto")) }
            let end = (r[8] & 0x20) != 0
            let len = Int(r[12]) << 24 | Int(r[13]) << 16 | Int(r[14]) << 8 | Int(r[15])
            if len > 0 {
                guard r.count >= 16 + len else { throw CHMPError.protocolError(L("bloque de imagen truncado")) }
                image.append(contentsOf: r[16..<(16 + len)])
                progress(L("Recibiendo imagen… %@", ByteCountFormatter.string(fromByteCount: Int64(image.count), countStyle: .file)))
            } else if !end {
                Thread.sleep(forTimeInterval: 0.05)   // aún no hay datos / no data yet
            }
            if end { break }
            if Date() > readDeadline { throw CHMPError.timeout(L("la transferencia de la imagen no terminó")) }
        }

        guard image.count > 2, image[0] == 0xFF, image[1] == 0xD8 else {
            throw CHMPError.protocolError(L("la imagen recibida no es un JPEG válido"))
        }
        return image
    }
}
