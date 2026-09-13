//
//  TwitchChatConnection.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import OSLog

enum ChatBadge: Equatable {
	case broadcaster
	case moderator
	case vip
	case subscriber
	case founder
}

struct ChatMessage: Identifiable, Equatable {
	let id: String
	let author: String
	let color: Color
	let badges: [ChatBadge]
	let text: String
	let emotes: [ChatEmoteRange]
	let isAction: Bool
}

/// Connects to a Twitch channel chat as an anonymous reader over the IRC websocket bridge.
@MainActor
final class TwitchChatConnection: ObservableObject {
	@Published private(set) var messages = [ChatMessage]()
	@Published private(set) var isConnected = false

	static let serverURL = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
	static let maxStoredMessages = 80
	static let flushInterval: TimeInterval = 0.3
	static let maxReconnectDelay: TimeInterval = 30

	private let session: URLSession
	private var socket: URLSessionWebSocketTask?
	private var reconnectTask: Task<Void, Never>?
	private var flushTask: Task<Void, Never>?
	private var pendingMessages = [ChatMessage]()
	private var wantedLogin: String?
	private var reconnectAttempt = 0

	init(session: URLSession = URLSession(configuration: .default)) {
		self.session = session
	}

	/// Connects to the chat of the given channel login, disconnecting from any prior channel.
	func connect(login: String) {
		let normalizedLogin = login.lowercased()
		guard wantedLogin != normalizedLogin else { return }

		disconnect()
		wantedLogin = normalizedLogin
		openSocket()
	}

	func disconnect() {
		wantedLogin = nil
		reconnectAttempt = 0

		reconnectTask?.cancel()
		reconnectTask = nil
		flushTask?.cancel()
		flushTask = nil

		socket?.cancel(with: .normalClosure, reason: nil)
		socket = nil

		pendingMessages.removeAll()
		messages.removeAll()
		isConnected = false
	}

	deinit {
		reconnectTask?.cancel()
		flushTask?.cancel()
		socket?.cancel(with: .normalClosure, reason: nil)
	}
}

private extension TwitchChatConnection {
	func openSocket() {
		guard let wantedLogin else { return }

		socket?.cancel(with: .goingAway, reason: nil)

		let task = session.webSocketTask(with: Self.serverURL)
		socket = task
		task.resume()

		// Anonymous reading uses a `justinfan` nickname, no OAuth is required.
		send("CAP REQ :twitch.tv/tags twitch.tv/commands")
		send("PASS SCHMOOPIIE")
		send("NICK justinfan\(Int.random(in: 0..<100_000))")

		isConnected = true
		receiveNext()
		scheduleFlush()
	}

	func send(_ line: String) {
		guard let socket else { return }

		socket.send(.string(line)) { [weak self] error in
			if error != nil {
				Task { @MainActor [weak self] in
					// Ignore errors from sockets that have since been replaced.
					guard let self, self.socket === socket else { return }

					self.scheduleReconnect()
				}
			}
		}
	}

	func receiveNext() {
		guard let socket else { return }

		socket.receive { [weak self] result in
			Task { @MainActor [weak self] in
				guard let self else { return }

				switch result {
				case .success(let message):
					self.reconnectAttempt = 0
					if case .string(let string) = message {
						string
							.split(separator: "\r\n", omittingEmptySubsequences: true)
							.forEach { self.handleLine(String($0)) }
					}
					self.receiveNext()
				case .failure(let error):
					// Ignore errors from sockets that have since been replaced.
					guard self.socket === socket else { return }

					Logger.twitch.error("Twitch chat websocket error. \(error.localizedDescription)")
					self.scheduleReconnect()
				}
			}
		}
	}

	func handleLine(_ line: String) {
		switch Self.command(of: line) {
		case "PING":
			// Echo the ping token back to keep the connection alive.
			send("PONG\(line.dropFirst("PING".count))")
		case "RECONNECT":
			scheduleReconnect()
		case "001":
			// The server welcomed us, join the channel.
			if let wantedLogin {
				send("JOIN #\(wantedLogin)")
			}
		case "PRIVMSG":
			if let message = Self.parseMessage(line: line) {
				pendingMessages.append(message)
			}
		default:
			break
		}
	}

	func scheduleReconnect() {
		guard wantedLogin != nil else { return }

		socket?.cancel(with: .abnormalClosure, reason: nil)
		socket = nil
		isConnected = false

		reconnectTask?.cancel()
		reconnectAttempt += 1

		let delay = min(Double(reconnectAttempt) * 2, Self.maxReconnectDelay)
		reconnectTask = Task { @MainActor [weak self] in
			try? await Task<Never, Never>.sleep(seconds: delay)
			guard !Task.isCancelled else { return }

			self?.openSocket()
		}
	}

	func scheduleFlush() {
		flushTask?.cancel()
		flushTask = Task { @MainActor [weak self] in
			try? await Task<Never, Never>.sleep(seconds: Self.flushInterval)
			guard let self, !Task.isCancelled else { return }

			flush()
			if socket != nil {
				scheduleFlush()
			}
		}
	}

	func flush() {
		guard pendingMessages.isEmpty == false else { return }

		messages.append(contentsOf: pendingMessages)
		pendingMessages.removeAll()

		if messages.count > Self.maxStoredMessages {
			messages.removeFirst(messages.count - Self.maxStoredMessages)
		}
	}
}

extension TwitchChatConnection {
	// - MARK: IRC Parsing

