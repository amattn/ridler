import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var currentProject: PRDProject?
    @State private var isFilePickerPresented = false
    @State private var isNewPRDPresented = false

    var body: some View {
        Group {
            if currentProject != nil {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                } content: {
                    DetailView()
                } detail: {
                    LogPanelView()
                }
            } else {
                EmptyStateView(
                    onOpenPRD: { isFilePickerPresented = true },
                    onNewPRD: { isNewPRDPresented = true }
                )
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.folder, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $isNewPRDPresented) {
            NewPRDSheet(isPresented: $isNewPRDPresented) { project in
                currentProject = project
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let store = FileSystemPRDStore()
            do {
                let project = try store.loadProject(from: url)
                currentProject = project
            } catch {
                // Error handling will be enhanced in US-015
            }
        case .failure:
            // Error handling will be enhanced in US-015
            break
        }
    }
}

#Preview {
    ContentView()
}
