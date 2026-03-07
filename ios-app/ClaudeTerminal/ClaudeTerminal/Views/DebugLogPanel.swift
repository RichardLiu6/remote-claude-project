import SwiftUI
import UIKit

/// Log entry for the debug panel.
struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: Category
    let message: String

    enum Category: String {
        case ws = "WS"
        case network = "NET"
        case voice = "VOICE"
        case upload = "UPLOAD"
        case system = "SYS"
        case error = "ERR"

        var color: Color {
            switch self {
            case .ws: return .cyan
            case .network: return .blue
            case .voice: return .green
            case .upload: return .purple
            case .system: return .gray
            case .error: return .red
            }
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Centralized debug log collector.
/// Captures WebSocket events, connection state changes, errors, and other debug info.
/// Triggered by shake gesture or a toolbar button.
final class DebugLogStore: ObservableObject {
    static let shared = DebugLogStore()

    @Published var entries: [DebugLogEntry] = []

    /// Maximum log entries to keep in memory.
    private let maxEntries = 500

    private init() {}

    func log(_ message: String, category: DebugLogEntry.Category = .system) {
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }

    /// Export all logs as a single string for sharing.
    func exportText() -> String {
        entries.map { "[\($0.formattedTime)] [\($0.category.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}

/// Debug log overlay panel.
/// Shows WebSocket events, connection state changes, and errors.
struct DebugLogPanel: View {
    @ObservedObject var logStore: DebugLogStore
    @Binding var isPresented: Bool
    @State private var filterCategory: DebugLogEntry.Category?
    @State private var showShareSheet = false

    private var filteredEntries: [DebugLogEntry] {
        if let filter = filterCategory {
            return logStore.entries.filter { $0.category == filter }
        }
        return logStore.entries
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All", category: nil)
                        filterChip("WS", category: .ws)
                        filterChip("NET", category: .network)
                        filterChip("ERR", category: .error)
                        filterChip("VOICE", category: .voice)
                        filterChip("UPLOAD", category: .upload)
                        filterChip("SYS", category: .system)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.12))

                // Log entries
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: logStore.entries.count) { _ in
                        if let last = filteredEntries.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            logStore.clear()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [logStore.exportText()])
            }
        }
    }

    private func logRow(_ entry: DebugLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.formattedTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)

            Text(entry.category.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.category.color)
                .cornerRadius(3)
                .frame(width: 55, alignment: .center)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private func filterChip(_ label: String, category: DebugLogEntry.Category?) -> some View {
        Button {
            filterCategory = category
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(filterCategory == category ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(filterCategory == category ? Color.white : Color(red: 0.2, green: 0.2, blue: 0.3))
                .cornerRadius(12)
        }
    }
}

// MARK: - Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

