//
//  ChatSettingsOverlay.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import SwiftUI

/// Overlay for configuring the floating chat window of a single stream.
/// Changes apply immediately and are persisted per stream via the given `ChatSettingsStore`.
struct ChatSettingsOverlay: View {
	private enum Control: Hashable {
		case size(ChatSize)
		case position(ChatPosition)
		case opacityDown
		case opacityUp
		case fontDown
		case fontUp
		case reset
		case close
	}

	private struct RowControl {
		let column: Int
		let control: Control
	}

	let streamID: String
	let streamName: String
	@ObservedObject var store: ChatSettingsStore
	let dismiss: () -> Void

	@State private var settings: ChatSettings
	@FocusState private var focusedControl: Control?
	@Namespace private var controlsFocusNamespace
	@Environment(\.resetFocus) private var resetFocus

	init(store: ChatSettingsStore, streamID: String, streamName: String, dismiss: @escaping () -> Void) {
		self.store = store
		self.streamID = streamID
		self.streamName = streamName
		self.dismiss = dismiss
		_settings = State(initialValue: store.settings(for: streamID))
	}

	private var rows: [[RowControl]] {
		return [
			ChatSize.allCases.enumerated().map { RowControl(column: $0.offset, control: .size($0.element)) },
			[
				RowControl(column: 0, control: .position(.topLeft)),
				RowControl(column: 1, control: .position(.topCenter)),
				RowControl(column: 2, control: .position(.topRight)),
			],
			[
				RowControl(column: 0, control: .position(.leftCenter)),
				RowControl(column: 2, control: .position(.rightCenter)),
			],
			[
				RowControl(column: 0, control: .position(.bottomLeft)),
				RowControl(column: 1, control: .position(.bottomCenter)),
				RowControl(column: 2, control: .position(.bottomRight)),
			],
			[
				RowControl(column: 0, control: .opacityDown),
				RowControl(column: 1, control: .opacityUp),
			],
			[
				RowControl(column: 0, control: .fontDown),
				RowControl(column: 1, control: .fontUp),
			],
			[RowControl(column: 0, control: .reset), RowControl(column: 1, control: .close)],
		]
	}

	var body: some View {
		ZStack {
			VisualEffectView(effect: UIBlurEffect(style: .dark))

			VStack(alignment: .leading, spacing: 16) {
				HStack(alignment: .bottom, spacing: 24) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Chat Settings")
							.font(.system(size: 34, weight: .bold))

						Text(streamName)
							.font(.system(size: 21, weight: .semibold))
							.lineLimit(1)
					}

					Spacer(minLength: 24)
				}

				Capsule()
					.fill(.white.opacity(0.32))
					.frame(height: 6)

				sizeRow
				positionRow
				opacityRow
				fontSizeRow
				actionRow
			}
			.padding(44)
			.frame(maxWidth: 980)
			.foregroundStyle(.white)
			.background {
				RoundedRectangle(cornerRadius: 22)
					.fill(.black.opacity(0.72))
			}
			.clipShape(RoundedRectangle(cornerRadius: 22))
			.focusScope(controlsFocusNamespace)
			.onMoveCommand(perform: moveFocus)
			.onExitCommand(perform: dismiss)
		}
		.edgesIgnoringSafeArea(.all)
		.onAppear {
			DispatchQueue.main.async {
				focusedControl = .size(settings.size)
				resetFocus(in: controlsFocusNamespace)
			}
		}
	}
}

private extension ChatSettingsOverlay {
	// - MARK: Rows

	var sizeRow: some View {
		HStack(spacing: 14) {
			rowLabel("Size")

			ForEach(ChatSize.allCases) { size in
				pillButton(
					size.label,
					control: .size(size),
					isSelected: settings.size == size
				) {
					update { $0.size = size }
				}
			}
		}
	}

	var positionRow: some View {
		HStack(alignment: .center, spacing: 14) {
			rowLabel("Position")

			VStack(spacing: 8) {
				positionGridRow([.topLeft, .topCenter, .topRight])
				positionGridRow([.leftCenter, nil, .rightCenter])
				positionGridRow([.bottomLeft, .bottomCenter, .bottomRight])
			}
		}
	}

	var opacityRow: some View {
		HStack(spacing: 14) {
			rowLabel("Background Opacity")

			pillButton("−", control: .opacityDown, isSelected: false) {
				update { $0.backgroundOpacity = max(0, $0.backgroundOpacity - 10) }
			}

			Text("\(settings.backgroundOpacity)%")
				.font(.system(size: 20, weight: .bold))
				.frame(width: 90)

			pillButton("+", control: .opacityUp, isSelected: false) {
				update { $0.backgroundOpacity = min(100, $0.backgroundOpacity + 10) }
			}
		}
	}

	var fontSizeRow: some View {
		HStack(spacing: 14) {
			rowLabel("Font Size")

			pillButton("−", control: .fontDown, isSelected: false) {
				update { settings in
					if let index = ChatFontSize.allCases.firstIndex(of: settings.fontSize), index > ChatFontSize.allCases.startIndex {
						settings.fontSize = ChatFontSize.allCases[index - 1]
					}
				}
			}

			Text(settings.fontSize.label)
				.font(.system(size: 20, weight: .bold))
				.frame(width: 90)

			pillButton("+", control: .fontUp, isSelected: false) {
				update { settings in
					if let index = ChatFontSize.allCases.firstIndex(of: settings.fontSize), index < ChatFontSize.allCases.count - 1 {
						settings.fontSize = ChatFontSize.allCases[index + 1]
					}
				}
			}
		}
	}

