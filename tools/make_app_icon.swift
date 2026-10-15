// Renders the 1024×1024 app icon: a road bike riding over an elevation profile.
// Usage: swift tools/make_app_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make_app_icon.swift <output.png>\n".utf8))
    exit(64)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create bitmap context") }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Background: night-sky navy.
linearGradient([color(0x1B2A4A), color(0x0B1020)], from: CGPoint(x: 0, y: 1024), to: CGPoint(x: 0, y: 0))

// Elevation profile, echoing the in-app charts.
// The tyres rest on the ridge at x = 272 and 752 (wheel bottoms at y = 390).
let profile: [CGPoint] = [
    (0, 250), (110, 300), (190, 360), (272, 390), (372, 404), (512, 440),
    (652, 404), (752, 390), (850, 330), (940, 280), (1024, 300),
].map { CGPoint(x: $0.0, y: $0.1) }

let area = CGMutablePath()
area.move(to: CGPoint(x: 0, y: 0))
profile.forEach { area.addLine(to: $0) }
area.addLine(to: CGPoint(x: 1024, y: 0))
area.closeSubpath()
ctx.saveGState()
ctx.addPath(area)
ctx.clip()
linearGradient([color(0xFF8A1F), color(0xFF5E1F, alpha: 0.35)], from: CGPoint(x: 0, y: 430), to: CGPoint(x: 0, y: 0))
ctx.restoreGState()

let ridge = CGMutablePath()
ridge.addLines(between: profile)
ctx.addPath(ridge)
ctx.setStrokeColor(color(0xFFC07A))
ctx.setLineWidth(14)
ctx.setLineJoin(.round)
ctx.strokePath()

// The bike, in white with round caps so it stays legible at small sizes.
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let wheelRadius: CGFloat = 170
let rear = CGPoint(x: 272, y: 560)
let front = CGPoint(x: 752, y: 560)
ctx.setLineWidth(42)
for hub in [rear, front] {
    ctx.addEllipse(in: CGRect(x: hub.x - wheelRadius, y: hub.y - wheelRadius, width: wheelRadius * 2, height: wheelRadius * 2))
}
ctx.strokePath()

let bottomBracket = CGPoint(x: 482, y: 560)
let seatCluster = CGPoint(x: 440, y: 770)
let headTop = CGPoint(x: 668, y: 780)
let headBottom = CGPoint(x: 688, y: 712)

func stroke(_ points: [CGPoint], width: CGFloat) {
    ctx.setLineWidth(width)
    ctx.addLines(between: points)
    ctx.strokePath()
}

stroke([rear, bottomBracket, seatCluster, rear], width: 34)          // chainstay, seat tube, seat stay
stroke([seatCluster, headTop], width: 38)                            // top tube
stroke([bottomBracket, headBottom], width: 40)                       // down tube
stroke([headTop, headBottom, front], width: 36)                      // head tube and fork
stroke([seatCluster, CGPoint(x: 428, y: 822)], width: 30)            // seat post
stroke([CGPoint(x: 372, y: 832), CGPoint(x: 486, y: 832)], width: 34) // saddle
stroke([headTop, CGPoint(x: 690, y: 832), CGPoint(x: 770, y: 840)], width: 30) // stem and bar
stroke([CGPoint(x: 770, y: 840), CGPoint(x: 792, y: 800), CGPoint(x: 770, y: 768)], width: 26) // drop

// Chainring and crank, with an orange hub to tie in the profile colour.
ctx.setLineWidth(22)
ctx.addEllipse(in: CGRect(x: bottomBracket.x - 44, y: bottomBracket.y - 44, width: 88, height: 88))
ctx.strokePath()
stroke([bottomBracket, CGPoint(x: 530, y: 486)], width: 26)
ctx.setFillColor(color(0xFF8A1F))
for hub in [rear, front] {
    ctx.fillEllipse(in: CGRect(x: hub.x - 22, y: hub.y - 22, width: 44, height: 44))
}

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not create PNG destination") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write PNG") }
