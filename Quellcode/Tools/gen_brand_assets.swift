// Erzeugt App-Icon, tvOS-Ebenen und Wortmarke nach dem Brandguide IP Television+ V1.0 (14.11.2026).
// Aufruf: swift Tools/gen_brand_assets.swift <Ausgabeordner>   (aus Quellcode/)
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build-assets")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func context(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    return c
}
func save(_ c: CGContext, _ name: String) {
    let url = out.appendingPathComponent(name)
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil)
    CGImageDestinationFinalize(d)
}
/// Koordinaten wie auf dem Papier: Ursprung oben links, y nach unten.
func flip(_ c: CGContext, _ h: CGFloat) { c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1) }

enum Look { case standard, tinted }

/// Hintergrund: Offwhite #FDFDFC zu #F3F2EE, Glut-Glow oben rechts (Brandguide S. 13).
func drawBackground(_ c: CGContext, rect: CGRect, look: Look, glowAt: CGPoint, glowRadius: CGFloat) {
    switch look {
    case .standard:
        c.drawLinearGradient(gradient([(0, rgb(0xFDFDFC)), (1, rgb(0xF3F2EE))]), start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        c.drawRadialGradient(gradient([(0, rgb(0xFC5F39, 0.62)), (0.55, rgb(0xFC5F39, 0.16)), (1, rgb(0xFC5F39, 0))]), startCenter: glowAt, startRadius: 0, endCenter: glowAt, endRadius: glowRadius, options: [])
    case .tinted:
        c.setFillColor(rgb(0x000000)); c.fill(rect)
    }
}

/// Bildschirm mit Dreieck und Fuss. `s` = Kantenlänge der Symbolfläche, Ursprung `o` oben links.
func drawSymbol(_ c: CGContext, origin o: CGPoint, side s: CGFloat, look: Look, simple: Bool, withStand: Bool = true) {
    let screen = CGRect(x: o.x + 0.10 * s, y: o.y + 0.185 * s, width: 0.80 * s, height: 0.54 * s)
    let radius = 0.115 * s
    let screenPath = CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)
    // Schatten unter dem Bildschirm
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -0.025 * s), blur: 0.05 * s, color: rgb(0x000000, look == .tinted ? 0 : 0.28))
    c.addPath(screenPath); c.setFillColor(rgb(0x1C1E1E)); c.fillPath()
    c.restoreGState()
    // Glasfläche: Graphite zu Black
    c.saveGState()
    c.addPath(screenPath); c.clip()
    let top: UInt32 = look == .tinted ? 0x6E6E6E : 0x4B4D4D, mid: UInt32 = look == .tinted ? 0x3C3C3C : 0x1C1E1E, bottom: UInt32 = look == .tinted ? 0x1E1E1E : 0x090A0A
    c.drawLinearGradient(gradient([(0, rgb(top)), (0.5, rgb(mid)), (1, rgb(bottom))]), start: CGPoint(x: 0, y: screen.minY), end: CGPoint(x: 0, y: screen.maxY), options: [])
    if !simple {
        // Frostiger Schimmer: nur auf dem Bildschirm, bis 38 % Weiss, weich nach unten auslaufend.
        let inset = 0.022 * s
        let glass = CGPath(roundedRect: screen.insetBy(dx: inset, dy: inset), cornerWidth: radius - inset, cornerHeight: radius - inset, transform: nil)
        c.addPath(glass); c.clip()
        c.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.38)), (0.55, rgb(0xFFFFFF, 0.06)), (1, rgb(0xFFFFFF, 0))]), start: CGPoint(x: 0, y: screen.minY), end: CGPoint(x: 0, y: screen.maxY), options: [])
    }
    c.restoreGState()
    // Dreieck in Glut (Play), runde Ecken
    let triW = (simple ? 0.30 : 0.25) * s, triH = (simple ? 0.34 : 0.29) * s
    let cx = screen.midX + 0.012 * s, cy = screen.midY
    let r = 0.022 * s
    let a = CGPoint(x: cx - triW / 2 + r, y: cy - triH / 2 + r), b = CGPoint(x: cx - triW / 2 + r, y: cy + triH / 2 - r), t = CGPoint(x: cx + triW / 2 - r, y: cy)
    let tri = CGMutablePath(); tri.move(to: a); tri.addLine(to: t); tri.addLine(to: b); tri.closeSubpath()
    let rounded = tri.copy(strokingWithWidth: 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 1)
    let g1: UInt32 = look == .tinted ? 0xFFFFFF : 0xFF8A5C, g2: UInt32 = look == .tinted ? 0xE0E0E0 : 0xFC5F39
    let triGradient = gradient([(0, rgb(g1)), (1, rgb(g2))])
    // Rand (gerundet) und Fläche getrennt füllen, damit keine Löcher entstehen.
    for shape in [rounded, tri] {
        c.saveGState()
        c.addPath(shape); c.clip()
        c.drawLinearGradient(triGradient, start: CGPoint(x: cx - triW / 2, y: cy - triH / 2), end: CGPoint(x: cx + triW / 2, y: cy + triH / 2), options: [])
        c.restoreGState()
    }
    // Fuss
    if withStand {
        let stand = CGRect(x: o.x + 0.395 * s, y: o.y + 0.775 * s, width: 0.21 * s, height: 0.048 * s)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -0.012 * s), blur: 0.02 * s, color: rgb(0x000000, look == .tinted ? 0 : 0.22))
        c.addPath(CGPath(roundedRect: stand, cornerWidth: stand.height / 2, cornerHeight: stand.height / 2, transform: nil))
        c.clip()
        c.drawLinearGradient(gradient([(0, rgb(look == .tinted ? 0x4A4A4A : 0x2A2C2C)), (1, rgb(look == .tinted ? 0x1E1E1E : 0x090A0A))]), start: CGPoint(x: 0, y: stand.minY), end: CGPoint(x: 0, y: stand.maxY), options: [])
        c.restoreGState()
    }
}

