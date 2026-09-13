//
//  TwitchTests.swift
//  ByteTests
//
//  Created by Kristian Pennacchia on 29/8/19.
//  Copyright © 2019 Kristian Pennacchia. All rights reserved.
//

import SwiftUI
import XCTest
@testable import Byte

@MainActor
class ByteTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testParsePrivMsg() {
        let line = "@badge-info=;badges=moderator/1,subscriber/12;color=#1E90FF;display-name=Pennacchia;emotes=;msg-id=abc-123 :pennacchia!pennacchia@pennacchia.tmi.twitch.tv PRIVMSG #somechannel :Hello, world!"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertNotNil(message)
        XCTAssertEqual(message?.author, "Pennacchia")
        XCTAssertEqual(message?.text, "Hello, world!")
        XCTAssertEqual(message?.id, "abc-123")
        XCTAssertEqual(message?.badges, [.moderator, .subscriber])
        XCTAssertEqual(message?.isAction, false)
    }

    func testParsePrivMsgWithoutTags() {
        let line = ":nick!nick@nick.tmi.twitch.tv PRIVMSG #somechannel :Just saying hi"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertNotNil(message)
        XCTAssertEqual(message?.author, "nick")
        XCTAssertEqual(message?.text, "Just saying hi")
        XCTAssertEqual(message?.badges, [])
    }

    func testParsePrivMsgAction() {
        let line = "@badges=;color=;display-name=Nick;emotes=;msg-id=abc :nick!nick@nick.tmi.twitch.tv PRIVMSG #somechannel :\u{01}ACTION waves\u{01}"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertNotNil(message)
        XCTAssertEqual(message?.text, "waves")
        XCTAssertEqual(message?.isAction, true)
    }

    func testParsePrivMsgWithEscapedName() {
        let line = "@badges=;color=;display-name=John\\sDoe;emotes=;msg-id=abc :nick!nick@nick.tmi.twitch.tv PRIVMSG #somechannel :hey"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertEqual(message?.author, "John Doe")
    }

    func testParseNonChatLines() {
        XCTAssertNil(TwitchChatConnection.parseMessage(line: "PING :tmi.twitch.tv"))
        XCTAssertNil(TwitchChatConnection.parseMessage(line: ":tmi.twitch.tv CLEARCHAT #somechannel"))
        XCTAssertNil(TwitchChatConnection.parseMessage(line: "@badges=;color=;display-name=Nick :nick!nick@nick.tmi.twitch.tv JOIN #somechannel"))
        XCTAssertNil(TwitchChatConnection.parseMessage(line: ""))
    }

    func testCommandExtraction() {
        XCTAssertEqual(TwitchChatConnection.command(of: "PING :tmi.twitch.tv"), "PING")
        XCTAssertEqual(TwitchChatConnection.command(of: ":tmi.twitch.tv 001 justinfan123 :Welcome, GLHF!"), "001")
        XCTAssertEqual(TwitchChatConnection.command(of: ":tmi.twitch.tv RECONNECT"), "RECONNECT")
        // A chat message containing the welcome code must not be mistaken for it.
        XCTAssertEqual(TwitchChatConnection.command(of: "@badges=;color=;display-name=Nick :nick!nick@nick.tmi.twitch.tv PRIVMSG #chan : 001 test"), "PRIVMSG")
        XCTAssertNil(TwitchChatConnection.command(of: "@tags-only"))
        XCTAssertNil(TwitchChatConnection.command(of: ""))
    }

    func testParseEmoteRanges() {
        let ranges = TwitchChatConnection.parseEmoteRanges("25:0-4,6-10/1902:12-16")

        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0].emoteID, "25")
        XCTAssertEqual(ranges[0].range.location, 0)
        XCTAssertEqual(ranges[0].range.length, 5)
        XCTAssertEqual(ranges[1].emoteID, "25")
        XCTAssertEqual(ranges[1].range.location, 6)
        XCTAssertEqual(ranges[2].emoteID, "1902")
        XCTAssertEqual(ranges[2].range.location, 12)
        XCTAssertTrue(TwitchChatConnection.parseEmoteRanges("").isEmpty)
        XCTAssertTrue(TwitchChatConnection.parseEmoteRanges("25:malformed").isEmpty)
    }

    func testParsePrivMsgEmotes() {
        let line = "@badges=;color=;display-name=Nick;emotes=25:0-4,12-16;msg-id=abc :nick!nick@nick.tmi.twitch.tv PRIVMSG #chan :Kappa Hello Kappa"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertEqual(message?.emotes.count, 2)
        XCTAssertEqual(message?.emotes.first?.emoteID, "25")
        XCTAssertEqual(message?.emotes.first?.range.location, 0)
        XCTAssertEqual(message?.emotes.first?.range.length, 5)
    }

    func testMessageSegmentsWithFirstPartyEmotes() {
        let line = "@badges=;color=;display-name=Nick;emotes=25:0-4,12-16 :nick!nick@nick.tmi.twitch.tv PRIVMSG #chan :Kappa Hello Kappa"
        let message = TwitchChatConnection.parseMessage(line: line)!
        let segments = message.segments(emoteCache: ChatEmoteCache())

        XCTAssertEqual(segments, [
            .emote(.twitch(id: "25")),
            .text(" Hello "),
            .emote(.twitch(id: "25")),
        ])
    }

    func testMessageSegmentsWithThirdPartyEmotes() {
        let cache = ChatEmoteCache()
        cache.add([
            ChatEmote(id: "bttv-abc", name: "KEKW", provider: .bttv, url: URL(string: "https://cdn.betterttv.net/emote/abc/2x")!),
        ])

        let message = ChatMessage(id: "1", author: "Nick", color: .white, badges: [], text: "Hello KEKW world", emotes: [], isAction: false)
        let segments = message.segments(emoteCache: cache)

        XCTAssertEqual(segments, [
            .text("Hello "),
            .emote(ChatEmote(id: "bttv-abc", name: "KEKW", provider: .bttv, url: URL(string: "https://cdn.betterttv.net/emote/abc/2x")!)),
            .text(" world"),
        ])
        XCTAssertEqual(segments.emoteIDs, "bttv-abc")
    }

    func testParseActionEmoteOffset() {
        // Emote positions of /me messages include the \u{01}ACTION wrapper.
        let line = "@badges=;color=;display-name=Nick;emotes=25:8-12 :nick!nick@nick.tmi.twitch.tv PRIVMSG #chan :\u{01}ACTION Kappa waves\u{01}"
        let message = TwitchChatConnection.parseMessage(line: line)

        XCTAssertEqual(message?.text, "Kappa waves")
        XCTAssertEqual(message?.isAction, true)
        XCTAssertEqual(message?.emotes.first?.range.location, 0)
        XCTAssertEqual(message?.emotes.first?.range.length, 5)
    }

    func testWindowFrameIsFlushAndWidthIsQuarter() {
        let area = CGSize(width: 1000, height: 800)

        XCTAssertEqual(ChatOverlayView.windowFrame(position: .bottomRight, heightFraction: 0.5, area: area), CGRect(x: 750, y: 400, width: 250, height: 400))
        XCTAssertEqual(ChatOverlayView.windowFrame(position: .topLeft, heightFraction: 0.25, area: area), CGRect(x: 0, y: 0, width: 250, height: 200))
        XCTAssertEqual(ChatOverlayView.windowFrame(position: .bottomCenter, heightFraction: 1, area: area), CGRect(x: 375, y: 0, width: 250, height: 800))
        XCTAssertEqual(ChatOverlayView.windowFrame(position: .leftCenter, heightFraction: 0.75, area: area), CGRect(x: 0, y: 100, width: 250, height: 600))
        XCTAssertEqual(ChatOverlayView.windowFrame(position: .topRight, heightFraction: 0.75, area: area), CGRect(x: 750, y: 0, width: 250, height: 600))
    }

    func testCornerRadiiOnlyOnCornersNotTouchingEdges() {
        let radius: CGFloat = 14

        XCTAssertEqual(ChatPosition.bottomRight.cornerRadii(radius: radius), ChatCornerRadii(topLeading: radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0))
        XCTAssertEqual(ChatPosition.bottomLeft.cornerRadii(radius: radius), ChatCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius))
        XCTAssertEqual(ChatPosition.topLeft.cornerRadii(radius: radius), ChatCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: 0))
        XCTAssertEqual(ChatPosition.topRight.cornerRadii(radius: radius), ChatCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: 0, topTrailing: 0))
        XCTAssertEqual(ChatPosition.bottomCenter.cornerRadii(radius: radius), ChatCornerRadii(topLeading: radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius))
        XCTAssertEqual(ChatPosition.topCenter.cornerRadii(radius: radius), ChatCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0))
        XCTAssertEqual(ChatPosition.leftCenter.cornerRadii(radius: radius), ChatCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: radius))
        XCTAssertEqual(ChatPosition.rightCenter.cornerRadii(radius: radius), ChatCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: 0, topTrailing: 0))
    }

    func testTokensPreserveWhitespace() {
        XCTAssertEqual(ChatMessage.tokens(of: "a  b c"), ["a", "  ", "b", " ", "c"])
        XCTAssertEqual(ChatMessage.tokens(of: "   "), ["   "])
        XCTAssertEqual(ChatMessage.tokens(of: ""), [])
    }

    func testBTTVEmoteDecoding() throws {
        let data = Data("""
        [{"id":"55b7ee61e2b311a08b90c9d6","code":"Kappa","imageType":"png"},{"id":"55b7ee61431a4bd96e1ce729","code":"HeyGuys","imageType":"gif"}]
        """.utf8)
        let emotes = try ChatEmoteCache.bttvEmotes(from: data)

        XCTAssertEqual(emotes.count, 2)
        XCTAssertEqual(emotes[0].name, "Kappa")
        XCTAssertEqual(emotes[0].provider, .bttv)
        XCTAssertEqual(emotes[0].url.absoluteString, "https://cdn.betterttv.net/emote/55b7ee61e2b311a08b90c9d6/2x")
    }

    func testBTTVUserEmoteDecoding() throws {
        let data = Data("""
        {"id":"123","name":"user","channelEmotes":[{"id":"e1","code":"KEKW","imageType":"png"}],"sharedEmotes":[{"id":"e2","code":"Sadge","imageType":"png"}]}
        """.utf8)
        let emotes = ChatEmoteCache.bttvEmotes(from: try JSONDecoder().decode(ChatEmoteCache.BTTVUser.self, from: data))

        XCTAssertEqual(emotes.map(\.name), ["KEKW", "Sadge"])
    }

    func testSevenTVEmoteDecoding() throws {
        let global = try ChatEmoteCache.sevenTVGlobalEmotes(from: Data("""
        {"id":"global","name":"Global Emotes","emotes":[{"id":"62c0c9ebab87a34ffaaa12f3","name":"KEKW"}]}
        """.utf8))
        XCTAssertEqual(global.count, 1)
        XCTAssertEqual(global[0].name, "KEKW")
        XCTAssertEqual(global[0].provider, .sevenTV)
        XCTAssertEqual(global[0].url.absoluteString, "https://cdn.7tv.app/emote/62c0c9ebab87a34ffaaa12f3/2x.webp")

        let channel = try ChatEmoteCache.sevenTVEmotes(from: Data("""
        {"user":{"id":"1"},"emote_set":{"id":"s1","emotes":[{"id":"e1","name":"peepoHappy"}]}}
        """.utf8))
        XCTAssertEqual(channel.map(\.name), ["peepoHappy"])

        // A user without an emote set yields no emotes.
        let empty = try ChatEmoteCache.sevenTVEmotes(from: Data("""
        {"user":{"id":"1"},"emote_set":null}
        """.utf8))
        XCTAssertTrue(empty.isEmpty)
    }

    func testFFZEmoteDecoding() throws {
        let data = Data("""
        {"default_sets":[3],"sets":{"3":{"title":"Global","emoticons":[{"id":1,"name":"FrankerZ","urls":{"1":"//cdn.frankerfacez.com/emote/1/1","2":"//cdn.frankerfacez.com/emote/1/2"}}]}}}
        """.utf8)
        let emotes = try ChatEmoteCache.ffzEmotes(from: data)

        XCTAssertEqual(emotes.count, 1)
        XCTAssertEqual(emotes[0].name, "FrankerZ")
        XCTAssertEqual(emotes[0].provider, .ffz)
        XCTAssertEqual(emotes[0].url.absoluteString, "https://cdn.frankerfacez.com/emote/1/2")
    }

    func testFontSizeScalesWithWindow() {
        var settings = ChatSettings.default

        // Fullscreen stream: only the font size setting applies.
        XCTAssertEqual(ChatOverlayView.fontSize(base: 15, settings: settings, windowScale: 1), 15)

        // Font size setting of 125%.
        settings.fontSize = .hundredTwentyFive
        XCTAssertEqual(ChatOverlayView.fontSize(base: 15, settings: settings, windowScale: 1), 15 * 1.25)

        // Two streams share the window: the font scales to half.
        XCTAssertEqual(ChatOverlayView.fontSize(base: 15, settings: settings, windowScale: 0.5), 15 * 1.25 * 0.5)

        // Font size setting of 200% with the window at half size.
        settings.fontSize = .twoHundred
        XCTAssertEqual(ChatOverlayView.fontSize(base: 15, settings: settings, windowScale: 0.5), 15)
    }

    func testAuthorColorFallsBackToPalette() {
        XCTAssertNotNil(TwitchChatConnection.authorColor(nil, author: "nick"))
        XCTAssertNotNil(TwitchChatConnection.authorColor("#1E90FF", author: "nick"))
        XCTAssertNil(Color(hex: "not-a-color"))
    }

    func testChatSettingsStorePersistsPerStream() {
        let suiteName = "ChatSettingsStoreTests"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = ChatSettingsStore(userDefaults: userDefaults)

        // Defaults are used when no per-stream settings exist.
        XCTAssertEqual(store.settings(for: "stream1"), .default)

        var settings = store.settings(for: "stream1")
        settings.size = .hundred
        settings.position = .topLeft
        settings.backgroundOpacity = 40
        settings.fontSize = .fifty
        settings.isEnabled = false
        store.update(settings, for: "stream1")

        // The settings are remembered for the stream and do not affect others.
        XCTAssertEqual(store.settings(for: "stream1"), settings)
        XCTAssertEqual(store.settings(for: "stream2"), .default)

        // A new store instance loads the persisted settings.
        let reloadedStore = ChatSettingsStore(userDefaults: userDefaults)
        XCTAssertEqual(reloadedStore.settings(for: "stream1"), settings)

        // Resetting a stream restores the global default.
        reloadedStore.reset(for: "stream1")
        XCTAssertEqual(reloadedStore.settings(for: "stream1"), .default)

        userDefaults.removePersistentDomain(forName: suiteName)
    }
}