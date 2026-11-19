// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConversationVAD",
    platforms: [.iOS(.v15)],
    products: [.library(name: "ConversationVAD", targets: ["ConversationVAD"])],
    targets: [
        .binaryTarget(name: "onnxruntime",
                      url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip",
                      checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"),
        .target(name: "ConversationVAD", dependencies: ["onnxruntime"])
    ],
    cxxLanguageStandard: .cxx17
)
