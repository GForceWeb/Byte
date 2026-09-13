//
//  ChatSettings.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import Foundation
import SwiftUI

/// Overlay settings for the floating chat window of a single stream.
struct ChatSettings: Codable, Equatable {
	static let `default` = ChatSettings()

	/// Chat window height as a percentage of the stream area height. The width is always a quarter of the stream area width.
	var size = ChatSize.fifty
	/// Chat window position (1-8), 1 is the bottom right corner.
	var position = ChatPosition.bottomRight
	/// Background opacity as a percentage, 0 is transparent and 100 is opaque.
	var backgroundOpacity = 80
	/// Font size scale as a percentage, 100 is the default size.
	var fontSize = ChatFontSize.hundred
	/// Whether the chat overlay is shown for this stream.
	var isEnabled = true
}

enum ChatSize: Int, Codable, CaseIterable, Identifiable {
	case twentyFive = 25
	case fifty = 50
	case seventyFive = 75
	case hundred = 100

	var id: Int { rawValue }

	var label: String {
		return "\(rawValue)%"
	}

	/// Height of the chat window as a fraction of the stream area height.
	var fraction: Double {
		return Double(rawValue) / 100
	}
}

/// Chat window positions, ordered clockwise starting from the bottom right corner.
enum ChatPosition: Int, Codable, CaseIterable, Identifiable {
	case bottomRight = 1
	case bottomLeft = 2
	case topLeft = 3
	case topRight = 4
	case bottomCenter = 5
	case leftCenter = 6
	case topCenter = 7
	case rightCenter = 8

	var id: Int { rawValue }

	var label: String {
		switch self {
		case .bottomRight:
			return "Bottom Right"
		case .bottomLeft:
			return "Bottom Left"
		case .topLeft:
			return "Top Left"
		case .topRight:
			return "Top Right"
		case .bottomCenter:
			return "Bottom"
		case .leftCenter:
			return "Left"
		case .topCenter:
			return "Top"
		case .rightCenter:
			return "Right"
		}
	}

	/// Position within the 3x3 selection grid, the center cell is unused.
	var grid: (row: Int, column: Int) {
		switch self {
		case .topLeft:
			return (0, 0)
		case .topCenter:
			return (0, 1)
		case .topRight:
			return (0, 2)
		case .leftCenter:
			return (1, 0)
		case .rightCenter:
			return (1, 2)
		case .bottomLeft:
			return (2, 0)
		case .bottomCenter:
			return (2, 1)
		case .bottomRight:
			return (2, 2)
		}
	}

	/// Anchor alignment of the chat window within the stream area.
	var alignment: Alignment {
		switch self {
		case .topLeft:
			return .topLeading
		case .topCenter:
			return .top
		case .topRight:
			return .topTrailing
		case .leftCenter:
			return .leading
		case .rightCenter:
			return .trailing
		case .bottomLeft:
			return .bottomLeading
		case .bottomCenter:
			return .bottom
		case .bottomRight:
			return .bottomTrailing
		}
	}
}

/// Corner radii of a rectangular window, one per corner.
struct ChatCornerRadii: Equatable {
	let topLeading: CGFloat
	let bottomLeading: CGFloat
	let bottomTrailing: CGFloat
	let topTrailing: CGFloat
}

extension ChatPosition {
	var touchesLeadingEdge: Bool {
		switch self {
		case .topLeft, .leftCenter, .bottomLeft:
			return true
		case .topCenter, .bottomCenter, .topRight, .rightCenter, .bottomRight:
			return false
		}
	}

	var touchesTrailingEdge: Bool {
		switch self {
		case .topRight, .rightCenter, .bottomRight:
			return true
		case .topLeft, .topCenter, .bottomLeft, .bottomCenter, .leftCenter:
			return false
		}
	}

	var touchesTopEdge: Bool {
		switch self {
		case .topLeft, .topCenter, .topRight:
			return true
		case .leftCenter, .rightCenter, .bottomLeft, .bottomCenter, .bottomRight:
			return false
		}
	}

	var touchesBottomEdge: Bool {
		switch self {
		case .bottomLeft, .bottomCenter, .bottomRight:
			return true
		case .topLeft, .topCenter, .topRight, .leftCenter, .rightCenter:
			return false
		}
	}

	/// Corner radii. Corners touching a window edge are not rounded so the window sits flush against it.
	func cornerRadii(radius: CGFloat) -> ChatCornerRadii {
		return ChatCornerRadii(
			topLeading: (touchesLeadingEdge || touchesTopEdge) ? 0 : radius,
			bottomLeading: (touchesLeadingEdge || touchesBottomEdge) ? 0 : radius,
			bottomTrailing: (touchesTrailingEdge || touchesBottomEdge) ? 0 : radius,
			topTrailing: (touchesTrailingEdge || touchesTopEdge) ? 0 : radius
		)
	}
}

enum ChatFontSize: Int, Codable, CaseIterable, Identifiable {
	case fifty = 50
	case seventyFive = 75
	case hundred = 100
	case hundredTwentyFive = 125
	case hundredFifty = 150
	case hundredSeventyFive = 175
	case twoHundred = 200

	var id: Int { rawValue }

	var label: String {
		return "\(rawValue)%"
	}

	var scale: Double {
		return Double(rawValue) / 100
	}
}