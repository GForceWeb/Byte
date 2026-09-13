//
//  ChatEmote.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import Foundation

enum ChatEmoteProvider: String {
	case twitch
	case bttv
	case sevenTV = "7tv"
	case ffz
}

struct ChatEmote: Equatable {
	let id: String
	let name: String
	let provider: ChatEmoteProvider
	let url: URL

	/// Creates a first-party Twitch emote, served from the Twitch CDN by emote ID.
	static func twitch(id: String) -> ChatEmote {
		return ChatEmote(
			id: "\(ChatEmoteProvider.twitch.rawValue)-\(id)",
			name: "",
			provider: .twitch,
			url: URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/default/dark/2.0")!
		)
	}
}

/// A first-party Twitch emote reference from the IRC `emotes` tag, positioned within the message.
struct ChatEmoteRange: Equatable {
	let emoteID: String
	let range: NSRange
}

enum ChatMessageSegment: Equatable {
	case text(String)
	case emote(ChatEmote)
}

extension Array where Element == ChatMessageSegment {
	/// Stable identifier of the emotes contained in the segments, used to (re)load their images.
	var emoteIDs: String {
		return compactMap { segment -> String? in
			if case .emote(let emote) = segment { return emote.id }
			return nil
		}
		.joined(separator: ",")
	}
}

@MainActor
extension ChatMessage {
	/// Splits the message into text and emote segments, merging consecutive text into single runs.
	/// First-party emotes are placed by the IRC `emotes` tag ranges, remaining words are matched
	/// against third-party emote sets.
	func segments(emoteCache: ChatEmoteCache) -> [ChatMessageSegment] {
		var segments = [ChatMessageSegment]()
		let text = self.text as NSString
		var cursor = 0

		for emoteRange in emotes.sorted(by: { $0.range.location < $1.range.location }) {
			guard emoteRange.range.location >= cursor, emoteRange.range.location + emoteRange.range.length <= text.length else { continue }

			if emoteRange.range.location > cursor {
				Self.append(words: text.substring(with: NSRange(location: cursor, length: emoteRange.range.location - cursor)), to: &segments, emoteCache: emoteCache)
			}

			segments.append(.emote(.twitch(id: emoteRange.emoteID)))
			cursor = emoteRange.range.location + emoteRange.range.length
		}

		if cursor < text.length {
			Self.append(words: text.substring(from: cursor), to: &segments, emoteCache: emoteCache)
		}

		return Self.mergeTextRuns(segments)
	}

	private static func append(words raw: String, to segments: inout [ChatMessageSegment], emoteCache: ChatEmoteCache) {
		for token in tokens(of: raw) {
			if let emote = emoteCache.emote(named: token) {
				segments.append(.emote(emote))
			} else {
				segments.append(.text(token))
			}
		}
	}

	private static func mergeTextRuns(_ segments: [ChatMessageSegment]) -> [ChatMessageSegment] {
		var merged = [ChatMessageSegment]()

		for segment in segments {
			if case .text(let new) = segment, case .text(let existing)? = merged.last {
				merged[merged.count - 1] = .text(existing + new)
			} else {
				merged.append(segment)
			}
		}

		return merged
	}

	/// Splits a string into runs of whitespace and runs of non-whitespace, preserving the original spacing.
	static func tokens(of string: String) -> [String] {
		var tokens = [String]()
		var current = ""
		var currentIsWhitespace: Bool?

		func flush() {
			guard current.isEmpty == false else { return }

			tokens.append(current)
			current = ""
		}

		for character in string {
			let isWhitespace = character.isWhitespace
			if let established = currentIsWhitespace, established != isWhitespace {
				flush()
			}
			currentIsWhitespace = isWhitespace
			current.append(character)
		}
		flush()

		return tokens
	}
}