/// iOS-Icon, vollflächig, ohne Maske.
func iosIcon(_ px: Int, look: Look, simple: Bool = false) -> CGContext {
    let c = context(px, px); let s = CGFloat(px); flip(c, s)
    drawBackground(c, rect: CGRect(x: 0, y: 0, width: s, height: s), look: look, glowAt: CGPoint(x: 0.80 * s, y: 0.17 * s), glowRadius: 0.42 * s)
    drawSymbol(c, origin: .zero, side: s, look: look, simple: simple)
    return c
}

/// macOS-Icon: Superellipse (824 von 1024) mit Schatten, Systemvorgabe ohne automatische Maske.
func macIcon(_ px: Int) -> CGContext {
    let c = context(px, px); let s = CGFloat(px); flip(c, s)
    let body = CGRect(x: 0.0977 * s, y: 0.0977 * s, width: 0.8047 * s, height: 0.8047 * s)
    let radius = body.width * 0.2237
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -0.012 * s), blur: 0.025 * s, color: rgb(0x000000, 0.30))
    c.addPath(path); c.setFillColor(rgb(0xF3F2EE)); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(path); c.clip()
    drawBackground(c, rect: body, look: .standard, glowAt: CGPoint(x: body.minX + 0.80 * body.width, y: body.minY + 0.17 * body.height), glowRadius: 0.42 * body.width)
    drawSymbol(c, origin: body.origin, side: body.width, look: .standard, simple: px <= 32)
    c.restoreGState()
    c.addPath(path); c.setStrokeColor(rgb(0x000000, 0.10)); c.setLineWidth(max(1, s / 1024)); c.strokePath()
    return c
}

/// tvOS: Rücken- und Vorderebene (Parallax). Rücken Offwhite plus Glow, Vorne Symbol mit Transparenz.
func tvBack(_ w: Int, _ h: Int) -> CGContext {
    let c = context(w, h); flip(c, CGFloat(h))
    drawBackground(c, rect: CGRect(x: 0, y: 0, width: w, height: h), look: .standard, glowAt: CGPoint(x: 0.82 * CGFloat(w), y: 0.12 * CGFloat(h)), glowRadius: 0.55 * CGFloat(h))
    return c
}
func tvFront(_ w: Int, _ h: Int) -> CGContext {
    let c = context(w, h); flip(c, CGFloat(h))
    let s = CGFloat(h) * 1.02
    drawSymbol(c, origin: CGPoint(x: (CGFloat(w) - s) / 2, y: (CGFloat(h) - s) / 2 + 0.02 * CGFloat(h)), side: s, look: .standard, simple: false)
    return c
}

