import SwiftUI

@main
struct ImageResizerApp: App {
    @StateObject private var viewModel = EditorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}
