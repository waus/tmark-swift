import Foundation
import AudioToolbox
import ImageIO

/// Validate decoded types, not filename extensions (which are only examples in the spec).
enum MediaFormats {
    static func allowsImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { return false }
        return ["public.jpeg", "public.png", "org.webmproject.webp", "public.avif", "public.jpeg-xl"].contains(type)
    }

    static func allowsAudio(_ data: Data) -> Bool {
        // Ogg's first packet must be the Opus identification header, not Vorbis or FLAC.
        if data.starts(with: Data("OggS".utf8)) {
            guard data.count >= 28, data[4] == 0, data[5] & 2 != 0 else { return false }
            let segments = Int(data[26])
            let offset = 27 + segments
            guard segments > 0, data.count >= offset + 19,
                  data[27] >= 19 else { return false }
            return data[offset..<(offset + 8)].elementsEqual("OpusHead".utf8)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        do { try data.write(to: url) } catch { return false }
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr,
              let file else { return false }
        defer { AudioFileClose(file) }
        var container: AudioFileTypeID = 0
        var containerSize = UInt32(MemoryLayout.size(ofValue: container))
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout.size(ofValue: format))
        guard AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &containerSize, &container) == noErr,
              AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &formatSize, &format) == noErr
        else { return false }
        switch container {
        case kAudioFileMP3Type: return format.mFormatID == kAudioFormatMPEGLayer3
        case kAudioFileFLACType: return format.mFormatID == kAudioFormatFLAC
        case kAudioFileM4AType, kAudioFileMPEG4Type:
            // The basic format can report AAC even for HE-AAC. The format list
            // puts the full profile first, followed by compatibility fallbacks.
            var size: UInt32 = 0
            guard AudioFileGetPropertyInfo(file, kAudioFilePropertyFormatList, &size, nil) == noErr,
                  size >= MemoryLayout<AudioFormatListItem>.size else { return false }
            var formats = [AudioFormatListItem](
                repeating: AudioFormatListItem(),
                count: Int(size) / MemoryLayout<AudioFormatListItem>.size
            )
            let status = formats.withUnsafeMutableBytes { buffer in
                AudioFileGetProperty(file, kAudioFilePropertyFormatList, &size, buffer.baseAddress!)
            }
            return status == noErr && formats[0].mASBD.mFormatID == kAudioFormatMPEG4AAC
        default: return false
        }
    }
}
