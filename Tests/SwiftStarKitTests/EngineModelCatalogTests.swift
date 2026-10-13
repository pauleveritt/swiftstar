import Foundation
import Testing
@testable import SwiftStarKit

struct EngineModelCatalogTests {
    private static func sample() throws -> EngineModelList { try Fixtures.modelList("models.json") }
    private static func real() throws -> EngineModelList { try Fixtures.modelList("models-real.json") }

    // Dropped in SU.5b: cacheKeySamePathSameMtimeIsEqual, cacheKeyChangedMtimeInvalidates and
    // cacheKeyChangedPathInvalidates, which tested the compiler's synthesised `==`.

    struct ValidatedCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let saved: String
        let useList: Bool
        let modelID: String
        let notice: String?
    }

    static let validatedCases: [ValidatedCase] = [
        .init(testDescription: "validatedKeepsOfferedId", saved: "qwen3.8-27b", useList: true,
              modelID: "qwen3.8-27b", notice: nil),
        .init(testDescription: "validatedClearsDroppedId", saved: "laguna-xs-2.1", useList: true, modelID: "",
              notice: "laguna-xs-2.1 isn't offered by the engine; using the engine default"),
        .init(testDescription: "validatedKeepsEmpty", saved: "", useList: true, modelID: "", notice: nil),
        .init(testDescription: "validatedKeepsIdWithoutList", saved: "laguna-xs-2.1", useList: false,
              modelID: "laguna-xs-2.1", notice: nil),
    ]

    @Test(arguments: validatedCases) func validated(_ c: ValidatedCase) throws {
        let r = ModelMenu.validated(saved: c.saved, list: c.useList ? try Self.real() : nil)
        #expect(r.modelID == c.modelID)
        #expect(r.notice == c.notice)
    }

    @Test(arguments: [
        (EngineSessionPhase.running, ModelMenuAction.sendModelCommand),
        (.idle, .restart), (.starting, .restart), (.quitting, .restart), (.notFound([]), .restart),
        (.ended(EngineExit(code: 0, message: "done")), .restart),
    ]) func selectionActionPerPhase(_ phase: EngineSessionPhase, _ action: ModelMenuAction) {
        #expect(ModelMenu.selectionAction(phase: phase) == action)
    }

    @Test(arguments: [
        (String?.none, "", "Engine default"), (nil, "x", "x"), ("a", "b", "a → b"), ("a", "a", "a"), ("a", "", "a"),
    ]) func modelLabelLoadedToChosen(_ loaded: String?, _ chosen: String, _ label: String) {
        #expect(ModelMenu.label(loaded: loaded, chosen: chosen) == label)
    }

    @Test(arguments: [
        (Int?.none, 0, "Default ctx"), (nil, 8192, "8192 ctx"), (8192, 0, "8192 ctx"), (8192, 4096, "8192 → 4096 ctx"),
    ]) func contextLabelLoadedToChosen(_ loaded: Int?, _ chosen: Int, _ label: String) {
        #expect(ContextMenu.label(loaded: loaded, chosen: chosen) == label)
    }

    @Test(arguments: [(" 4096 ", Int?.some(4096)), ("0", nil), ("x", nil), ("", nil)])
    func contextParseCustom(_ text: String, _ size: Int?) {
        #expect(ContextMenu.parseCustom(text) == size)
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
        // ds4-engine main (TUI.35) sends no `schema_version`, `default_model_id`
        // or `saved_model_id`, and names the context field `context`; the
        // decoder treats the first as version 1 and falls back for the second.
        let list = try Self.real()
        #expect(list.models.count == 3)
        #expect(list.defaultModelID == nil)
        #expect(list.savedModelID == nil)
        #expect(list.model(id: "qwen3.8-27b")?.defaultContext == 131072)
        let items = ModelMenu.items(list: list, settingsID: "", loadedID: nil)
        #expect(items.first { $0.value == "qwen3.8-flash-next-q2" }?.disabledReason == "not on this Mac")
        #expect(items.first { $0.value == "qwen3.8-27b" }?.disabledReason == nil)
    }

    struct InlineCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let json: String
        /// The decoded ids, or nil when decoding should fail.
        var ids: [String]? = nil
        var defaultContext: Int? = nil
        var unsupported: Int? = nil
    }

    static let inlineCases: [InlineCase] = [
        .init(testDescription: "ignoresUnknownKeys",
              json: #"{"schema_version":1,"extra":true,"models":[{"id":"m","display_name":"M","family":"f","on_this_mac":true,"downloadable":false,"runs_in_tui":true,"measured_contexts":[],"zzz":1}]}"#,
              ids: ["m"]),
        .init(testDescription: "missingSchemaVersionDefaultsToOne", json: #"{"models":[{"id":"m","context":4096}]}"#,
              ids: ["m"], defaultContext: 4096),
        .init(testDescription: "wrongSchemaVersionFails", json: #"{"schema_version":2,"models":[]}"#, unsupported: 2),
        .init(testDescription: "wrongSchemaVersionFails (garbage is malformed)", json: "nope"),
    ]

    @Test(arguments: inlineCases) func decodesInline(_ c: InlineCase) throws {
        switch EngineModelList.decode(Data(c.json.utf8)) {
        case .success(let list):
            #expect(list.models.map(\.id) == c.ids)
            #expect(list.defaultModelID == nil)
            if let context = c.defaultContext { #expect(list.model(id: "m")?.defaultContext == context) }
        case .failure(.unsupportedSchema(let version)):
            #expect(c.ids == nil && version == c.unsupported)
        case .failure(.malformed):
            #expect(c.ids == nil && c.unsupported == nil)
        case .failure(let other):
            Issue.record("unexpected \(other)")
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
            list: list, modelID: "laguna-xs-2.1", settingsContext: 20000, loaded: 20000,
            locale: Locale(identifier: "en_US"))
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

    // MARK: SU.5a2 Task 1: toolbar labels and parsing

}
