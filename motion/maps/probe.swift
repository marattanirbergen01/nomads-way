// Проверка сдачи карты: ./probebin <file.mp4> <last.png> <папка_стоп-кадров>
// параметры потока, faststart, размер файла, последний кадр против PNG, неподвижность конца, стоп-кадры.
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments, url = URL(fileURLWithPath: a[1]), pngURL = URL(fileURLWithPath: a[2]), dir = URL(fileURLWithPath: a[3])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let fourcc = { (c: FourCharCode) in String(bytes: [24, 16, 8, 0].map { UInt8((c >> $0) & 255) }, encoding: .ascii)! }
let data = try Data(contentsOf: url)
// порядок атомов верхнего уровня
var atoms: [String] = [], off = 0
while off + 8 <= data.count {
  var size = Int(data[off..<off + 4].reduce(0) { $0 << 8 | UInt32($1) }); let type = String(bytes: data[off + 4..<off + 8], encoding: .ascii) ?? "?"
  if size == 1 { size = Int(data[off + 8..<off + 16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) }
  atoms.append(type); if size < 8 { break }; off += size
}
let faststart = (atoms.firstIndex(of: "moov") ?? 99) < (atoms.firstIndex(of: "mdat") ?? -1)
let asset = AVURLAsset(url: url)
let vt = asset.tracks(withMediaType: .video), at = asset.tracks(withMediaType: .audio)
let v = vt[0], vf = v.formatDescriptions[0] as! CMFormatDescription
print("файл: \(url.lastPathComponent), \(String(format: "%.2f", Double(data.count) / 1_048_576)) МБ \(data.count <= 3 * 1_048_576 ? "✓ ≤ 3 МБ" : "✗ > 3 МБ")")
print("атомы: \(atoms.joined(separator: " ")) → faststart \(faststart ? "✓" : "✗")")
print("видео: \(fourcc(CMFormatDescriptionGetMediaSubType(vf))) \(Int(v.naturalSize.width))×\(Int(v.naturalSize.height)), \(v.nominalFrameRate) fps, длительность \(String(format: "%.4f", asset.duration.seconds)) с; аудиодорожек: \(at.count) \(at.isEmpty ? "✓" : "✗")")

// все кадры: число, шаг, формат; RGB для сравнения — через тот же декодер (AVAssetImageGenerator)
let r = try AVAssetReader(asset: asset)
let vo = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]); r.add(vo); r.startReading()
var pts: [Double] = [], pix = ""
while let sb = vo.copyNextSampleBuffer() { if pts.isEmpty, let ib = CMSampleBufferGetImageBuffer(sb) { pix = fourcc(CVPixelBufferGetPixelFormatType(ib)) }; pts.append(CMSampleBufferGetPresentationTimeStamp(sb).seconds) }
let steps = zip(pts.dropFirst(), pts).map { $0 - $1 }
print("кадров: \(pts.count), шаг \(String(format: "%.5f…%.5f", steps.min()!, steps.max()!)) с, декод \(pix) (4:2:0)")

func rgba(_ img: CGImage) -> [UInt8] {
  let w = img.width, h = img.height; var buf = [UInt8](repeating: 0, count: w * h * 4)
  let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return buf
}
func diff(_ x: [UInt8], _ y: [UInt8]) -> (Double, Int) {
  var s = 0, m = 0; for i in 0..<x.count where i % 4 != 3 { let d = abs(Int(x[i]) - Int(y[i])); s += d; m = max(m, d) }
  return (Double(s) / Double(x.count / 4 * 3), m)
}
let gen = AVAssetImageGenerator(asset: asset); gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
func frame(_ t: Double) throws -> CGImage { try gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) }
let lastT = pts.last!
let last = try frame(lastT)
let png = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pngURL as CFURL, nil)!, 0, nil)!
let pAlpha = png.alphaInfo
let (dm, dx) = diff(rgba(last), rgba(png))
print(String(format: "последний кадр против PNG: средняя разница %.3f, макс %d %@; PNG %d×%d, альфа: %@", dm, dx, dm <= 1 ? "✓" : "✗", png.width, png.height, [.none, .noneSkipLast, .noneSkipFirst].contains(pAlpha) ? "нет ✓" : "есть ✗"))
let f31 = rgba(try frame(3.1)), f33 = rgba(try frame(3.3)), fl = rgba(last)
let (a1, m1) = diff(f31, f33), (a2, m2) = diff(f33, fl)
print(String(format: "неподвижность: 3,1↔3,3 %.3f (макс %d), 3,3↔%.3f %.3f (макс %d) %@", a1, m1, lastT, a2, m2, a1 < 0.5 && a2 < 0.5 ? "✓" : "✗"))
for t in [0.5, 1.5, 2.5, lastT] {
  let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(String(format: "t%.2f.png", t)) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(d, try frame(t), nil); CGImageDestinationFinalize(d)
}