	var actionRow: some View {
		HStack(spacing: 14) {
			pillButton("Reset To Default", control: .reset, isSelected: false) {
				store.reset(for: streamID)
				settings = store.settings(for: streamID)
				DispatchQueue.main.async {
					focusedControl = .size(settings.size)
				}
			}

			pillButton("Close", control: .close, isSelected: false, action: dismiss)
		}
	}

	func positionGridRow(_ positions: [ChatPosition?]) -> some View {
		HStack(spacing: 8) {
			ForEach(Array(positions.enumerated()), id: \.offset) { _, position in
				if let position {
					let isFocused = focusedControl == .position(position)

					RoundedRectangle(cornerRadius: 10)
						.fill(cellFill(isSelected: settings.position == position, isFocused: isFocused))
						.frame(width: 52, height: 52)
						.contentShape(RoundedRectangle(cornerRadius: 10))
						.focusEffectDisabled()
						.focusable(true, interactions: .activate)
						.focused($focusedControl, equals: .position(position))
						.scaleEffect(isFocused ? 1.1 : 1)
						.animation(.easeInOut(duration: 0.14), value: focusedControl)
						.simultaneousGesture(TapGesture().onEnded {
							update { $0.position = position }
						})
						.onExitCommand(perform: dismiss)
				} else {
					RoundedRectangle(cornerRadius: 10)
						.fill(.white.opacity(0.04))
						.frame(width: 52, height: 52)
				}
			}
		}
	}

	// - MARK: Helpers

	func rowLabel(_ title: String) -> some View {
		return Text(title)
			.font(.system(size: 18, weight: .semibold))
			.foregroundStyle(.white.opacity(0.74))
			.frame(width: 210, alignment: .leading)
	}

	private func pillButton(_ title: String, control: Control, isSelected: Bool, action: @escaping () -> Void) -> some View {
		let isFocused = focusedControl == control

		return Text(title)
			.font(.system(size: 18, weight: .semibold))
			.lineLimit(1)
			.padding(.horizontal, 22)
			.frame(height: 48)
			.contentShape(Capsule())
			.focusEffectDisabled()
			.focusable(true, interactions: .activate)
			.focused($focusedControl, equals: control)
			.foregroundStyle(foreground(isSelected: isSelected, isFocused: isFocused))
			.background {
				Capsule()
					.fill(background(isSelected: isSelected, isFocused: isFocused))
			}
			.animation(.easeInOut(duration: 0.14), value: focusedControl)
			.animation(.easeInOut(duration: 0.14), value: settings)
			.scaleEffect(isFocused ? 1.06 : 1)
			.shadow(color: .black.opacity(isFocused ? 0.34 : 0), radius: 18, y: 8)
			.simultaneousGesture(TapGesture().onEnded(action))
			.onExitCommand(perform: dismiss)
	}

	func background(isSelected: Bool, isFocused: Bool) -> Color {
		if isFocused {
			return isSelected ? Color.brand.primary : .white
		}
		return isSelected ? Color.brand.primary.opacity(0.82) : .white.opacity(0.14)
	}

	func foreground(isSelected: Bool, isFocused: Bool) -> Color {
		if isFocused {
			return .black
		}
		return isSelected ? .white : .white.opacity(0.86)
	}

	func update(_ mutate: (inout ChatSettings) -> Void) {
		var newSettings = settings
		mutate(&newSettings)
		settings = newSettings
		store.update(newSettings, for: streamID)
	}

	func cellFill(isSelected: Bool, isFocused: Bool) -> Color {
		if isFocused {
			return isSelected ? Color.brand.primary : .white.opacity(0.55)
		}
		return isSelected ? Color.brand.primary.opacity(0.82) : .white.opacity(0.14)
	}

	func moveFocus(_ direction: MoveCommandDirection) {
		guard let current = focusedControl else { return }

		let rows = self.rows
		guard let location = location(of: current, in: rows) else { return }

		let target: Control?

		switch direction {
		case .up:
			guard location.row > 0 else {
				target = nil
				break
			}

			let row = rows[location.row - 1]
			target = row.first(where: { $0.column >= location.column })?.control ?? row.last?.control
		case .down:
			guard location.row < rows.count - 1 else {
				target = nil
				break
			}

			let row = rows[location.row + 1]
			target = row.first(where: { $0.column >= location.column })?.control ?? row.last?.control
		case .left:
			guard let index = rows[location.row].firstIndex(where: { $0.control == current }), index > 0 else {
				target = nil
				break
			}

			target = rows[location.row][index - 1].control
		case .right:
			let row = rows[location.row]
			guard let index = row.firstIndex(where: { $0.control == current }), index < row.count - 1 else {
				target = nil
				break
			}

			target = row[index + 1].control
		@unknown default:
			target = nil
		}

		if let target {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
				focusedControl = target
			}
		}
	}

	private func location(of control: Control, in rows: [[RowControl]]) -> (row: Int, column: Int)? {
		for (rowIndex, row) in rows.enumerated() {
			if let rowControl = row.first(where: { $0.control == control }) {
				return (rowIndex, rowControl.column)
			}
		}

		return nil
	}
}