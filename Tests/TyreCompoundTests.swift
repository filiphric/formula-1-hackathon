import Testing
@testable import FormulaCore

@Test(arguments: [
    ("SOFT", "S", "Soft tyre"),
    ("MEDIUM", "M", "Medium tyre"),
    ("HARD", "H", "Hard tyre"),
    ("INTERMEDIATE", "I", "Intermediate tyre"),
    ("WET", "W", "Wet tyre"),
    (" soft\n", "S", "Soft tyre")
])
func tyreMarkings(value: String, symbol: String, label: String) {
    let tyre = TyreCompound(value)
    #expect(tyre.symbol == symbol)
    #expect(tyre.label == label)
}

@Test(arguments: [nil, "", "UNKNOWN", "SUPER SOFT", "ICE"] as [String?])
func unknownTyresAreNotMislabelled(value: String?) {
    #expect(TyreCompound(value).symbol == "?")
    #expect(TyreCompound(value).label == "Tyre unknown")
}
