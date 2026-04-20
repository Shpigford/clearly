import Foundation

#if os(macOS)
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
public typealias PlatformPasteboard = NSPasteboard
#elseif os(iOS)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
public typealias PlatformPasteboard = UIPasteboard
#endif
