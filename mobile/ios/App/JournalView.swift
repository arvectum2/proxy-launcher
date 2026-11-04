import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if model.events.isEmpty {
                    Text("Событий пока нет").foregroundStyle(.secondary)
                } else {
                    ForEach(model.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.type).font(.headline)
                                Spacer()
                                Text(event.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            if let name = event.profileName { Text(name).font(.subheadline) }
                            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Журнал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}
