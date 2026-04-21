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

    static func clearlyDynamic(
        name: String,
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> PlatformColor {
        #if os(macOS)
        return NSColor(name: NSColor.Name(name)) { appearance in
            appearance.clearlyIsDark
                ? NSColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
                : NSColor(red: light.0, green: light.1, blue: light.2, alpha: light.3)
        }
        #else
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: light.3)
        }
        #endif
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

#if os(macOS)
private extension NSAppearance {
    var clearlyIsDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
#endif
