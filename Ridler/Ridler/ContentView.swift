import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            DetailView()
        } detail: {
            LogPanelView()
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
