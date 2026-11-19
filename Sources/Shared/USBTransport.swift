// USBTransport.swift
// Transporte USB para el escáner Canon: los mismos mensajes que van dentro de
// CHMP, enviados por los canales bulk de la interfaz del fabricante.
// USB transport for the Canon scanner: the same messages carried inside CHMP,
// sent over the vendor interface's bulk pipes.

import Foundation
import IOKit
import IOUSBHost

/// Impresora Canon conectada por USB / Canon printer connected over USB
struct USBPrinter: Equatable {
    let name: String
    let vendorID: Int
    let productID: Int
    let locationID: Int
}

final class USBTransport {
    static let canonVendorID = 0x04A9

    private let interface: IOUSBHostInterface
    private let pipeOut: IOUSBHostPipe
    private let pipeIn: IOUSBHostPipe

    // MARK: - Búsqueda / Discovery

    /// Busca impresoras Canon con interfaz de escáner (clase 255) conectadas por USB.
    /// Finds Canon printers with a scanner interface (class 255) connected over USB.
    static func connectedPrinters() -> [USBPrinter] {
        var result = [USBPrinter]()
        for service in matchingInterfaces() {
            defer { IOObjectRelease(service) }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }
            let name = property(parent, "USB Product Name") as? String ?? "Canon"
            let pid = property(parent, "idProduct") as? Int ?? 0
            let loc = property(parent, "locationID") as? Int ?? 0
            result.append(USBPrinter(name: "Canon \(name)", vendorID: canonVendorID, productID: pid, locationID: loc))
        }
        return result
    }

    /// Interfaces de clase 255 de Canon / Canon class-255 interfaces
    private static func matchingInterfaces() -> [io_service_t] {
        // idVendor está en el dispositivo padre, no en la interfaz.
        // idVendor lives on the parent device, not on the interface.
        // IOKit no filtra por bInterfaceClass aquí, así que se filtra en el código.
        // IOKit doesn't filter by bInterfaceClass here, so it's filtered in code.
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }
        var out = [io_service_t]()
        while case let s = IOIteratorNext(iter), s != 0 {
            var parent: io_registry_entry_t = 0
            var isCanon = false
            if property(s, "bInterfaceClass") as? Int == 255,
               IORegistryEntryGetParentEntry(s, kIOServicePlane, &parent) == KERN_SUCCESS {
                isCanon = property(parent, "idVendor") as? Int == canonVendorID
                IOObjectRelease(parent)
            }
            if isCanon { out.append(s) } else { IOObjectRelease(s) }
        }
        return out
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: - Conexión / Connection

    init(locationID: Int? = nil) throws {
        let services = Self.matchingInterfaces()
        defer { services.forEach { IOObjectRelease($0) } }
        // Elige la impresora pedida o la primera / Pick the requested printer or the first one
        var chosen: io_service_t?
        for s in services {
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(s, kIOServicePlane, &parent) == KERN_SUCCESS {
                let loc = Self.property(parent, "locationID") as? Int
                IOObjectRelease(parent)
                if locationID == nil || loc == locationID { chosen = s; break }
            }
        }
        guard let service = chosen else { throw CHMPError.connection(L("no hay una impresora Canon conectada por USB")) }

        do {
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw CHMPError.connection(L("no se pudo abrir el escáner USB (¿lo está usando otra app?)"))
        }

        // Busca los canales bulk de entrada y salida / Find the bulk in and out pipes
        var addrIn: Int?, addrOut: Int?
        let config = interface.configurationDescriptor
        let iface = interface.interfaceDescriptor
        var ep = IOUSBGetNextEndpointDescriptor(config, iface, nil)
        while let e = ep {
            let isBulk = (e.pointee.bmAttributes & 0x03) == 0x02
            if isBulk {
                if e.pointee.bEndpointAddress & 0x80 != 0 { addrIn = addrIn ?? Int(e.pointee.bEndpointAddress) }
                else { addrOut = addrOut ?? Int(e.pointee.bEndpointAddress) }
            }
            ep = IOUSBGetNextEndpointDescriptor(config, iface, UnsafePointer(OpaquePointer(e)))
        }
        guard let i = addrIn, let o = addrOut else {
            interface.destroy()
            throw CHMPError.connection(L("el escáner USB no tiene los canales esperados"))
        }
        pipeIn = try interface.copyPipe(withAddress: i)
        pipeOut = try interface.copyPipe(withAddress: o)
    }

    func close() {
        interface.destroy()
    }

    deinit { close() }

    // MARK: - Intercambio / Exchange

    /// Envía un mensaje y lee la respuesta completa.
    /// Sends a message and reads the full response.
    func exchange(_ body: [UInt8], timeout: TimeInterval = 20) throws -> [UInt8] {
        let out = NSMutableData(bytes: body, length: body.count)
        var sent = 0
        do {
            try pipeOut.__sendIORequest(with: out, bytesTransferred: &sent, completionTimeout: timeout)
        } catch {
            throw CHMPError.connection(L("envío fallido (%@)", error.localizedDescription))
        }

        var response = try readOnce(timeout: timeout)
        // Lectura de imagen (d420): seguir hasta completar el largo declarado.
        // Image read (d420): keep reading until the declared length is complete.
        if body.count >= 2, body[0] == 0xD4, body[1] == 0x20, response.count >= 16, response[0] == 0x06 {
            let len = Int(response[12]) << 24 | Int(response[13]) << 16 | Int(response[14]) << 8 | Int(response[15])
            while response.count < 16 + len {
                let more = try readOnce(timeout: timeout)
                if more.isEmpty { break }
                response += more
            }
        }
        return response
    }

    private func readOnce(timeout: TimeInterval) throws -> [UInt8] {
        let buf = NSMutableData(length: 65536 + 16)!
        var got = 0
        do {
            try pipeIn.__sendIORequest(with: buf, bytesTransferred: &got, completionTimeout: timeout)
        } catch {
            throw CHMPError.timeout(L("sin respuesta de la impresora"))
        }
        return [UInt8](UnsafeRawBufferPointer(start: buf.bytes, count: got))
    }
}
