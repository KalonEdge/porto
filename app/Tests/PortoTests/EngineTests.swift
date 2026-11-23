import Foundation
import Testing
@testable import Porto

struct EngineTests {
    @Test func watchesVersionedInterpreters() {
        let allowlist = Preferences.defaultAllowlist
        for name in ["node", "python3", "python3.12", "Python", "ruby3.3", "php8.3", "bun", "deno", "postgres16"] {
            #expect(ScanEngine.isWatched(name, in: allowlist), "\(name)")
        }
        for name in ["Safari", "rapportd", "ControlCenter", "3", "node-helper", "Xcode26"] {
            #expect(!ScanEngine.isWatched(name, in: allowlist), "\(name)")
        }
        #expect(ScanEngine.isWatched("ruby3.4", in: ["ruby"]))
        #expect(!ScanEngine.isWatched("ruby3.4", in: ["node"]))
    }

    @Test func formatsMemory() {
        #expect(Format.bytesString(184 * 1_048_576) == "184 MB")
        #expect(Format.bytesString(UInt64(1.21 * 1_073_741_824)) == "1.21 GB")
        #expect(Format.totalString(16 * 1_073_741_824) == "16 GB")
        #expect(Format.totalString(UInt64(4.9 * 1_073_741_824)) == "4.9 GB")
        #expect(Format.totalString(612 * 1_048_576) == "612 MB")
        #expect(Format.trim(2) == "2")
        #expect(Format.trim(1.5) == "1.5")
    }

    @Test func formatsTimeAndLoad() {
        #expect(Format.duration(20) == "<1m")
        #expect(Format.duration(12 * 60) == "12m")
        #expect(Format.duration(3 * 3600 + 12 * 60) == "3h 12m")
        #expect(Format.duration(3 * 3600) == "3h")
        #expect(Format.duration(50 * 3600) == "2d")
        #expect(Format.shortDuration(10) == "1m")
        #expect(Format.shortDuration(3 * 3600 + 59 * 60) == "3h")
        #expect(Format.percent(0) == "0%")
        #expect(Format.percent(0.05) == "<0.1%")
        #expect(Format.percent(0.3) == "0.3%")
        #expect(Format.percent(42.4) == "42%")
    }

    @Test func readsThisProcessFromTheKernel() throws {
        let pid = getpid()
        #expect(ProcessTable.isAlive(pid))
        let path = try #require(ProcessTable.executablePath(pid))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        #expect(ProcessTable.all()[pid] != nil)
        #expect(ProcessTable.systemMemory().total > 1_073_741_824)
    }

    @Test func findsAListeningSocket() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #expect(socket >= 0)
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        #expect(listen(socket, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            _ = $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))

        let listener = try #require(ProcessTable.tcpSockets(getpid()).first { $0.localPort == port })
        #expect(listener.state == .listening)
        #expect(listener.localAddress == "127.0.0.1")
    }
}
