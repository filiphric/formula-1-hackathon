// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FormulaCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FormulaCore", targets: ["FormulaCore"])],
    targets: [.target(name: "FormulaCore", path: "Core"),
              .testTarget(name: "FormulaCoreTests", dependencies: ["FormulaCore"], path: "Tests", resources: [.copy("Fixtures")])]
)
