// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "TsutaeCore",
	defaultLocalization: "en",
	platforms: [.macOS(.v14)],
	products: [
		.library(name: "TsutaeCore", targets: ["TsutaeCore"]),
	],
	dependencies: [
		.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
		.package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
		.package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
	],
	targets: [
		.target(
			name: "TsutaeCore",
			dependencies: [
				.product(name: "Hummingbird", package: "hummingbird"),
				.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
				.product(name: "Yams", package: "Yams"),
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
			]
		),
		.testTarget(
			name: "TsutaeCoreTests",
			dependencies: ["TsutaeCore"]
		),
	]
)
