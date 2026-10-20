// PNG-кадры → MP4 без звука (H.264 High 4:2:0, moov в начале файла).
// swiftc -O encode.swift -o encodebin && ./encodebin <папка_кадров> <out.mp4> <last.png> [fps=30] [бит/с=5000000]
// Поток помечен sRGB (передаточная функция IEC 61966-2-1): декодированный кадр совпадает с PNG, без «осветления» BT.709.
import AVFoundation
import ImageIO

let args = CommandLine.arguments
let frameDir = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2]), pngURL = URL(fileURLWithPath: args[3])
let fps = Int32(args.count > 4 ? args[4] : "30")!, bitrate = Int(args.count > 5 ? args[5] : "5000000")!
let files = try FileManager.default.contentsOfDirectory(atPath: frameDir.path).filter { $0.hasSuffix(".png") }.sorted()
guard let first = CGImageSourceCreateWithURL(frameDir.appendingPathComponent(files[0]) as CFURL, nil),
      let img0 = CGImageSourceCreateImageAtIndex(first, 0, nil) else { fatalError("нет кадров") }
let w = img0.width, h = img0.height
try? FileManager.default.removeItem(at: outURL)
let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true   // faststart: moov перед mdat

let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
  AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                              AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                              AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                    AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalKey: Int(fps), AVVideoAllowFrameReorderingKey: false]])
vIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(vIn)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
for (i, f) in files.enumerated() {
  guard let src = CGImageSourceCreateWithURL(frameDir.appendingPathComponent(f) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError(f) }
  while !vIn.isReadyForMoreMediaData { usleep(500) }
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  let buf = pb!
  CVPixelBufferLockBaseAddress(buf, [])
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  let rowSrc = ctx.bytesPerRow, rowDst = CVPixelBufferGetBytesPerRow(buf)
  let s = ctx.data!.assumingMemoryBound(to: UInt8.self), d = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
  for y in 0..<h { memcpy(d + y * rowDst, s + y * rowSrc, w * 4) }
  CVPixelBufferUnlockBaseAddress(buf, [])
  if !adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) { fatalError("append \(i): \(String(describing: writer.error))") }
}
vIn.markAsFinished()
// последний кадр → PNG RGB без альфы, тот же растр, что ушёл в кодер
if let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(pngURL as CFURL, "public.png" as CFString, 1, nil) {
  CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
if writer.status != .completed { fatalError("writer: \(String(describing: writer.error))") }
print("\(outURL.lastPathComponent): \(files.count) кадров \(w)×\(h) @\(fps)")
