//
//  ChatEmoteCache.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import Foundation
import SwiftUI
import UIKit
import ImageIO
import OSLog

/// Raw decoded emote content, either a single image or animation frames.
enum ChatEmoteImage {
	case image(UIImage)
	case animated(frames: [UIImage], duration: TimeInterval)
}

/// Loads and caches chat emotes from Twitch and third-party providers (BTTV, 7TV, FFZ),
/// providing emote images sized for inline rendering within chat messages.
@MainActor
final class ChatEmoteCache: ObservableObject {
	@Published private(set) var images = [String: ChatEmoteImage]()
	@Published private(set) var emotesByName = [String: ChatEmote]()

	/// Emotes are rendered larger than the surrounding text, matching the Twitch client.
	static let emoteSizeFactor: Double = 1.35
	private static let maxAnimationFrameCount = 64

	private static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return decoder
	}()

	private var preparedUserIDs = Set<String>()
	private var loadingEmoteIDs = [String: Task<Void, Never>]()
	private var scaledDisplayables = [String: ChatEmoteImage]()
	private var scaledFontSize: CGFloat?
	private var failedEmoteIDs = Set<String>()

	func emote(named name: String) -> ChatEmote? {
		return emotesByName[name]
	}

	/// Returns the emote displayable scaled for rendering next to text of the given font size, loading it if needed.
	func displayable(for emote: ChatEmote, fontSize: CGFloat) -> ChatEmoteImage? {
		if scaledFontSize != fontSize {
			scaledDisplayables.removeAll()
			scaledFontSize = fontSize
		}

		if let scaled = scaledDisplayables[emote.id] {
			return scaled
		}

		guard let image = images[emote.id] else {
			return nil
		}

		let scaled = Self.scaledDisplayable(from: image, fontSize: fontSize)
		scaledDisplayables[emote.id] = scaled
		return scaled
	}

	/// Fetches the global and channel emote sets of all providers for the given Twitch user.
	func prepare(twitchUserID: String) async {
		guard twitchUserID.isEmpty == false, preparedUserIDs.contains(twitchUserID) == false else { return }
		preparedUserIDs.insert(twitchUserID)

		async let bttvGlobal = Self.fetchBTTVGlobalEmotes()
		async let sevenTVGlobal = Self.fetchSevenTVGlobalEmotes()
		async let ffzGlobal = Self.fetchFFZGlobalEmotes()
		async let bttvChannel = Self.fetchBTTVEmotes(twitchUserID: twitchUserID)
		async let sevenTVChannel = Self.fetchSevenTVEmotes(twitchUserID: twitchUserID)
		async let ffzChannel = Self.fetchFFZEmotes(twitchUserID: twitchUserID)

		// Earlier sets win name conflicts.
		add((try? await bttvGlobal) ?? [])
		add((try? await sevenTVGlobal) ?? [])
		add((try? await ffzGlobal) ?? [])
		add((try? await bttvChannel) ?? [])
		add((try? await sevenTVChannel) ?? [])
		add((try? await ffzChannel) ?? [])
	}

	/// Loads the image for an emote, deduplicating concurrent requests and remembering failures.
	func loadImage(for emote: ChatEmote) async {
		if images[emote.id] != nil || failedEmoteIDs.contains(emote.id) {
			return
		}

		if let loading = loadingEmoteIDs[emote.id] {
			await loading.value
			return
		}

		loadingEmoteIDs[emote.id] = Task { [weak self] () -> Void in
			let loaded = await Self.loadImage(url: emote.url)

			guard let self else { return }

			self.loadingEmoteIDs[emote.id] = nil
			if let loaded {
				self.images[emote.id] = loaded
			} else {
				self.failedEmoteIDs.insert(emote.id)
			}
		}

		await loadingEmoteIDs[emote.id]?.value
	}

	/// Adds emotes to the lookup table without overwriting existing names.
	func add(_ emotes: [ChatEmote]) {
		for emote in emotes where emotesByName[emote.name] == nil {
			emotesByName[emote.name] = emote
		}
	}

	nonisolated private static func loadImage(url: URL) async -> ChatEmoteImage? {
		guard let (data, response) = try? await URLSession.shared.data(from: url),
			(response as? HTTPURLResponse)?.statusCode == 200
		else {
			return nil
		}

		return decode(data: data)
	}

	/// Decodes image data into a single image or animation frames, supporting GIF, APNG and animated WebP.
	nonisolated private static func decode(data: Data) -> ChatEmoteImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
			return nil
		}

		let frameCount = CGImageSourceGetCount(source)
		guard frameCount > 0 else {
			return nil
		}

		if frameCount > 1 {
			var frames = [UIImage]()
			var duration = 0.0

			for index in 0..<min(frameCount, maxAnimationFrameCount) {
				guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }

				frames.append(UIImage(cgImage: cgImage))
				duration += frameDelay(source: source, index: index)
			}

			if frames.count > 1 {
				return .animated(frames: frames, duration: max(0.05, duration))
			}
			if let frame = frames.first {
				return .image(frame)
			}
			return nil
		}

		guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
			return nil
		}

		return .image(UIImage(cgImage: cgImage))
	}

	/// Frame display delay in seconds, from GIF, APNG or animated WebP metadata.
	nonisolated private static func frameDelay(source: CGImageSource, index: Int) -> Double {
		guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
			return 0.1
		}

		for containerKey in [kCGImagePropertyGIFDictionary, kCGImagePropertyWebPDictionary] {
			guard let container = properties[containerKey] as? [CFString: Any] else { continue }

			if let delay = container[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? container[kCGImagePropertyGIFDelayTime] as? Double {
				return max(0.02, delay)
			}
		}

		if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
			let delay = png[kCGImagePropertyAPNGDelayTime] as? Double
		{
			return max(0.02, delay)
		}

		return 0.1
	}

	private static func scaledDisplayable(from image: ChatEmoteImage, fontSize: CGFloat) -> ChatEmoteImage {
		switch image {
		case .image(let image):
			return .image(scaled(image, fontSize: fontSize))
		case .animated(let frames, let duration):
			return .animated(frames: frames.map { scaled($0, fontSize: fontSize) }, duration: duration)
		}
	}

	/// Scales an emote image to render next to text of the given font size, preserving aspect ratio.
	private static func scaled(_ image: UIImage, fontSize: CGFloat) -> UIImage {
		let side = Double(fontSize) * emoteSizeFactor
		let aspect = image.size.width / max(1, image.size.height)
		let width = side * aspect
		let format = UIGraphicsImageRendererFormat()
		format.scale = 2
		format.opaque = false

		return UIGraphicsImageRenderer(size: CGSize(width: width, height: side), format: format).image { _ in
			image.draw(in: CGRect(x: 0, y: 0, width: width, height: side))
		}
	}
}
extension ChatEmoteCache {
	// - MARK: BTTV

