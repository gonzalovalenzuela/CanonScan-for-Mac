// ESCLServer.swift
// Servidor eSCL (AirScan) que traduce los trabajos de macOS a CHMP.
// eSCL (AirScan) server that translates macOS scan jobs to CHMP.

import Foundation
import Network

/// Trabajo de escaneo eSCL / eSCL scan job
final class ESCLJob {
    let id = UUID().uuidString.lowercased()
    let settings: ScanSettings
    let region: (x: Int, y: Int, w: Int, h: Int)?
    let created = Date()
    var data: Data?
    var error: Error?
    var delivered = false
    var cancelled = false
    let done = DispatchSemaphore(value: 0)

    init(settings: ScanSettings, region: (x: Int, y: Int, w: Int, h: Int)?) {
        self.settings = settings
        self.region = region
    }

    var finished: Bool { data != nil || error != nil || cancelled }
}

final class ESCLServer {
    /// Cambios de estado para la barra de menú / State changes for the menu bar
    var onActivity: ((Bool) -> Void)?

    private let printerHost: String
    private let serviceName: String
    private let deviceUUID: String
    private var listener: NWListener?
    private var jobs = [String: ESCLJob]()
    private let lock = NSLock()
    private var closeAfter = [ObjectIdentifier: Bool]()
    private let scanQueue = DispatchQueue(label: "cl.local.canonscan.bridge.scan")   // uno a la vez / one at a time
    private let netQueue = DispatchQueue(label: "cl.local.canonscan.bridge.net", attributes: .concurrent)

    init(printerHost: String, serviceName: String) {
        self.printerHost = printerHost
        self.serviceName = serviceName
        // UUID estable por impresora / Stable UUID per printer
        let key = "bridgeUUID-\(printerHost)"
        if let saved = SharedSettings.defaults.string(forKey: key) {
            deviceUUID = saved
        } else {
            deviceUUID = UUID().uuidString.lowercased()
            SharedSettings.defaults.set(deviceUUID, forKey: key)
        }
    }

    // MARK: - Ciclo de vida / Lifecycle

    func start() throws {
        let l = try NWListener(using: .tcp, on: .any)   // puerto elegido por el sistema / system-chosen port
        let txt: [String: String] = [
            "txtvers": "1", "vers": "2.63", "rs": "eSCL", "ty": serviceName,
            "representation": "", "pdl": "image/jpeg", "cs": "color,grayscale", "is": "platen",
            "duplex": "F", "uuid": deviceUUID, "note": "CanonScan",
        ]
        l.service = NWListener.Service(name: serviceName, type: "_uscan._tcp", domain: nil, txtRecord: NWTXTRecord(txt))
        l.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            c.start(queue: self.netQueue)
            self.receive(c)
        }
        l.start(queue: netQueue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        jobs.values.forEach { $0.cancelled = true }
        lock.unlock()
    }

    // MARK: - HTTP

