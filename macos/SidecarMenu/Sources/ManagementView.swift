import SwiftUI

struct ManagementView: View {
    @State private var folderPath = ""

    var body: some View {
        TabView {
            ScanView(folderPath: $folderPath)
                .tabItem { Label("Scan", systemImage: "doc.text.magnifyingglass") }
            FilesView(folderPath: folderPath)
                .tabItem { Label("Files", systemImage: "folder") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            StatusView(folderPath: folderPath)
                .tabItem { Label("Status", systemImage: "chart.bar") }
            ConfigView(folderPath: folderPath)
                .tabItem { Label("Config", systemImage: "gearshape") }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
