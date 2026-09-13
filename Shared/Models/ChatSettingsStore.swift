//
//  ChatSettingsStore.swift
//  Byte
//
//  Created by Kristian Pennacchia on 13/9/2026.
//  Copyright © 2026 Kristian Pennacchia. All rights reserved.
//

import Foundation
import Combine
import OSLog

/// Stores the chat overlay settings for each stream, persisting per-stream overrides in user defaults.
@MainActor
final class ChatSettingsStore: ObservableObject {
	private static let storageKey = "chatSettings"

	@Published private(set) var streamSettings = [String: ChatSettings]()

	private let userDefaults: UserDefaults

	init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		streamSettings = Self.load(userDefaults: userDefaults)
	}

	func settings(for streamID: String) -> ChatSettings {
		return streamSettings[streamID] ?? .default
	}

	func update(_ settings: ChatSettings, for streamID: String) {
		streamSettings[streamID] = settings
		persist()
	}

	/// Removes any per-stream overrides, restoring the global default settings.
	func reset(for streamID: String) {
		guard streamSettings[streamID] != nil else { return }

		streamSettings[streamID] = nil
		persist()
	}

	private func persist() {
		guard let data = try? JSONEncoder().encode(streamSettings) else {
			Logger.twitch.error("Failed encoding chat settings for persistence.")
			return
		}

		userDefaults.set(data, forKey: Self.storageKey)
	}

	private static func load(userDefaults: UserDefaults) -> [String: ChatSettings] {
		guard let data = userDefaults.data(forKey: storageKey) else {
			return [:]
		}

		do {
			return try JSONDecoder().decode([String: ChatSettings].self, from: data)
		} catch {
			Logger.twitch.error("Failed decoding persisted chat settings. \(error.localizedDescription)")
			return [:]
		}
	}
}