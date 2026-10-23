// Format-only preparation of approved artwork: square opaque sRGB PNG, no design redraw.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let size = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 1024
let source = CGImageSourceCreateWithURL(input as CFURL,nil)!
let image = CGImageSourceCreateImageAtIndex(source,0,nil)!
precondition(image.width == image.height,"Icon must be square")
let context = CGContext(data: nil,width: size,height: size,bitsPerComponent: 8,bytesPerRow: size * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high
context.draw(image,in: CGRect(x: 0,y: 0,width: size,height: size))
let destination = CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
precondition(CGImageDestinationFinalize(destination),"PNG export failed")
// ImageIO adds an ancillary EXIF block even with empty source metadata. Strip it
// structurally; the pixels and all color information remain untouched.
let png = try Data(contentsOf: output)
var clean = Data(png.prefix(8)); var offset = 8
while offset + 12 <= png.count {
    let length = png[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    let end = offset + length + 12
    if String(data: png[(offset + 4)..<(offset + 8)],encoding: .ascii) != "eXIf" { clean.append(png[offset..<end]) }
    offset = end
}
try clean.write(to: output)
