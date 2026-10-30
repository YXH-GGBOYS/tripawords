// Turn Han's logo into a square transparent master and an opaque 1024 App Store icon.
//   swift scripts/make_logo.swift <logo-in> <transparent-square.png> <app-icon-1024.png>
//
// Background removal: flood-fill the near-white pixels connected to the image border, so white
// inside the drawing (eyes, book pages) stays. Light-grey anti-aliasing next to the removed area
// becomes partially transparent black, which keeps outlines smooth without a white halo.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4 else {
    print("usage: make_logo.swift <in> <transparent.png> <icon1024.png>")
    exit(2)
}

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("cannot read \(path)"); exit(1)
    }
    return img
}

func save(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("cannot write \(path)"); exit(1)
    }
    CGImageDestinationAddImage(dst, image, nil)
    CGImageDestinationFinalize(dst)
}

func rgbaContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let source = load(args[1])
let side = max(source.width, source.height)
let ctx = rgbaContext(side, side)
// White square canvas with the logo centred, so the flood fill sees one connected background.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
ctx.draw(source, in: CGRect(x: (side - source.width) / 2, y: (side - source.height) / 2,
                            width: source.width, height: source.height))

let px = ctx.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
func luma(_ i: Int) -> Int { (Int(px[i]) * 299 + Int(px[i + 1]) * 587 + Int(px[i + 2]) * 114) / 1000 }
func isWhite(_ i: Int) -> Bool { px[i] >= 232 && px[i + 1] >= 232 && px[i + 2] >= 232 }

var removed = [Bool](repeating: false, count: side * side)
var stack: [Int] = []
for x in 0..<side { stack.append(x); stack.append((side - 1) * side + x) }
for y in 0..<side { stack.append(y * side); stack.append(y * side + side - 1) }
while let p = stack.popLast() {
    if removed[p] || !isWhite(p * 4) { continue }
    removed[p] = true
    let x = p % side, y = p / side
    if x > 0 { stack.append(p - 1) }
    if x < side - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - side) }
    if y < side - 1 { stack.append(p + side) }
}

let edgeLight = 150  // lighter than this, next to removed background, is an anti-aliasing halo
for p in 0..<(side * side) {
    let i = p * 4
    if removed[p] {
        px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
        continue
    }
    let x = p % side, y = p / side
    let touches = (x > 0 && removed[p - 1]) || (x < side - 1 && removed[p + 1])
        || (y > 0 && removed[p - side]) || (y < side - 1 && removed[p + side])
    let l = luma(i)
    if touches, l > edgeLight {
        // Grey halo pixel: keep it as black with alpha proportional to its darkness.
        let a = UInt8(max(0, min(255, (255 - l) * 255 / (255 - edgeLight))))
        px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = a
    }
}
save(ctx.makeImage()!, args[2])

// App icon: opaque (App Store rejects transparent icons), white background, small margin.
let icon = rgbaContext(1024, 1024)
icon.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
icon.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
icon.interpolationQuality = .high
let inset: CGFloat = 40
icon.draw(ctx.makeImage()!, in: CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset))
let opaque = icon.makeImage()!
// Drop the alpha channel entirely.
let flat = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(opaque, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
save(flat.makeImage()!, args[3])
print("ok: \(side)x\(side) transparent master, 1024 opaque icon")
