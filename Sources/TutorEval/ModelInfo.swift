import Foundation
import FoundationModels

/// Every identity signal the framework and the OS offer about the model -
/// Chapter 14. There is no model version API, and the adapter API whose
/// compatibility identifiers tracked the base model is obsoleted in macOS
/// 27 / iOS 27. What is left is the OS build, and what the model reports
/// about itself: the only fingerprint an app can record next to an answer.
struct ModelInfo: Codable {
    let osVersion: String
    let osBuild: String
    let available: Bool
    let contextSize: Int
    let supportedLanguages: Int

    init() {
        let model = SystemLanguageModel.default
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        var buildName = [CChar](repeating: 0, count: 64)
        var size = buildName.count
        sysctlbyname("kern.osversion", &buildName, &size, nil, 0)
        osBuild = String(cString: buildName)
        if case .available = model.availability { available = true } else { available = false }
        contextSize = model.contextSize
        supportedLanguages = model.supportedLanguages.count
    }
}
