#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate a Ridler app icon: a modern macOS-style icon with a gradient background
// and a stylized "R" with circuit/code motif

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Background: rounded rectangle with gradient
    let cornerRadius = s * 0.22
    let inset = s * 0.02
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Draw shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 0.2, alpha: 1.0))
    context.fillPath()
    context.restoreGState()

    // Gradient background: deep indigo to vibrant blue
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.18, green: 0.12, blue: 0.45, alpha: 1.0),  // Deep indigo
        CGColor(red: 0.22, green: 0.35, blue: 0.72, alpha: 1.0),  // Medium blue
        CGColor(red: 0.15, green: 0.55, blue: 0.85, alpha: 1.0),  // Bright blue
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.5, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: []
        )
    }

    // Subtle grid pattern for tech feel
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
    context.setLineWidth(s * 0.002)
    let gridSpacing = s * 0.08
    var x = gridSpacing
    while x < s {
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: s))
        context.strokePath()
        x += gridSpacing
    }
    var y = gridSpacing
    while y < s {
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: s, y: y))
        context.strokePath()
        y += gridSpacing
    }

    // Draw stylized "R" letter
    let fontSize = s * 0.52
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = "R" as NSString

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = CGRect(
        x: (s - textSize.width) / 2 + s * 0.01,
        y: (s - textSize.height) / 2 - s * 0.02,
        width: textSize.width,
        height: textSize.height
    )

    // Draw text shadow
    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    shadow.set()
    text.draw(in: textRect, withAttributes: attributes)
    context.restoreGState()

    // Draw the "R" with a subtle glow
    let glowAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.3),
        .paragraphStyle: paragraphStyle
    ]
    let glowRect = textRect.offsetBy(dx: 0, dy: s * 0.003)
    text.draw(in: glowRect, withAttributes: glowAttributes)

    // Draw the main "R"
    text.draw(in: textRect, withAttributes: attributes)

    // Draw small circuit dots at corners to suggest autonomy/tech
    let dotRadius = s * 0.012
    let dotColor = CGColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.6)
    context.setFillColor(dotColor)

    let dotPositions = [
        CGPoint(x: s * 0.20, y: s * 0.20),
        CGPoint(x: s * 0.80, y: s * 0.20),
        CGPoint(x: s * 0.20, y: s * 0.80),
        CGPoint(x: s * 0.80, y: s * 0.80),
        CGPoint(x: s * 0.50, y: s * 0.88),
        CGPoint(x: s * 0.50, y: s * 0.12),
    ]

    for pos in dotPositions {
        let dotRect = CGRect(x: pos.x - dotRadius, y: pos.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        context.fillEllipse(in: dotRect)
    }

    // Draw thin connecting lines between some dots
    context.setStrokeColor(CGColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.15))
    context.setLineWidth(s * 0.003)
    // Top line
    context.move(to: CGPoint(x: s * 0.20, y: s * 0.80))
    context.addLine(to: CGPoint(x: s * 0.50, y: s * 0.88))
    context.strokePath()
    context.move(to: CGPoint(x: s * 0.50, y: s * 0.88))
    context.addLine(to: CGPoint(x: s * 0.80, y: s * 0.80))
    context.strokePath()
    // Bottom line
    context.move(to: CGPoint(x: s * 0.20, y: s * 0.20))
    context.addLine(to: CGPoint(x: s * 0.50, y: s * 0.12))
    context.strokePath()
    context.move(to: CGPoint(x: s * 0.50, y: s * 0.12))
    context.addLine(to: CGPoint(x: s * 0.80, y: s * 0.20))
    context.strokePath()

    context.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Error: Failed to create PNG data")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path)")
    } catch {
        print("Error saving \(path): \(error)")
    }
}

// Generate all required sizes for macOS app icon
let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset"

// macOS icon sizes: 16, 32, 128, 256, 512 at 1x and 2x
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in sizes {
    let image = generateIcon(size: entry.pixels)
    let path = "\(iconsetDir)/\(entry.name)"
    savePNG(image, to: path)
}

print("Icon generation complete!")
