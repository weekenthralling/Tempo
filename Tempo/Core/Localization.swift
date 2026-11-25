//
//  Localization.swift
//  Tempo
//

import Foundation

/// Formats a localized string that contains a single integer placeholder.
///
/// SwiftUI can localize `Text("Bar \(number)")` on its own, but the format
/// specifier it generates for an `Int` is an implementation detail. Going
/// through `NSLocalizedString` keeps the `%lld` keys in `Localizable.strings`
/// authoritative and makes the behaviour identical on every iOS version.
func localizedInteger(_ key: String, _ value: Int) -> String {
    String(format: NSLocalizedString(key, comment: ""), Int64(value))
}