    private func receive(_ c: NWConnection, buffer: Data = Data()) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, complete, err in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }
            // Se mide en bytes / Measured in bytes
            if let headEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<headEnd.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let parts = lines[0].split(separator: " ")
                var headers = [String: String]()
                for l in lines.dropFirst() {
                    if let i = l.firstIndex(of: ":") {
                        headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    }
                }
                let len = Int(headers["content-length"] ?? "0") ?? 0
                if buf.endIndex - headEnd.upperBound >= len, parts.count >= 2 {
                    self.lock.lock()
                    self.closeAfter[ObjectIdentifier(c)] = headers["connection"]?.lowercased() == "close"
                    self.lock.unlock()
                    let body = String(decoding: buf[headEnd.upperBound...], as: UTF8.self)
                    self.handle(method: String(parts[0]), path: String(parts[1]), body: body, c)
                    return
                }
            }
            if complete || err != nil {
                self.lock.lock(); self.closeAfter[ObjectIdentifier(c)] = nil; self.lock.unlock()
                c.cancel()
                return
            }
            self.receive(c, buffer: buf)
        }
    }

    private func respond(_ c: NWConnection, _ code: Int, _ reason: String, type: String? = nil,
                         body: Data = Data(), extra: [String: String] = [:]) {
        lock.lock(); let close = closeAfter[ObjectIdentifier(c)] ?? false; lock.unlock()
        var h = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: \(body.count)\r\n"
            + "Connection: \(close ? "close" : "keep-alive")\r\nServer: CanonScan\r\n"
        if let type { h += "Content-Type: \(type)\r\n" }
        for (k, v) in extra { h += "\(k): \(v)\r\n" }
        h += "\r\n"
        c.send(content: Data(h.utf8) + body, completion: .contentProcessed { [weak self] _ in
            if close { c.cancel() } else { self?.receive(c) }   // keep-alive: siguiente pedido / next request
        })
    }

    private func handle(method: String, path rawPath: String, body: String, _ c: NWConnection) {
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let comps = path.split(separator: "/").map(String.init)   // ["eSCL","ScanJobs",id,"NextDocument"]
        switch (method, path) {
        case ("GET", "/eSCL/ScannerCapabilities"):
            respond(c, 200, "OK", type: "text/xml", body: Data(capabilitiesXML().utf8))
        case ("GET", "/eSCL/ScannerStatus"):
            respond(c, 200, "OK", type: "text/xml", body: Data(statusXML().utf8))
        case ("POST", "/eSCL/ScanJobs"):
            let job = makeJob(from: body)
            lock.lock()
            // Olvida trabajos de hace más de 10 minutos / Forget jobs older than 10 minutes
            jobs = jobs.filter { Date().timeIntervalSince($0.value.created) < 600 }
            jobs[job.id] = job
            lock.unlock()
            runScan(job)
            respond(c, 201, "Created", extra: ["Location": "/eSCL/ScanJobs/\(job.id)"])
        case ("GET", _) where comps.count == 4 && comps[1] == "ScanJobs" && comps[3] == "NextDocument":
            lock.lock(); let job = jobs[comps[2]]; lock.unlock()
            guard let job, !job.delivered, !job.cancelled else { respond(c, 404, "Not Found"); return }
            // Espera el escaneo sin bloquear la cola de red / Wait for the scan off the network queue
            DispatchQueue.global().async {
                job.done.wait(); job.done.signal()
                if let data = job.data {
                    job.delivered = true
                    self.respond(c, 200, "OK", type: "image/jpeg", body: data)
                } else {
                    // Aborta para que macOS muestre el error / Abort so macOS shows the error
                    self.respond(c, 500, "Internal Server Error")
                }
            }
        case ("DELETE", _) where comps.count == 3 && comps[1] == "ScanJobs":
            lock.lock()
            if let job = jobs[comps[2]], !job.delivered { job.cancelled = true }
            lock.unlock()
            respond(c, 200, "OK")
        default:
            respond(c, 404, "Not Found")
        }
    }

    // MARK: - Escaneo / Scanning

    private func makeJob(from xml: String) -> ESCLJob {
        let dpi = Int(Self.value("XResolution", in: xml) ?? "") ?? 300
        let snapped = [150, 300, 600].min { abs($0 - dpi) < abs($1 - dpi) }!
        let gray = (Self.value("ColorMode", in: xml) ?? "RGB24").hasPrefix("Grayscale")
        var region: (x: Int, y: Int, w: Int, h: Int)?
        if let w = Int(Self.value("Width", in: xml) ?? ""), let h = Int(Self.value("Height", in: xml) ?? "") {
            region = (Int(Self.value("XOffset", in: xml) ?? "") ?? 0, Int(Self.value("YOffset", in: xml) ?? "") ?? 0, w, h)
        }
        return ESCLJob(settings: ScanSettings(dpi: snapped, grayscale: gray), region: region)
    }

    private func runScan(_ job: ESCLJob) {
        scanQueue.async { [printerHost, weak self] in
            defer { job.done.signal() }
            guard !job.cancelled else { return }   // macOS lo canceló antes / cancelled by macOS
            DispatchQueue.main.async { self?.onActivity?(true) }
            defer { DispatchQueue.main.async { self?.onActivity?(false) } }
            do {
                let jpeg = try CHMPClient.scan(host: printerHost, settings: job.settings,
                                               shouldContinue: { !job.cancelled }, progress: { _ in })
                job.data = Self.postProcess(jpeg, job: job) ?? jpeg
            } catch {
                job.error = error
                NSLog("CanonScan bridge: %@", error.localizedDescription)
            }
        }
    }

    /// Recorta la zona pedida y aplica gris / Crops the requested region and applies gray
    private static func postProcess(_ jpeg: Data, job: ESCLJob) -> Data? {
        guard var img = ImageTools.decode(jpeg) else { return nil }
        if let r = job.region { img = ImageTools.crop(img, dpi: job.settings.dpi, x: r.x, y: r.y, width: r.w, height: r.h) }
        if job.settings.grayscale, let g = ImageTools.toGray(img) { img = g }
        return ImageTools.jpeg(img, dpi: job.settings.dpi)
    }

    private static func value(_ tag: String, in xml: String) -> String? {
        guard let r = xml.range(of: "<[^>/]*:\(tag)>([^<]*)<", options: .regularExpression) else { return nil }
        let m = xml[r]
        guard let open = m.firstIndex(of: ">") else { return nil }
        return String(m[m.index(after: open)..<m.index(before: m.endIndex)])
    }

    // MARK: - XML

    private func capabilitiesXML() -> String {
        let resolutions = [150, 300, 600].map {
            "<scan:DiscreteResolution><scan:XResolution>\($0)</scan:XResolution><scan:YResolution>\($0)</scan:YResolution></scan:DiscreteResolution>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
          <pwg:Version>2.63</pwg:Version>
          <pwg:MakeAndModel>\(serviceName)</pwg:MakeAndModel>
          <pwg:SerialNumber>canonscan</pwg:SerialNumber>
          <scan:UUID>\(deviceUUID)</scan:UUID>
          <scan:Platen>
            <scan:PlatenInputCaps>
              <scan:MinWidth>16</scan:MinWidth>
              <scan:MaxWidth>2480</scan:MaxWidth>
              <scan:MinHeight>16</scan:MinHeight>
              <scan:MaxHeight>3508</scan:MaxHeight>
              <scan:MaxScanRegions>1</scan:MaxScanRegions>
              <scan:SettingProfiles>
                <scan:SettingProfile>
                  <scan:ColorModes>
                    <scan:ColorMode>RGB24</scan:ColorMode>
                    <scan:ColorMode>Grayscale8</scan:ColorMode>
                  </scan:ColorModes>
                  <scan:DocumentFormats>
                    <pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat>
                    <scan:DocumentFormatExt>image/jpeg</scan:DocumentFormatExt>
                  </scan:DocumentFormats>
                  <scan:SupportedResolutions><scan:DiscreteResolutions>\(resolutions)</scan:DiscreteResolutions></scan:SupportedResolutions>
                </scan:SettingProfile>
              </scan:SettingProfiles>
              <scan:SupportedIntents>
                <scan:Intent>Document</scan:Intent>
                <scan:Intent>TextAndGraphic</scan:Intent>
                <scan:Intent>Photo</scan:Intent>
                <scan:Intent>Preview</scan:Intent>
              </scan:SupportedIntents>
              <scan:MaxOpticalXResolution>600</scan:MaxOpticalXResolution>
              <scan:MaxOpticalYResolution>600</scan:MaxOpticalYResolution>
            </scan:PlatenInputCaps>
          </scan:Platen>
        </scan:ScannerCapabilities>
        """
    }

    private func statusXML() -> String {
        lock.lock(); let all = Array(jobs.values); lock.unlock()
        let busy = all.contains { !$0.finished }
        let infos = all.map { j -> String in
            let state: String, reason: String
            if j.cancelled { state = "Canceled"; reason = "JobCanceledByUser" }
            else if j.error != nil { state = "Aborted"; reason = "AbortedBySystem" }
            else if j.delivered { state = "Completed"; reason = "JobCompletedSuccessfully" }
            else { state = "Processing"; reason = "JobScanning" }
            return """
              <scan:JobInfo>
                <pwg:JobUri>/eSCL/ScanJobs/\(j.id)</pwg:JobUri>
                <pwg:JobUuid>\(j.id)</pwg:JobUuid>
                <scan:Age>\(Int(Date().timeIntervalSince(j.created)))</scan:Age>
                <pwg:ImagesCompleted>\(j.delivered ? 1 : 0)</pwg:ImagesCompleted>
                <pwg:ImagesToTransfer>\(j.delivered || j.cancelled || j.error != nil ? 0 : 1)</pwg:ImagesToTransfer>
                <pwg:JobState>\(state)</pwg:JobState>
                <pwg:JobStateReasons><pwg:JobStateReason>\(reason)</pwg:JobStateReason></pwg:JobStateReasons>
              </scan:JobInfo>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScannerStatus xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
          <pwg:Version>2.63</pwg:Version>
          <pwg:State>\(busy ? "Processing" : "Idle")</pwg:State>
          <scan:AdfState>ScannerAdfEmpty</scan:AdfState>
          <scan:Jobs>
        \(infos)
          </scan:Jobs>
        </scan:ScannerStatus>
        """
    }
}
