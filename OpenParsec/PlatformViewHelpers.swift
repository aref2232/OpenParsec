import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension View {
    @ViewBuilder
    func platformPadding() -> some View {
        #if os(macOS)
        self.padding(12)
        #else
        self.padding(8)
        #endif
    }
}
