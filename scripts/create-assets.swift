import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("HeartAdoption/Assets.xcassets")
let fm = FileManager.default
try fm.createDirectory(at: root, withIntermediateDirectories: true)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let iconDir = root.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let blue = CGColor(red: 34/255, green: 77/255, blue: 199/255, alpha: 1)
context.setFillColor(blue); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let heart = CGMutablePath()
heart.move(to: CGPoint(x: 512, y: 200))
heart.addCurve(to: CGPoint(x: 200, y: 590), control1: CGPoint(x: 390, y: 310), control2: CGPoint(x: 200, y: 400))
heart.addCurve(to: CGPoint(x: 512, y: 700), control1: CGPoint(x: 200, y: 810), control2: CGPoint(x: 410, y: 850))
heart.addCurve(to: CGPoint(x: 824, y: 590), control1: CGPoint(x: 620, y: 850), control2: CGPoint(x: 824, y: 810))
heart.addCurve(to: CGPoint(x: 512, y: 200), control1: CGPoint(x: 824, y: 400), control2: CGPoint(x: 634, y: 310))
context.setFillColor(CGColor(gray: 1, alpha: 1)); context.addPath(heart); context.fillPath()
context.setFillColor(blue); context.fillEllipse(in: CGRect(x: 400, y: 370, width: 224, height: 180))
for (x, y, w, h) in [(339.0, 548.0, 82.0, 105.0), (441, 602, 82, 110), (546, 602, 82, 110), (644, 548, 82, 105)] { context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h)) }
let destination = CGImageDestinationCreateWithURL(iconDir.appendingPathComponent("AppIcon.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write app icon") }
try "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: iconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let colorDir = root.appendingPathComponent("LaunchBackground.colorset")
try fm.createDirectory(at: colorDir, withIntermediateDirectories: true)
try "{\"colors\":[{\"idiom\":\"universal\",\"color\":{\"color-space\":\"srgb\",\"components\":{\"red\":\"0.961\",\"green\":\"0.973\",\"blue\":\"0.988\",\"alpha\":\"1.0\"}}}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: colorDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
