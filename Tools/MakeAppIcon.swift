#!/usr/bin/env swift
//
//  Generator ikony aplikacji — jedyne źródło prawdy dla icon-1024.png.
//
//  Ikona nie ma pliku SVG, więc geometria żyje tutaj: krzywa to sześcienny
//  Bézier odtworzony z pierwotnej grafiki (błąd RMS ~1 px), kolory zmierzone
//  z tej samej grafiki i zgodne z `Palette`.
//
//  Uruchomienie:
//      swift Tools/MakeAppIcon.swift
//

import AppKit

let canvas: CGFloat = 1024

// ── Kolory ────────────────────────────────────────────────────────────────
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let bgLight = rgb(0xF7F9F4)   // lewy górny róg
let bgDark = rgb(0xE2E7DC)    // prawy dolny róg
let pine = rgb(0x3B7D71)      // kreska trendu
let ochre = rgb(0xD48B26)     // kropka
let halo = rgb(0xD48B26, 0.13) // poświata: ta sama ochra, ledwo widoczna

// ── Geometria (układ „y liczone od góry", płótno 1024) ────────────────────
let strokeWidth: CGFloat = 54
let p0 = CGPoint(x: 140, y: 723.8)
let c1 = CGPoint(x: 375.3, y: 723.8)
let c2 = CGPoint(x: 586.2, y: 409.0)
let p3 = CGPoint(x: 825, y: 371.0)

/// Jedna kropka w ~2/3 długości łuku krzywej.
let dotCenter = CGPoint(x: 591.2, y: 481.0)
let coreRadius: CGFloat = 68
let ringWidth: CGFloat = coreRadius * 11 / 60   // biała obwódka
let haloRadius: CGFloat = coreRadius * 89 / 60

/// Rysunek jest szerszy niż wyższy, więc sam nie stoi na środku płótna —
/// domykamy to wyśrodkowaniem jego bounding boxa i lekkim powiększeniem,
/// żeby zajmował tyle miejsca co poprzednia wersja z czterema kropkami.
let drawingScale: CGFloat = 1.09

// ── Rysowanie ─────────────────────────────────────────────────────────────
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high
ctx.translateBy(x: 0, y: canvas)
ctx.scaleBy(x: 1, y: -1)

ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.clip()
ctx.drawLinearGradient(
    CGGradient(colorsSpace: space, colors: [bgLight, bgDark] as CFArray, locations: [0, 1])!,
    start: .zero, end: CGPoint(x: canvas, y: canvas), options: [])
ctx.restoreGState()

let bounds = CGRect(x: p0.x - strokeWidth / 2, y: p3.y - strokeWidth / 2,
                    width: (p3.x - p0.x) + strokeWidth,
                    height: (p0.y - p3.y) + strokeWidth)

ctx.saveGState()
ctx.translateBy(x: canvas / 2, y: canvas / 2)
ctx.scaleBy(x: drawingScale, y: drawingScale)
ctx.translateBy(x: -bounds.midX, y: -bounds.midY)

let curve = CGMutablePath()
curve.move(to: p0)
curve.addCurve(to: p3, control1: c1, control2: c2)
ctx.setStrokeColor(pine)
ctx.setLineWidth(strokeWidth)
ctx.setLineCap(.round)
ctx.addPath(curve)
ctx.strokePath()

func fillCircle(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
}

fillCircle(dotCenter, haloRadius, halo)
fillCircle(dotCenter, coreRadius + ringWidth, CGColor(gray: 1, alpha: 1))
fillCircle(dotCenter, coreRadius, ochre)
ctx.restoreGState()

// ── Zapis ─────────────────────────────────────────────────────────────────
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
let output = repoRoot
    .appendingPathComponent("Longevity/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("nie udało się utworzyć obrazu") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("zapis PNG nie powiódł się") }
print("zapisano \(output.path)")
