//
//  Color+Extensions.swift
//  Byte
//
//  Created by Kristian Pennacchia on 29/8/19.
//  Copyright © 2019 Kristian Pennacchia. All rights reserved.
//

import SwiftUI

extension Color {
    static let brand = BrandColor.self

    /// Creates a color from a hex string, e.g. "#1E90FF" or "1E90FF".
    init?(hex: String) {
        let sanitized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