	/// Returns the IRC command of a line, e.g. `PRIVMSG`, skipping the tags and prefix.
	static func command(of line: String) -> String? {
		var remainder = Substring(line)

		if remainder.hasPrefix("@") {
			guard let spaceIndex = remainder.firstIndex(of: " ") else { return nil }
			remainder = remainder[remainder.index(after: spaceIndex)...]
		}

		if remainder.hasPrefix(":") {
			guard let spaceIndex = remainder.firstIndex(of: " ") else { return nil }
			remainder = remainder[remainder.index(after: spaceIndex)...]
		}

		let command = remainder.prefix(while: { $0 != " " })
		return command.isEmpty ? nil : String(command)
	}

	/// Parses the `emotes` IRC tag, e.g. `25:0-4,6-10/1902:12-16`, into emote references.
	/// Positions are UTF-16 code unit indices into the message text, inclusive of both ends.
	static func parseEmoteRanges(_ raw: String) -> [ChatEmoteRange] {
		guard raw.isEmpty == false else { return [] }

		return raw
			.split(separator: "/")
			.flatMap { entry -> [ChatEmoteRange] in
				let parts = entry.split(separator: ":", maxSplits: 1)
				guard parts.count == 2 else { return [] }

				let emoteID = String(parts[0])
				return parts[1]
					.split(separator: ",")
					.compactMap { rawRange -> ChatEmoteRange? in
						let bounds = rawRange.split(separator: "-")
						guard bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), end >= start else { return nil }

						return ChatEmoteRange(emoteID: emoteID, range: NSRange(location: start, length: end - start + 1))
					}
			}
	}

	/// Parses a Twitch IRC line into a chat message, returning nil for non-chat or unparsable lines.
	static func parseMessage(line: String) -> ChatMessage? {
		var tags = [String: String]()
		var remainder = Substring(line)

		if line.hasPrefix("@") {
			let parts = line.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
			tags = parseTags(String(parts.first ?? ""))
			remainder = parts.count > 1 ? parts[1] : ""
		}

		guard remainder.hasPrefix(":"), let firstSpace = remainder.firstIndex(of: " ") else { return nil }

		let nick = remainder[remainder.index(after: remainder.startIndex)..<firstSpace].prefix(while: { $0 != "!" })
		let commandAndParams = remainder[remainder.index(after: firstSpace)...]

		guard commandAndParams.hasPrefix("PRIVMSG "), nick.isEmpty == false else {
			return nil
		}

		let afterCommand = commandAndParams.dropFirst("PRIVMSG".count)
		guard let textRange = afterCommand.range(of: " :") else { return nil }

		var text = String(afterCommand[textRange.upperBound...])
		var isAction = false
		if text.hasPrefix("\u{01}ACTION "), text.hasSuffix("\u{01}") {
			text = String(text.dropFirst("\u{01}ACTION ".count).dropLast())
			isAction = true
		}

		let displayName = tags["display-name"].map { unescape($0) } ?? ""
		let author = displayName.isEmpty ? String(nick) : displayName

		// Emote tag positions of action messages include the '\u{01}ACTION ' wrapper.
		let emoteOffset = isAction ? "\u{01}ACTION ".count : 0
		let emotes = parseEmoteRanges(tags["emotes"] ?? "").compactMap { emoteRange -> ChatEmoteRange? in
			guard emoteRange.range.location >= emoteOffset else { return nil }

			return ChatEmoteRange(emoteID: emoteRange.emoteID, range: NSRange(location: emoteRange.range.location - emoteOffset, length: emoteRange.range.length))
		}

		return ChatMessage(
			id: tags["msg-id"] ?? UUID().uuidString,
			author: author,
			color: authorColor(tags["color"], author: author),
			badges: parseBadges(tags["badges"] ?? ""),
			text: text,
			emotes: emotes,
			isAction: isAction
		)
	}

	static func parseTags(_ rawTags: String) -> [String: String] {
		return rawTags
			.split(separator: ";")
			.reduce(into: [String: String]()) { result, rawTag in
				let parts = rawTag.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
				if parts.count == 2 {
					result[String(parts[0])] = String(parts[1])
				}
			}
	}

	static func parseBadges(_ rawBadges: String) -> [ChatBadge] {
		return rawBadges
			.split(separator: ",")
			.compactMap { rawBadge in
				switch rawBadge.split(separator: "/").first {
				case "broadcaster":
					return .broadcaster
				case "moderator":
					return .moderator
				case "vip":
					return .vip
				case "subscriber", "founder":
					return rawBadge.hasPrefix("founder") ? .founder : .subscriber
				default:
					return nil
				}
			}
	}

	/// Determines the message author color, falling back to the Twitch default palette.
	static func authorColor(_ colorTag: String?, author: String) -> Color {
		if let colorTag, colorTag.isEmpty == false, let color = Color(hex: colorTag) {
			return color
		}

		// Twitch's default colors used when a viewer has no selected color.
		let palette = [
			"#FF0000", "#0000FF", "#00FF00", "#B22222", "#FF7F50", "#9ACD32",
			"#FF4500", "#2E8B57", "#DA70D6", "#DAA520", "#D2691E", "#5F9EA0",
			"#1E90FF", "#FF69B4", "#8A2BE2", "#00FF7F",
		]

		var hash: UInt64 = 5381
		for scalar in author.unicodeScalars {
			hash = (hash &* 33) &+ UInt64(scalar.value)
		}

		return Color(hex: palette[Int(hash % UInt64(palette.count))]) ?? .white
	}

	static func unescape(_ string: String) -> String {
		return string
			.replacingOccurrences(of: "\\s", with: " ")
			.replacingOccurrences(of: "\\:", with: ":")
			.replacingOccurrences(of: "\\\\", with: "\\")
			.replacingOccurrences(of: "\\r", with: "\r")
			.replacingOccurrences(of: "\\n", with: "\n")
	}
}