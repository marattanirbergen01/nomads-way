// Проверка готового MP4: параметры потоков, число кадров, громкость, кадры в PNG.
// ./probebin <file.mp4> <папка_для_кадров> <t1,t2,...>
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments, url = URL(fileURLWithPath: a[1]), dir = URL(fileURLWithPath: a[2])
let times = a[3].split(separator: ",").compactMap { Double($0) }
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let asset = AVURLAsset(url: url)
let v = asset.tracks(withMediaType: .video)[0], au = asset.tracks(withMediaType: .audio)[0]
let vf = v.formatDescriptions[0] as! CMFormatDescription, af = au.formatDescriptions[0] as! CMFormatDescription
let fourcc = { (c: FourCharCode) in String(bytes: [24, 16, 8, 0].map { UInt8((c >> $0) & 255) }, encoding: .ascii)! }
let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(af)!.pointee
print("файл: \(url.lastPathComponent), длительность \(String(format: "%.4f", asset.duration.seconds)) с")
print("видео: \(fourcc(CMFormatDescriptionGetMediaSubType(vf))) \(Int(v.naturalSize.width))×\(Int(v.naturalSize.height)), nominal \(v.nominalFrameRate) fps, \(String(format: "%.2f", v.estimatedDataRate / 1e6)) Мбит/с")
print("аудио: \(fourcc(asbd.mFormatID)) \(Int(asbd.mSampleRate)) Гц × \(asbd.mChannelsPerFrame), длительность \(String(format: "%.4f", au.timeRange.duration.seconds)) с")

// кадры и шаг времени
let r = try AVAssetReader(asset: asset)
let vo = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
let ao = AVAssetReaderTrackOutput(track: au, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
r.add(vo); r.add(ao); r.startReading()
var n = 0, pts: [Double] = [], pixfmt = ""
while let sb = vo.copyNextSampleBuffer() {
  if n == 0, let ib = CMSampleBufferGetImageBuffer(sb) { pixfmt = fourcc(CVPixelBufferGetPixelFormatType(ib)) }
  pts.append(CMSampleBufferGetPresentationTimeStamp(sb).seconds); n += 1
}
let steps = zip(pts.dropFirst(), pts).map { $0 - $1 }
print("кадров: \(n), шаг мин/макс \(String(format: "%.5f/%.5f", steps.min()!, steps.max()!)) с, декод в \(pixfmt) (4:2:0)")
var peak: Float = 0, sum: Double = 0, cnt = 0, win: [Double] = Array(repeating: 0, count: 27)
while let sb = ao.copyNextSampleBuffer() {
  let t0 = CMSampleBufferGetPresentationTimeStamp(sb).seconds
  var bl: CMBlockBuffer? ; var abl = AudioBufferList()
  CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: nil, bufferListOut: &abl, bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &bl)
  let p = abl.mBuffers.mData!.assumingMemoryBound(to: Float.self), m = Int(abl.mBuffers.mDataByteSize) / 4
  for i in 0..<m { let x = p[i]; peak = max(peak, abs(x)); sum += Double(x * x); cnt += 1
    let w = Int((t0 + Double(i / 2) / 48000) * 10); if w >= 0 && w < win.count { win[w] = max(win[w], Double(abs(x))) } }
}
print(String(format: "аудио: пик %.2f dBFS, RMS %.1f dBFS", 20 * log10(Double(peak)), 10 * log10(sum / Double(cnt))))
print("пики по 0,1 с: " + win.map { String(format: "%.2f", $0) }.joined(separator: " "))

let gen = AVAssetImageGenerator(asset: asset); gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
for t in times {
  let img = try gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
  let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(String(format: "t%.3f.png", t)) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
