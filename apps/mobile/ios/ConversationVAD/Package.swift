// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConversationVAD",
    platforms: [.iOS(.v15)],
    products: [.library(name: "ConversationVAD", targets: ["ConversationVAD"])],
    targets: [
        .binaryTarget(name: "onnxruntime",
                      path: "Vendor/onnxruntime.xcframework"),
        .target(name: "ConversationVAD", dependencies: ["onnxruntime"])
    ],
    cxxLanguageStandard: .cxx17
)