	struct BTTVEmote: Decodable {
		let id: String
		let code: String

		var chatEmote: ChatEmote {
			return ChatEmote(
				id: "\(ChatEmoteProvider.bttv.rawValue)-\(id)",
				name: code,
				provider: .bttv,
				url: URL(string: "https://cdn.betterttv.net/emote/\(id)/2x")!
			)
		}
	}

	struct BTTVUser: Decodable {
		let channelEmotes: [BTTVEmote]?
		let sharedEmotes: [BTTVEmote]?
	}

	static func bttvEmotes(from data: Data) throws -> [ChatEmote] {
		return try decoder.decode([BTTVEmote].self, from: data).map(\.chatEmote)
	}

	static func bttvEmotes(from response: BTTVUser) -> [ChatEmote] {
		return ((response.channelEmotes ?? []) + (response.sharedEmotes ?? [])).map(\.chatEmote)
	}

	private static func fetchBTTVGlobalEmotes() async throws -> [ChatEmote] {
		let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try bttvEmotes(from: data)
	}

	private static func fetchBTTVEmotes(twitchUserID: String) async throws -> [ChatEmote] {
		let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(twitchUserID)")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try bttvEmotes(from: decoder.decode(BTTVUser.self, from: data))
	}

	// - MARK: 7TV

	struct SevenTVEmote: Decodable {
		let id: String
		let name: String

		var chatEmote: ChatEmote {
			return ChatEmote(
				id: "\(ChatEmoteProvider.sevenTV.rawValue)-\(id)",
				name: name,
				provider: .sevenTV,
				url: URL(string: "https://cdn.7tv.app/emote/\(id)/2x.webp")!
			)
		}
	}

	struct SevenTVEmoteSet: Decodable {
		let emotes: [SevenTVEmote]?
	}

	struct SevenTVGlobal: Decodable {
		let emotes: [SevenTVEmote]?
	}

	struct SevenTVUser: Decodable {
		let emoteSet: SevenTVEmoteSet?
	}

	static func sevenTVGlobalEmotes(from data: Data) throws -> [ChatEmote] {
		return try decoder.decode(SevenTVGlobal.self, from: data).emotes?.map(\.chatEmote) ?? []
	}

	static func sevenTVEmotes(from data: Data) throws -> [ChatEmote] {
		return try decoder.decode(SevenTVUser.self, from: data).emoteSet?.emotes?.map(\.chatEmote) ?? []
	}

	private static func fetchSevenTVGlobalEmotes() async throws -> [ChatEmote] {
		let url = URL(string: "https://7tv.io/v3/emote-sets/global")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try sevenTVGlobalEmotes(from: data)
	}

	private static func fetchSevenTVEmotes(twitchUserID: String) async throws -> [ChatEmote] {
		let url = URL(string: "https://7tv.io/v3/users/twitch/\(twitchUserID)")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try sevenTVEmotes(from: data)
	}

	// - MARK: FFZ

	struct FFZEmoticon: Decodable {
		let name: String
		let urls: [String: String]

		var chatEmote: ChatEmote? {
			guard let rawURL = urls["2"] ?? urls["1"] ?? urls["4"] else { return nil }

			let urlString = rawURL.hasPrefix("//") ? "https:\(rawURL)" : rawURL
			guard let url = URL(string: urlString) else { return nil }

			return ChatEmote(
				id: "\(ChatEmoteProvider.ffz.rawValue)-\(name)",
				name: name,
				provider: .ffz,
				url: url
			)
		}
	}

	struct FFZSet: Decodable {
		let emoticons: [FFZEmoticon]?
	}

	struct FFZResponse: Decodable {
		let sets: [String: FFZSet]?
	}

	static func ffzEmotes(from data: Data) throws -> [ChatEmote] {
		return try ffzEmotes(from: decoder.decode(FFZResponse.self, from: data))
	}

	static func ffzEmotes(from response: FFZResponse) -> [ChatEmote] {
		return (response.sets ?? [:]).values
			.flatMap { $0.emoticons ?? [] }
			.compactMap(\.chatEmote)
	}

	private static func fetchFFZGlobalEmotes() async throws -> [ChatEmote] {
		let url = URL(string: "https://api.frankerfacez.com/v1/set/global")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try ffzEmotes(from: data)
	}

	private static func fetchFFZEmotes(twitchUserID: String) async throws -> [ChatEmote] {
		let url = URL(string: "https://api.frankerfacez.com/v1/room/id/\(twitchUserID)")!
		let (data, _) = try await URLSession.shared.data(from: url)
		return try ffzEmotes(from: data)
	}
}
