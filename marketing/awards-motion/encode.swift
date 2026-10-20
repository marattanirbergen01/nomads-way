// PNG-кадры + WAV → MP4 (H.264 High 4:2:0, 60 fps, AAC 48 кГц).
// swiftc -O encode.swift -o encodebin && ./encodebin <папка_кадров> <audio.wav> <out.mp4>
import AVFoundation
import CoreImage
import ImageIO

let args = CommandLine.arguments
let frameDir = URL(fileURLWithPath: args[1]), wavURL = URL(fileURLWithPath: args[2]), outURL = URL(fileURLWithPath: args[3])
let fps: Int32 = 60
let files = try FileManager.default.contentsOfDirectory(atPath: frameDir.path).filter { $0.hasSuffix(".png") }.sorted()
guard let first = CGImageSourceCreateWithURL(frameDir.appendingPathComponent(files[0]) as CFURL, nil),
      let img0 = CGImageSourceCreateImageAtIndex(first, 0, nil) else { fatalError("нет кадров") }
let w = img0.width, h = img0.height
try? FileManager.default.removeItem(at: outURL)
let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
  AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                              AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                              AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 28_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                    AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalKey: 60, AVVideoAllowFrameReorderingKey: false]])
vIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(vIn)

let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000])
aIn.expectsMediaDataInRealTime = false
writer.add(aIn)
let asset = AVURLAsset(url: wavURL)
let reader = try AVAssetReader(asset: asset)
let aTrack = asset.tracks(withMediaType: .audio)[0]
let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
reader.add(aOut)

writer.startWriting(); reader.startReading()
writer.startSession(atSourceTime: .zero)

// аудио заранее в память: писатель ждёт чередования потоков
var audio: [CMSampleBuffer] = []
while let sb = aOut.copyNextSampleBuffer() { audio.append(sb) }
var ai = 0, audioDone = false
func feedAudio(upTo t: Double) {
  while ai < audio.count && CMSampleBufferGetPresentationTimeStamp(audio[ai]).seconds <= t && aIn.isReadyForMoreMediaData {
    if !aIn.append(audio[ai]) { fatalError("audio append: \(String(describing: writer.error))") }
    ai += 1
  }
  if ai == audio.count && !audioDone { aIn.markAsFinished(); audioDone = true }
}

let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
for (i, f) in files.enumerated() {
  guard let src = CGImageSourceCreateWithURL(frameDir.appendingPathComponent(f) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError(f) }
  while !vIn.isReadyForMoreMediaData { feedAudio(upTo: Double(i) / Double(fps) + 1.0); usleep(500) }
  feedAudio(upTo: Double(i) / Double(fps) + 0.5)
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  let buf = pb!
  CVPixelBufferLockBaseAddress(buf, [])
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  let rowSrc = ctx.bytesPerRow, rowDst = CVPixelBufferGetBytesPerRow(buf)
  let s = ctx.data!.assumingMemoryBound(to: UInt8.self), d = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
  for y in 0..<h { memcpy(d + y * rowDst, s + y * rowSrc, w * 4) }
  CVPixelBufferUnlockBaseAddress(buf, [])
  if !adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) { fatalError("video append \(i): \(String(describing: writer.error))") }
}
vIn.markAsFinished()
while !audioDone { feedAudio(upTo: .infinity); usleep(500) }
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
if writer.status != .completed { fatalError("writer: \(String(describing: writer.error))") }
print("\(outURL.lastPathComponent): \(files.count) кадров \(w)×\(h) @\(fps)")
