// SwiftUI menu-bar app entry. Stub.
// See ./README.md for what to fill in.
import SwiftUI

@main
struct TsutaeApp: App {
	var body: some Scene {
		MenuBarExtra("tsutae", systemImage: "mic.fill") {
			Text("tsutae stub")
				.padding()
			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}
		}
		.menuBarExtraStyle(.window)

		Settings {
			Text("Settings to be implemented.")
				.frame(width: 480, height: 360)
		}
	}
}
