import Foundation
import Testing
@testable import SwiftStarKit

struct EngineModelCatalogTests {
    private static let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/engine/models.json")

    private static func sample() throws -> EngineModelList {
        let data = try Data(contentsOf: sampleURL)
        return try EngineModelList.decode(data).get()
    }

    @Test func decodesSampleList() throws {
        let list = try Self.sample()
        #expect(list.defaultModelID == "laguna-xs-2.1")
        #expect(list.models.map(\.id) == [
            "deepseek-v4-flash", "laguna-xs-2.1", "laguna-s-2.1", "qwen3.8-flash-next", "mellum-2"])
        let laguna = list.models[1]
        #expect(laguna.displayName == "Laguna XS 2.1")
        #expect(laguna.measuredContexts.map(\.context) == [4096, 20000, 65536])
        #expect(laguna.measuredContexts[1].planGiB == 23.67)
        #expect(!list.models[2].onThisMac)
        #expect(list.models[2].fits == nil)
    }

    @Test func decodesRealEngineCapture() throws {
        let url = Self.sampleURL.deletingLastPathComponent().appendingPathComponent("models-real.json")
        let list = try EngineModelList.decode(Data(contentsOf: url)).get()
        #expect(list.models.count == 4)
        #expect(list.defaultModelID == "laguna-xs-2.1")
        #expect(list.savedModelID == nil)
        #expect(list.model(id: "laguna-xs-2.1")?.defaultContext == 65536)
        let items = ModelMenu.items(list: list, settingsID: "", loadedID: nil)
        #expect(items.first { $0.value == "qwen3.8-flash-next-q2" }?.disabledReason == "not on this Mac")
        #expect(items.first { $0.value == "laguna-xs-2.1" }?.disabledReason == nil)
    }

    @Test func ignoresUnknownKeys() throws {
        let json = #"{"schema_version":1,"extra":true,"models":[{"id":"m","display_name":"M","family":"f","on_this_mac":true,"downloadable":false,"runs_in_tui":true,"measured_contexts":[],"zzz":1}]}"#
        let list = try EngineModelList.decode(Data(json.utf8)).get()
        #expect(list.models.map(\.id) == ["m"])
        #expect(list.defaultModelID == nil)
    }

    @Test func wrongSchemaVersionFails() {
        let result = EngineModelList.decode(Data(#"{"schema_version":2,"models":[]}"#.utf8))
        #expect(result == .failure(.unsupportedSchema(2)))
        if case .failure(.malformed) = EngineModelList.decode(Data("nope".utf8)) {} else {
            Issue.record("garbage should be malformed")
        }
    }

    @Test func modelMenuTicksSettingsChoice() throws {
        let list = try Self.sample()
        let items = ModelMenu.items(list: list, settingsID: "laguna-xs-2.1", loadedID: "qwen3.8-flash-next")
        #expect(items.first?.title == "Engine default (laguna-xs-2.1)")
        #expect(items.first?.value == "")
        #expect(items.first?.isChecked == false)
        #expect(items.filter(\.isChecked).map(\.value) == ["laguna-xs-2.1"])
        #expect(ModelMenu.items(list: list, settingsID: " ", loadedID: nil).first?.isChecked == true)
        // A typed id the engine does not list stays visible and ticked.
        let custom = ModelMenu.items(list: list, settingsID: "my-model", loadedID: nil)
        #expect(custom.last?.value == "my-model")
        #expect(custom.last?.isChecked == true)
    }

    @Test func modelMenuDisablesWithReason() throws {
        let list = try Self.sample()
        let items = ModelMenu.items(list: list, settingsID: "", loadedID: nil)
        func reason(_ id: String) -> String? { items.first { $0.value == id }?.disabledReason }
        #expect(reason("laguna-s-2.1") == "not on this Mac")
        #expect(reason("deepseek-v4-flash") == "doesn't fit")
        #expect(reason("mellum-2") == "not usable in the TUI")
        #expect(reason("laguna-xs-2.1") == nil)
        #expect(reason("qwen3.8-flash-next") == nil)
    }

    @Test func modelMenuFallbackWithoutList() {
        let none = ModelMenu.items(list: nil, settingsID: "", loadedID: nil)
        #expect(none.map(\.title) == ["Engine default"])
        #expect(none.first?.isChecked == true)
        let some = ModelMenu.items(list: nil, settingsID: "laguna-xs-2.1", loadedID: nil)
        #expect(some.map(\.value) == ["", "laguna-xs-2.1"])
        #expect(some.filter(\.isChecked).map(\.value) == ["laguna-xs-2.1"])
        #expect(some.allSatisfy { $0.disabledReason == nil })
    }

    @Test func contextMenuListsMeasuredAndRoundSizes() throws {
        let list = try Self.sample()
        let items = ContextMenu.items(
            list: list, modelID: "laguna-xs-2.1", settingsContext: 20000, loaded: 20000)
        #expect(items.first?.title == "Engine default (65,536)")
        #expect(items.first?.value == 0)
        let sizes = items.dropFirst().map(\.value)
        // Measured 4096, 20000, 65536 plus round sizes up to 2 x 65536.
        #expect(sizes == [4096, 8192, 16384, 20000, 32768, 65536, 131072])
        #expect(items.filter(\.isChecked).map(\.value) == [20000])
        #expect(items.first { $0.value == 20000 }?.title.contains("23.7 GiB") == true)

        // One measured size: round sizes stop at twice it, measured always stay.
        let qwen = ContextMenu.items(
            list: list, modelID: "qwen3.8-flash-next", settingsContext: 0, loaded: nil)
        #expect(qwen.dropFirst().map(\.value) == [8192, 16384, 20000, 32768])
        #expect(qwen.first?.isChecked == true)
        // Empty model id resolves through the engine default.
        let dflt = ContextMenu.items(list: list, modelID: nil, settingsContext: 0, loaded: nil)
        #expect(dflt.dropFirst().map(\.value) == [4096, 8192, 16384, 20000, 32768, 65536, 131072])
    }

    @Test func contextMenuFallbackRoundSizes() throws {
        let none = ContextMenu.items(list: nil, modelID: nil, settingsContext: 0, loaded: nil)
        #expect(none.map(\.value) == [0, 8192, 16384, 32768, 65536])
        #expect(none.first?.title == "Engine default")
        // A current size outside the round set stays visible and ticked.
        let odd = ContextMenu.items(list: nil, modelID: nil, settingsContext: 20000, loaded: nil)
        #expect(odd.map(\.value) == [0, 8192, 16384, 20000, 32768, 65536])
        #expect(odd.filter(\.isChecked).map(\.value) == [20000])
        // A model the list does not know falls back too.
        let list = try Self.sample()
        let unknown = ContextMenu.items(list: list, modelID: "other", settingsContext: 0, loaded: nil)
        #expect(unknown.map(\.value) == [0, 8192, 16384, 32768, 65536])
    }

    @Test func recentWorkspacesDedupesCapsOrders() {
        #expect(RecentWorkspaces.updated([], adding: "/a") == ["/a"])
        #expect(RecentWorkspaces.updated(["/a", "/b", "/c"], adding: "/b") == ["/b", "/a", "/c"])
        let full = ["/1", "/2", "/3", "/4", "/5"]
        #expect(RecentWorkspaces.updated(full, adding: "/6") == ["/6", "/1", "/2", "/3", "/4"])
        #expect(RecentWorkspaces.updated(full, adding: "/6", cap: 2) == ["/6", "/1"])
    }

    @Test func recentWorkspaceItemsDisableMissingFolders() {
        let items = RecentWorkspaces.items(
            ["/here", "/gone"], current: "/here", exists: { $0 == "/here" })
        #expect(items.map(\.title) == ["here", "gone"])
        #expect(items.map(\.isChecked) == [true, false])
        #expect(items.map(\.disabledReason) == [nil, "folder not found"])
    }
}
