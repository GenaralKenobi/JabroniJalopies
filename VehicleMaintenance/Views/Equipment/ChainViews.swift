import FirebaseFirestore
import SwiftUI

/// Summary rows for a truck's chains (shown on the truck page).
struct ChainSummaryRows: View {
    let inventory: ChainInventory

    var body: some View {
        ForEach(inventory.sortedSizes) { size in
            let count = inventory.count(size)
            LabeledContent {
                Text("\(count) sharp")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(count <= 0 ? Color.orange : Color.primary)
            } label: {
                Text("\(size.label) chains")
            }
        }
    }
}

/// A truck's chains: counts, actions and history.
struct ChainsView: View {
    let vehicleId: String

    @Environment(FleetModel.self) private var fleet
    @State private var logs: [ChainLog] = []
    @State private var unsyncedLogIds: Set<String> = []
    @State private var listener: ListenerRegistration?
    @State private var form: ChainLogFormView.Mode?
    @State private var editingSizes = false

    var body: some View {
        let inventory = fleet.chainInventories[vehicleId]
        List {
            if let inventory, !inventory.sizes.isEmpty {
                Section {
                    ChainSummaryRows(inventory: inventory)
                    if inventory.hasNegativeCount {
                        Label(fleet.isManager
                              ? "Below zero. Chains may have been added on a phone that hasn't synced yet. If it stays below zero, use Correct Counts after counting what's on the truck."
                              : "Below zero. Chains may have been added on a phone that hasn't synced yet. If it stays that way, a manager will count them.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("On This Truck")
                } footer: {
                    if let correctedAt = inventory.correctedAt {
                        Text("Last counted by \(inventory.correctedByName ?? "a manager") \(Formatting.dayAndTime(correctedAt)).")
                    }
                }

                Section {
                    Button { form = .usedBox } label: {
                        Label("Empty Used Chain Box", systemImage: "tray.and.arrow.up")
                            .font(.headline)
                    }
                    Button { form = .add } label: {
                        Label("Add Chains", systemImage: "plus.circle")
                    }
                    if fleet.isManager {
                        Button { form = .correct } label: {
                            Label("Correct Counts", systemImage: "slider.horizontal.3")
                        }
                    }
                } footer: {
                    Text("At the end of the day, take the chains out of the used chain box and record how many are dull (to resharpen) and how many are thrown away."
                         + (fleet.isManager ? " Correct Counts makes what you count the new starting point; anything logged after it is added on top." : ""))
                }
            } else {
                Section {
                    Text(fleet.isManager ? "Set which chain sizes this truck carries to start tracking chains."
                         : "A manager hasn't set up chain sizes for this truck yet.")
                        .foregroundStyle(Color.secondary)
                }
            }

            if fleet.isManager {
                Section {
                    Button { editingSizes = true } label: {
                        Label(inventory?.sizes.isEmpty ?? true ? "Set Chain Sizes" : "Edit Chain Sizes", systemImage: "ruler")
                    }
                }
            }

            if !logs.isEmpty {
                Section("History") {
                    ForEach(logs) { log in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: log.kind.symbolName).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.kind.label).font(.subheadline.weight(.semibold))
                                Text(log.summary).font(.subheadline)
                                Text("\(log.loggedByName) · \(log.loggedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(Color.secondary)
                                if unsyncedLogIds.contains(log.id ?? "") {
                                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Chains — \(fleet.vehicle(vehicleId)?.displayName ?? "")")
        .onAppear { fleet.watch(vehicle: vehicleId) }
        .onDisappear { fleet.unwatch(vehicle: vehicleId) }
        .navigationBarTitleDisplayMode(.inline)
        .syncStatusBanner()
        .onAppear(perform: startListening)
        .onDisappear { listener?.remove(); listener = nil }
        .sheet(item: $form) { mode in
            if let inventory {
                ChainLogFormView(vehicleId: vehicleId, inventory: inventory, mode: mode)
            }
        }
        .sheet(isPresented: $editingSizes) {
            ChainSizesEditorView(vehicleId: vehicleId, sizes: inventory?.sortedSizes ?? [], vehicle: fleet.vehicle(vehicleId))
        }
    }

    private func startListening() {
        guard listener == nil else { return }
        let query = FS.chainLogs(fleet.fleetId, vehicleId).order(by: "loggedAt", descending: true).limit(to: 60)
        listener = firestoreListen(query, includeMetadataChanges: true) { (items: [ChainLog], snapshot) in
            logs = items
            unsyncedLogIds = Set(snapshot.documents.filter(\.metadata.hasPendingWrites).map(\.documentID))
        }
    }
}

/// Used chain box, add chains, or (managers) correct counts — one stepper row per size.
struct ChainLogFormView: View {
    enum Mode: String, Identifiable {
        case usedBox, add, correct
        var id: String { rawValue }
    }

    let vehicleId: String
    let inventory: ChainInventory
    let mode: Mode

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var dull: [String: Int] = [:]
    @State private var discarded: [String: Int] = [:]
    @State private var added: [String: Int] = [:]
    @State private var actual: [String: Int] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(inventory.sortedSizes) { size in
                    Section {
                        switch mode {
                        case .usedBox:
                            CountStepper(title: "Dull — resharpen", value: binding($dull, size))
                            CountStepper(title: "Thrown away", value: binding($discarded, size))
                        case .add:
                            CountStepper(title: "Added to truck", value: binding($added, size))
                        case .correct:
                            CountStepper(title: "Actually on truck", value: Binding(
                                get: { actual[size.key] ?? max(0, inventory.count(size)) },
                                set: { actual[size.key] = $0 }))
                        }
                    } header: {
                        HStack {
                            Text("\(size.label) chains")
                            Spacer()
                            Text("\(inventory.count(size)) on truck").textCase(nil)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private var title: String {
        switch mode {
        case .usedBox: "Used Chain Box"
        case .add: "Add Chains"
        case .correct: "Correct Counts"
        }
    }

    private func binding(_ dict: Binding<[String: Int]>, _ size: ChainSize) -> Binding<Int> {
        Binding(get: { dict.wrappedValue[size.key] ?? 0 }, set: { dict.wrappedValue[size.key] = $0 })
    }

    private func save() {
        do {
            switch mode {
            case .usedBox:
                try fleet.emptyUsedChainBox(vehicleId: vehicleId, sizes: inventory.sortedSizes, dull: dull, discarded: discarded)
            case .add:
                try fleet.addChains(vehicleId: vehicleId, sizes: inventory.sortedSizes, added: added)
            case .correct:
                try fleet.correctChainCounts(vehicleId: vehicleId, inventory: inventory, actual: actual)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A large, glove-friendly number entry with − / + buttons.
struct CountStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { value = max(0, value - 1) } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(value == 0)
            .accessibilityLabel("Decrease \(title)")
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minWidth: 36)
            Button { value += 1 } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Increase \(title)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value)")
    }
}

struct ChainSizesEditorView: View {
    let vehicleId: String
    let vehicle: Vehicle?

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?

    init(vehicleId: String, sizes: [ChainSize], vehicle: Vehicle?) {
        self.vehicleId = vehicleId
        self.vehicle = vehicle
        _text = State(initialValue: sizes.map { $0.inches.formatted() }.joined(separator: ", "))
    }

    private var parsed: [ChainSize] { ChainSizeParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 16, 18, 22", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Chain sizes on \(vehicle?.displayName ?? "this truck") (inches)")
                } footer: {
                    Text(parsed.isEmpty ? "Separate sizes with commas." : "Will track: " + parsed.map(\.label).joined(separator: ", "))
                }
                let barLengths = fleet.equipment(on: vehicleId, type: .chainsaw).compactMap(\.barLengthInches)
                if !barLengths.isEmpty {
                    Section {
                        Button("Use Saw Bar Lengths (\(Set(barLengths).sorted().map { ChainSize.format($0) }.joined(separator: ", ")))") {
                            text = Set(barLengths).sorted().map { $0.formatted() }.joined(separator: ", ")
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .keyboardDoneButton()
            .navigationTitle("Chain Sizes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try fleet.setChainSizes(parsed, vehicleId: vehicleId)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(parsed.isEmpty)
                }
            }
        }
    }
}

/// Managers: chains across the whole fleet.
struct ChainTotalsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "This Week", month = "This Month", year = "This Year"
        var id: String { rawValue }

        var start: Date {
            let calendar = Calendar.current
            let component: Calendar.Component = switch self {
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
            return calendar.dateInterval(of: component, for: .now)?.start ?? .now
        }
    }

    @Environment(FleetModel.self) private var fleet
    @State private var period: Period = .month
    @State private var logs: [ChainLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        let totals = ChainTotals.make(inventories: Array(fleet.chainInventories.values), logs: logs, since: period.start)
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if totals.rows.isEmpty {
                Section {
                    Text("No chain sizes set up on any truck yet.").foregroundStyle(Color.secondary)
                }
            } else {
                Section {
                    ForEach(totals.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(row.label) chains").font(.headline)
                            HStack {
                                stat("Sharp on trucks", row.onTrucks)
                                stat("Dull", row.dull)
                                stat("Thrown away", row.discarded)
                                stat("Added", row.added)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Fleet Totals")
                } footer: {
                    Text("\"Sharp on trucks\" is right now. Dull, thrown away and added are for \(period.rawValue.lowercased()).")
                }
                Section("By Truck") {
                    ForEach(fleet.sortedVehicles) { vehicle in
                        if let inventory = fleet.chainInventories[vehicle.id ?? ""], !inventory.sizes.isEmpty {
                            NavigationLink {
                                ChainsView(vehicleId: vehicle.id ?? "")
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vehicle.displayName).foregroundStyle(Color.primary)
                                    Text(inventory.sortedSizes.map { "\($0.label): \(inventory.count($0))" }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Chain Totals")
        .onAppear { fleet.watchAllChains(true) }
        .onDisappear { fleet.watchAllChains(false) }
        .overlay { if isLoading && logs.isEmpty { ProgressView() } }
        // Reload once the trucks have loaded (the screen can open before they arrive).
        .task(id: fleet.vehicles.count) { await load() }
        .refreshable { await load() }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        do {
            logs = try await fleet.chainLogs(since: Period.year.start)
            errorMessage = nil
        } catch {
            errorMessage = ErrorCenter.friendly(error)
        }
        isLoading = false
    }
}
