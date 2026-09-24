// swift-tools-version: 6.2
import PackageDescription

// Three targets, and the split is the first lesson of the book:
//
//   TutorCore  - the app's AI features. The same code ships in the app and is
//                evaluated here. An eval of a copy of your feature is an eval
//                of something you do not ship.
//   EvalKit    - feature-agnostic machinery: recording, statistics, text
//                normalisation. No model in it, so it is unit-tested normally.
//   TutorEval  - the command-line runner. Generates outputs, records them,
//                grades them.
//
// No third-party dependencies. Everything here runs on a Mac with Apple
// Intelligence enabled and costs nothing.
let package = Package(
    name: "Tutor",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "TutorCore", targets: ["TutorCore"]),
        .library(name: "EvalKit", targets: ["EvalKit"]),
        .executable(name: "tutor-eval", targets: ["TutorEval"]),
        .executable(name: "minimal-eval", targets: ["MinimalEval"]),
    ],
    targets: [
        .target(name: "TutorCore"),
        .target(name: "EvalKit"),
        .executableTarget(name: "TutorEval", dependencies: ["TutorCore", "EvalKit"]),
        // Chapter 2: the whole idea in one file, with no EvalKit at all.
        .executableTarget(name: "MinimalEval", dependencies: ["TutorCore"]),
        .testTarget(name: "EvalKitTests", dependencies: ["EvalKit"]),
        .testTarget(name: "TutorCoreTests", dependencies: ["TutorCore"]),
        // Chapter 6: the code that makes and audits datasets is tested like
        // any other code, because a wrong dataset is a wrong score.
        .testTarget(name: "TutorEvalTests", dependencies: ["TutorEval"]),
    ],
    swiftLanguageModes: [.v6]
)
