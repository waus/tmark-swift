import Foundation
import Testing
@testable import TMarkSwiftUI

@Test func imageWhitelistUsesContent() throws {
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII="))
    let gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
    #expect(MediaFormats.allowsImage(png))
    #expect(!MediaFormats.allowsImage(gif))
    #expect(!MediaFormats.allowsImage(Data("{\"v\":\"5.0\",\"layers\":[]}".utf8)))
}

@Test func oggWhitelistRequiresOpusIdentification() {
    func ogg(firstPacket: [UInt8]) -> Data {
        var header = [UInt8](repeating: 0, count: 28)
        header.replaceSubrange(0..<4, with: "OggS".utf8)
        header[5] = 2
        header[26] = 1
        header[27] = UInt8(firstPacket.count)
        return Data(header + firstPacket)
    }
    let opus = Array("OpusHead".utf8) + [1, 2, 0, 0, 0x80, 0xbb, 0, 0, 0, 0, 0]
    #expect(MediaFormats.allowsAudio(ogg(firstPacket: opus)))
    #expect(!MediaFormats.allowsAudio(ogg(firstPacket: [1] + Array("vorbis".utf8) + [UInt8](repeating: 0, count: 20))))
    #expect(!MediaFormats.allowsAudio(ogg(firstPacket: [0x7f] + Array("FLAC".utf8) + [UInt8](repeating: 0, count: 20))))
    #expect(!MediaFormats.allowsAudio(Data("OggS".utf8)))
    #expect(!MediaFormats.allowsAudio(Data()))
}
