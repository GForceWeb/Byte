//
//  ChatOverlayView.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import SwiftUI
import UIKit

/// Floating chat window overlaying a single stream, configurable via `ChatSettings`.
/// The window is a quarter of the stream width, sized in height by `settings.size`, and sits
/// flush against the edges matching the configured position.
struct ChatOverlayView: View {
	@StateObject private var connection = TwitchChatConnection()
	@ObservedObject var emoteCache: ChatEmoteCache

	let channelLogin: String
	let twitchUserID: String
	let settings: ChatSettings
	/// Fraction of the full window this stream occupies, e.g. 0.5 when two streams share the window.
	/// Font size scales with it so text stays proportionally sized in multiview, independent of the font size setting.
	let windowScale: Double

	private static let baseFontSize: CGFloat = 15

	var body: some View {
		GeometryReader { geometry in
			let windowFrame = Self.windowFrame(
				position: settings.position,
				heightFraction: settings.size.fraction,
				area: geometry.size
			)

			messageList
				.frame(width: windowFrame.width, height: windowFrame.height)
				.background(Color.black.opacity(Double(settings.backgroundOpacity) / 100))
				.clipShape(Self.clipShape(position: settings.position))
				.position(x: windowFrame.midX, y: windowFrame.midY)
				.transition(.opacity)
		}
		.allowsHitTesting(false)
		.onAppear {
			connection.connect(login: channelLogin)
			Task { await emoteCache.prepare(twitchUserID: twitchUserID) }
		}
		.onDisappear {
			connection.disconnect()
		}
	}

	/// Base font size scaled by the font size setting and the size of the stream window.
	static func fontSize(base: CGFloat, settings: ChatSettings, windowScale: Double) -> CGFloat {
		return base * settings.fontSize.scale * CGFloat(windowScale)
	}
}

extension ChatOverlayView {
	/// Width of the chat window as a fraction of the stream area width.
	static let widthFraction = 0.25

	/// Corner radius applied to corners not flush with the window edges.
	static let cornerRadius: CGFloat = 14

	/// Calculates the chat window frame, sitting flush against the edges matching the configured position.
	static func windowFrame(position: ChatPosition, heightFraction: Double, area: CGSize) -> CGRect {
		let width = area.width * widthFraction
		let height = area.height * heightFraction

		let x: CGFloat
		switch position {
		case .topLeft, .leftCenter, .bottomLeft:
			x = 0
		case .topCenter, .bottomCenter:
			x = (area.width - width) / 2
		case .topRight, .rightCenter, .bottomRight:
			x = area.width - width
		}

		let y: CGFloat
		switch position {
		case .topLeft, .topCenter, .topRight:
			y = 0
		case .leftCenter, .rightCenter:
			y = (area.height - height) / 2
		case .bottomLeft, .bottomCenter, .bottomRight:
			y = area.height - height
		}

		return CGRect(x: x, y: y, width: width, height: height)
	}

	/// Corner rounding that only applies to corners not touching the window edges.
	static func clipShape(position: ChatPosition) -> UnevenRoundedRectangle {
		let radii = position.cornerRadii(radius: cornerRadius)
		return UnevenRoundedRectangle(
			cornerRadii: .init(
				topLeading: radii.topLeading,
				bottomLeading: radii.bottomLeading,
				bottomTrailing: radii.bottomTrailing,
				topTrailing: radii.topTrailing
			)
		)
	}}

private extension ChatOverlayView {
	var fontSize: CGFloat {
		return Self.fontSize(base: Self.baseFontSize, settings: settings, windowScale: windowScale)
	}
	var messageList: some View {
		ScrollViewReader { proxy in
			ScrollView {
				VStack(alignment: .leading, spacing: 6) {
					ForEach(connection.messages) { message in
						ChatMessageRow(message: message, fontSize: fontSize, emoteCache: emoteCache)
					}
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
			}
			.onChange(of: connection.messages) { _, newMessages in
				withAnimation(.easeOut(duration: 0.15)) {
					proxy.scrollTo(newMessages.last?.id, anchor: .bottom)
				}
			}
		}
	}
}

struct ChatMessageRow: View {
	let message: ChatMessage
	let fontSize: CGFloat
	@ObservedObject var emoteCache: ChatEmoteCache

	var body: some View {
		let segments = message.segments(emoteCache: emoteCache)

		FlowLayout(itemSpacing: 4, lineSpacing: 4) {
			ForEach(Array(message.badges.enumerated()), id: \.offset) { _, badge in
				badgeIcon(badge)
			}

			Text(message.author)
				.fontWeight(.bold)
				.foregroundColor(message.color)

			ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
				segmentView(segment)
			}
		}
		.font(.system(size: fontSize))
		.task(id: segments.emoteIDs) {
			for segment in segments {
				if case .emote(let emote) = segment {
					await emoteCache.loadImage(for: emote)
				}
			}
		}
	}

	@ViewBuilder
	private func segmentView(_ segment: ChatMessageSegment) -> some View {
		switch segment {
		case .text(let string):
			Text(string)
				.foregroundColor(.white)
		case .emote(let emote):
			ChatEmoteDisplayView(emote: emote, fontSize: fontSize, emoteCache: emoteCache)
		}
	}

	private func badgeIcon(_ badge: ChatBadge) -> some View {
		let (systemImage, color): (String, Color) = {
			switch badge {
			case .broadcaster:
				return ("crown.fill", Color.yellow)
			case .moderator:
				return ("shield.fill", Color.green)
			case .vip:
				return ("diamond.fill", Color.pink)
			case .subscriber:
				return ("star.fill", Color.purple)
			case .founder:
				return ("heart.fill", Color.blue)
			}
		}()

		return Image(systemName: systemImage)
			.font(.system(size: fontSize * 0.8))
			.foregroundColor(color)
	}
}

/// Displays a loaded emote inline, animating animated emotes (GIF, APNG, animated WebP).
struct ChatEmoteDisplayView: View {
	let emote: ChatEmote
	let fontSize: CGFloat
	@ObservedObject var emoteCache: ChatEmoteCache

	var body: some View {
		if let displayable = emoteCache.displayable(for: emote, fontSize: fontSize) {
			switch displayable {
			case .image(let image):
				Image(uiImage: image)
					.resizable()
					.frame(width: image.size.width, height: image.size.height)
			case .animated(let frames, let duration):
				ChatAnimatedEmoteView(frames: frames, duration: duration)
					.frame(width: frames.first?.size.width ?? 0, height: frames.first?.size.height ?? 0)
			}
		} else {
			// Shown as text until the emote image loads.
			Text(emote.name)
				.foregroundColor(.white)
		}
	}
}

/// Renders animated emote frames via UIImageView, repeating indefinitely.
struct ChatAnimatedEmoteView: UIViewRepresentable {
	let frames: [UIImage]
	let duration: TimeInterval

	func makeUIView(context: Context) -> UIImageView {
		let view = UIImageView()
		view.contentMode = .scaleAspectFit
		return view
	}

	func updateUIView(_ view: UIImageView, context: Context) {
		guard context.coordinator.frames != frames else { return }

		context.coordinator.frames = frames
		view.stopAnimating()
		view.animationImages = frames
		view.animationDuration = max(0.05, duration)
		view.animationRepeatCount = 0
		view.startAnimating()
	}

	func makeCoordinator() -> Coordinator {
		return Coordinator()
	}

	final class Coordinator {
		var frames: [UIImage]?
	}
}