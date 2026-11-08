import Testing
@testable import FormulaCore

// Request: the race control and team radio icons show a red dot when there is a new item in the list.

@Test func nothingIsNewBeforeTheFirstListArrives() {
    let seen = SeenItems()
    #expect(!seen.hasUnseen(in: []))
    #expect(!seen.hasUnseen(in: ["a"]))
}

@Test func itemsAlreadyThereWhenTheAppConnectsAreNotNew() {
    var seen = SeenItems()
    seen.observe(["a", "b"], viewing: false)
    #expect(!seen.hasUnseen(in: ["a", "b"]))
}

@Test func anItemArrivingWhileAwayFromThePageShowsTheDot() {
    var seen = SeenItems()
    seen.observe(["a"], viewing: false)
    seen.observe(["b", "a"], viewing: false)
    #expect(seen.hasUnseen(in: ["b", "a"]))
}

@Test func theDotStaysUntilThePageIsViewedThenClears() {
    var seen = SeenItems()
    seen.observe(["a"], viewing: false)
    seen.observe(["b", "a"], viewing: false)
    seen.observe(["c", "b", "a"], viewing: false)
    #expect(seen.hasUnseen(in: ["c", "b", "a"]))
    seen.observe(["c", "b", "a"], viewing: true)
    #expect(!seen.hasUnseen(in: ["c", "b", "a"]))
}

@Test func anItemArrivingWhileTheUserIsOnThePageNeverShowsTheDot() {
    var seen = SeenItems()
    seen.observe(["a"], viewing: true)
    seen.observe(["b", "a"], viewing: true)
    #expect(!seen.hasUnseen(in: ["b", "a"]))
}

@Test func aNewSessionStartsFromAFreshBaseline() {
    var seen = SeenItems()
    seen.observe(["a"], viewing: false)
    seen.reset()
    seen.observe(["x", "y"], viewing: false)
    #expect(!seen.hasUnseen(in: ["x", "y"]))
}
