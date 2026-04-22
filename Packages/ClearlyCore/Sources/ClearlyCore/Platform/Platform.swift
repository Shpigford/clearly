import Foundation
import SwiftUI

#if os(macOS)
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
public typealias PlatformPasteboard = NSPasteboard
public typealias PlatformTextView = NSTextView
public typealias PlatformTextStorage = NSTextStorage
public typealias PlatformParagraphStyle = NSMutableParagraphStyle
#elseif os(iOS)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
public typealias PlatformPasteboard = UIPasteboard
public typealias PlatformTextView = UITextView
public typealias PlatformTextStorage = NSTextStorage
public typealias PlatformParagraphStyle = NSMutableParagraphStyle
#endif

public enum PlatformFontWeight {
    case regular
    case bold
}

public enum PlatformDevice {
    /// User-visible device name, used in conflict sibling filenames.
    public static func currentName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #endif
    }
}

public enum PlatformTextAttributes {
    public static let font = NSAttributedString.Key.font
    public static let foregroundColor = NSAttributedString.Key.foregroundColor
    public static let backgroundColor = NSAttributedString.Key.backgroundColor
    public static let paragraphStyle = NSAttributedString.Key.paragraphStyle
    public static let baselineOffset = NSAttributedString.Key.baselineOffset
    public static let strikethroughStyle = NSAttributedString.Key.strikethroughStyle
    public static let singleUnderlineStyleValue = NSUnderlineStyle.single.rawValue
}

public extension PlatformFont {
    static func clearlyMonospacedSystemFont(ofSize size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
        #if os(macOS)
        let platformWeight: NSFont.Weight = weight == .bold ? .bold : .regular
        return NSFont.monospacedSystemFont(ofSize: size, weight: platformWeight)
        #else
        let platformWeight: UIFont.Weight = weight == .bold ? .bold : .regular
        return UIFont.monospacedSystemFont(ofSize: size, weight: platformWeight)
        #endif
    }

    /// Returns a font with italic trait applied. Falls back to `self` if unavailable.
    func withItalicTrait() -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
        #else
        var traits = fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: pointSize)
        }
        return self
        #endif
    }

    /// Builds a bold + italic monospaced system font at the given size.
    static func clearlyMonospacedBoldItalic(size: CGFloat) -> PlatformFont {
        #if os(macOS)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        return NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        #else
        let bold = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        var traits = bold.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = bold.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return bold
        #endif
    }
}

public extension PlatformColor {
    static func clearlyColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        #if os(macOS)
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// Loads a named color from the `ClearlyCore` asset catalog (`Bundle.module`).
    /// The asset must exist — unresolved names trap.
    static func clearlyAsset(named name: String) -> PlatformColor {
        #if os(macOS)
        guard let color = NSColor(named: NSColor.Name(name), bundle: .module) else {
            fatalError("Missing color asset '\(name)' in ClearlyCore Colors.xcassets")
        }
        return color
        #else
        guard let color = UIColor(named: name, in: .module, compatibleWith: nil) else {
            fatalError("Missing color asset '\(name)' in ClearlyCore Colors.xcassets")
        }
        return color
        #endif
    }

    enum Appearance: Sendable {
        case light
        case dark
    }

    /// Resolves this color's sRGB components for the given appearance and returns a CSS
    /// color string: `#RRGGBB` when alpha rounds to 1, `rgba(r, g, b, a)` otherwise.
    func cssHexString(for appearance: Appearance) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        #if os(macOS)
        let target = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
        var resolved: NSColor?
        target.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.sRGB)
        }
        if let resolved {
            r = resolved.redComponent
            g = resolved.greenComponent
            b = resolved.blueComponent
            a = resolved.alphaComponent
        }
        #else
        let traits = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
        self.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        if a >= 0.9995 {
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
        let alpha = (a * 1000).rounded() / 1000
        let alphaStr: String
        if alpha == alpha.rounded() {
            alphaStr = String(Int(alpha))
        } else {
            alphaStr = String(format: "%g", alpha)
        }
        return "rgba(\(ri), \(gi), \(bi), \(alphaStr))"
    }
}

public extension Color {
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
