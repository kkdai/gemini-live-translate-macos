import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @StateObject private var viewModel = TranslatorViewModel()
    @State private var floatingWindow: FloatingSubtitleWindow?

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    let panel = FloatingSubtitleWindow(viewModel: viewModel)
                    floatingWindow = panel
                }
                .onChange(of: viewModel.isRunning) { _ in
                    if viewModel.isRunning {
                        floatingWindow?.show()
                    } else {
                        floatingWindow?.hide()
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
