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
        #expect(list.models.map(\.id) == [
            "deepseek-v4-flash", "laguna-xs-2.1", "laguna-s-2.1", "qwen3.8-flash-next", "mellum-2"])
        let laguna = list.models[1]
        #expect(laguna.displayName == "Laguna XS 2.1")
        #expect(laguna.context == 65536)
        #expect(laguna.planGiB == 25.41)
        #expect(laguna.sizeBytes == 21_000_000_000)
        #expect(!list.models[2].onThisMac)
        #expect(list.models[2].fits == nil)
    }

    @Test func decodesRealEngineCapture() throws {
        // ds4-engine `tui_cli.py:196-222` at `a84b79bd`: no `schema_version`,
        // which the decoder reads as version 1 (EN.2, D7).
        let list = try Self.real()
        #expect(list.models.count == 3)
        let qwen = try #require(list.model(id: "qwen3.8-27b"))
        #expect(qwen.context == 131072)
        #expect(qwen.sizeBytes == 16_810_714_336)
        #expect(qwen.planGiB == 24.74)
        let items = ModelMenu.items(list: list, settingsID: "", loadedID: nil)
        #expect(items.first { $0.value == "qwen3.8-flash-next-q2" }?.disabledReason == "not on this Mac")
        #expect(items.first { $0.value == "qwen3.8-27b" }?.disabledReason == nil)
    }

    struct InlineCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let json: String
        /// The decoded ids, or nil when decoding should fail.
        var ids: [String]? = nil
        var context: Int? = nil
        var unsupported: Int? = nil
    }

    static let inlineCases: [InlineCase] = [
        .init(testDescription: "ignoresUnknownKeys",
              json: #"{"schema_version":1,"extra":true,"models":[{"id":"m","display_name":"M","family":"f","on_this_mac":true,"downloadable":false,"runs_in_tui":true,"measured_contexts":[],"zzz":1}]}"#,
              ids: ["m"]),
        .init(testDescription: "missingSchemaVersionDefaultsToOne", json: #"{"models":[{"id":"m","context":4096}]}"#,
              ids: ["m"], context: 4096),
        .init(testDescription: "wrongSchemaVersionFails", json: #"{"schema_version":2,"models":[]}"#, unsupported: 2),
        .init(testDescription: "wrongSchemaVersionFails (garbage is malformed)", json: "nope"),
    ]

    @Test(arguments: inlineCases) func decodesInline(_ c: InlineCase) throws {
        switch EngineModelList.decode(Data(c.json.utf8)) {
        case .success(let list):
            #expect(list.models.map(\.id) == c.ids)
            if let context = c.context { #expect(list.model(id: "m")?.context == context) }
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
        #expect(items.first?.title == "Engine default")
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
        #expect(reason("mellum-2") == nil)
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

    // EN.2, D7: the engine's own context and plan for the model.
    @Test func contextDefaultNamesContextAndPlan() throws {
        let items = ContextMenu.items(
            list: try Self.real(), modelID: "qwen3.8-27b", settingsContext: 0, loaded: nil,
            locale: Locale(identifier: "en_US"))
        #expect(items.first?.title == "Engine default (131,072 · 24.7 GiB)")
        #expect(items.first?.value == 0)
        #expect(items.first?.isChecked == true)
    }

    @Test func contextMenuAddsTheModelsContext() throws {
        let list = try Self.sample()
        let items = ContextMenu.items(list: list, modelID: "qwen3.8-flash-next", settingsContext: 4096, loaded: 4096)
        #expect(items.dropFirst().map(\.value) == [4096, 8192, 16384, 20000, 32768, 65536])
        #expect(items.filter(\.isChecked).map(\.value) == [4096])
        // Without a chosen model there's no model's context to add.
        let dflt = ContextMenu.items(list: list, modelID: nil, settingsContext: 0, loaded: nil)
        #expect(dflt.map(\.value) == [0, 8192, 16384, 32768, 65536])
        #expect(dflt.first?.title == "Engine default")
    }

    @Test func modelTitleNamesSizeAndPlan() throws {
        let items = ModelMenu.items(list: try Self.real(), settingsID: "", loadedID: nil, locale: Locale(identifier: "en_US"))
        #expect(items.first { $0.value == "qwen3.8-27b" }?.title == "Qwen3.8 27B — 15.7 GiB, plans 24.7 GiB")
        let mellum = ModelMenu.items(list: try Self.sample(), settingsID: "", loadedID: nil)
        #expect(mellum.first { $0.value == "mellum-2" }?.title == "Mellum 2")
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
