//
//  FlowLayout.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import SwiftUI

/// Wrapping flow layout used by chat messages, placing text and inline emote images
/// into as many rows as needed, bottom-aligned within each row.
struct FlowLayout: Layout {
	var itemSpacing: CGFloat = 4
	var lineSpacing: CGFloat = 4

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let arrangement = arrange(width: proposal.width ?? .infinity, subviews: subviews)
		return CGSize(width: arrangement.width, height: arrangement.height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let arrangement = arrange(width: bounds.width, subviews: subviews)
		var y = bounds.minY

		for row in arrangement.rows {
			var x = bounds.minX

			for index in row.indices {
				let size = arrangement.sizes[index]
				subviews[index].place(
					at: CGPoint(x: x, y: y + row.height - size.height),
					anchor: .topLeading,
					proposal: ProposedViewSize(width: size.width, height: size.height)
				)
				x += size.width + itemSpacing
			}

			y += row.height + lineSpacing
		}
	}
}

private extension FlowLayout {
	private struct Arrangement {
		var rows = [(indices: Range<Int>, height: CGFloat)]()
		var sizes = [CGSize]()
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	/// Measures subviews and wraps them into rows fitting the given width.
	private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
		var arrangement = Arrangement(sizes: Array(repeating: .zero, count: subviews.count))
		var x: CGFloat = 0
		var lineHeight: CGFloat = 0
		var rowStart = 0

		for index in subviews.indices {
			let remaining = width - x
			var size = subviews[index].sizeThatFits(ProposedViewSize(width: max(0, remaining), height: nil))

			if size.width > remaining, x > 0 {
				arrangement.rows.append((rowStart..<index, lineHeight))
				arrangement.height += lineHeight + lineSpacing
				x = 0
				lineHeight = 0
				rowStart = index
				size = subviews[index].sizeThatFits(ProposedViewSize(width: max(0, width), height: nil))
			}

			arrangement.sizes[index] = size
			lineHeight = max(lineHeight, size.height)
			x += size.width + itemSpacing

			if x > width, width.isFinite {
				arrangement.rows.append((rowStart..<index + 1, lineHeight))
				arrangement.height += lineHeight + lineSpacing
				x = 0
				lineHeight = 0
				rowStart = index + 1
			}
			arrangement.width = max(arrangement.width, x - itemSpacing)
		}

		if rowStart < subviews.count {
			arrangement.rows.append((rowStart..<subviews.count, lineHeight))
			arrangement.height += lineHeight
		}

		if width.isFinite {
			arrangement.width = width
		}

		return arrangement
	}
}