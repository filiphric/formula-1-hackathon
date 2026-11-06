// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FormulaCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FormulaCore", targets: ["FormulaCore"])],
    targets: [.target(name: "FormulaCore", path: "Core"),
              .target(name: "FormulaAppState", dependencies: ["FormulaCore"], path: "App",
                      exclude: ["DashboardView.swift", "FormulaLiveApp.swift", "ScheduleView.swift", "TimingStore.swift", "Info.plist", "FormulaLive.entitlements"],
                      sources: ["ScheduleStore.swift"]),
              .testTarget(name: "FormulaCoreTests", dependencies: ["FormulaCore", "FormulaAppState"], path: "Tests", resources: [.copy("Fixtures")])]
)