// MARK: Wortmarke «IP Television+» (Brandguide S. 4): IP Geist Mono Regular, Television Geist Medium (-0.012 em), «+» Glut.
func font(_ file: String, _ size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "App/Resources/Fonts/\(file).ttf")
    let desc = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)! as! [CTFontDescriptor]
    return CTFontCreateWithFontDescriptor(desc[0], size, nil)
}
func wordmark(canvas w: Int, _ h: Int, text: UInt32) -> CGContext {
    let c = context(w, h)
    let em: CGFloat = 1000
    let ip = NSAttributedString(string: "IP", attributes: [.font: font("GeistMono-Regular", em), .foregroundColor: NSColor(cgColor: rgb(text))!])
    let tv = NSAttributedString(string: "Television", attributes: [.font: font("Geist-Medium", em), .foregroundColor: NSColor(cgColor: rgb(text))!, .kern: -0.012 * em])
    let l1 = CTLineCreateWithAttributedString(ip), l2 = CTLineCreateWithAttributedString(tv)
    let b1 = CTLineGetImageBounds(l1, c), b2 = CTLineGetImageBounds(l2, c)
    let gap = 0.16 * em, plus = 0.20 * em
    let totalW = b1.width + gap + b2.width + plus * 0.5
    let capH = max(b1.height, b2.height)
    let scale = min(CGFloat(w) * 0.92 / totalW, CGFloat(h) * 0.56 / capH)
    c.translateBy(x: (CGFloat(w) - totalW * scale) / 2, y: CGFloat(h) / 2 - capH * scale / 2 - min(b1.minY, b2.minY) * scale)
    c.scaleBy(x: scale, y: scale)
    var x: CGFloat = -b1.minX
    c.textPosition = CGPoint(x: x, y: 0); CTLineDraw(l1, c)
    x += b1.maxX + gap - b2.minX
    c.textPosition = CGPoint(x: x, y: 0); CTLineDraw(l2, c)
    // «+»: Strich 92/1000 em, runde Enden, um -8° gekippt, oben bündig (Cap-Höhe)
    let px = x + b2.maxX + 0.07 * em, py = capH - 0.085 * em
    c.saveGState()
    c.translateBy(x: px, y: py); c.rotate(by: 8 * .pi / 180)
    c.setStrokeColor(rgb(0xFC5F39)); c.setLineCap(.round); c.setLineWidth(0.092 * em)
    c.move(to: CGPoint(x: -0.095 * em, y: 0)); c.addLine(to: CGPoint(x: 0.095 * em, y: 0))
    c.move(to: CGPoint(x: 0, y: -0.095 * em)); c.addLine(to: CGPoint(x: 0, y: 0.095 * em))
    c.strokePath()
    c.restoreGState()
    return c
}

// MARK: Ausgabe
save(iosIcon(1024, look: .standard), "icon-1024.png")
save(iosIcon(1024, look: .standard), "icon-1024-dark.png") // Guide: nie dunkler Grund, Dark nutzt dasselbe Icon
save(iosIcon(1024, look: .tinted), "icon-1024-tinted.png")
for px in [16, 32, 64, 128, 256, 512, 1024] { save(macIcon(px), "mac-\(px).png") }
save(iosIcon(1024, look: .standard), "AppIconMaster.png")
for (name, w, h) in [("Large", 1280, 768), ("Small", 400, 240)] {
    for k in [1, 2] {
        save(tvBack(w * k, h * k), "tv-\(name)-back\(k)x.png")
        save(tvFront(w * k, h * k), "tv-\(name)-front\(k)x.png")
    }
}
for (name, w, h) in [("Wortmarke", 2400, 635), ("WortmarkeKlein", 2000, 444), ("Lockup", 2800, 769)] {
    save(wordmark(canvas: w, h, text: 0x090A0A), "\(name)-hell.png")
    save(wordmark(canvas: w, h, text: 0xFDFDFC), "\(name)-dunkel.png")
}
print("fertig: \(out.path)")
