import SwiftData
import SwiftUI

struct ServiceHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let vehicle: Vehicle

    @State private var searchText = ""
    @State private var editingRecord: ServiceRecord?

    private var filteredRecords: [ServiceRecord] {
        let all = vehicle.sortedRecords
        let query = searchText.trimmed
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.shop.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var recordsByYear: [(year: Int, records: [ServiceRecord])] {
        let groups = Dictionary(grouping: filteredRecords) { Calendar.current.component(.year, from: $0.date) }
        return groups.keys.sorted(by: >).map { (year: $0, records: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(recordsByYear, id: \.year) { group in
                Section {
                    ForEach(group.records) { record in
                        Button {
                            editingRecord = record
                        } label: {
                            ServiceRecordRow(record: record)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(group.records[index])
                        }
                    }
                } header: {
                    HStack {
                        Text(String(group.year))
                        Spacer()
                        Text(Formatting.currency(group.records.reduce(0) { $0 + $1.cost }))
                    }
                }
            }
        }
        .overlay {
            if filteredRecords.isEmpty {
                if searchText.trimmed.isEmpty {
                    ContentUnavailableView("No Service History", systemImage: "wrench.and.screwdriver")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search services, shops, notes")
        .navigationTitle("Service History")
        .sheet(item: $editingRecord) { record in
            ServiceRecordFormView(vehicle: vehicle, record: record)
        }
    }
}
