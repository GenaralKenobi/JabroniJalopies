import PhotosUI
import SwiftUI

struct VehicleFormView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    private var unit: DistanceUnit { DistanceUnit.resolved(draft.readingUnit) }

    /// `nil` when adding a new vehicle.
    let original: Vehicle?

    @State private var draft: Vehicle
    @State private var odometerText: String
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private static let years: [Int] = {
        let current = Calendar.current.component(.year, from: .now)
        return Array((1950...(current + 1)).reversed())
    }()

    init(vehicle: Vehicle? = nil) {
        original = vehicle
        _draft = State(initialValue: vehicle ?? .new())
        _odometerText = State(initialValue: vehicle.map { String($0.odometer) } ?? "")
    }

    private var isValid: Bool { !draft.make.trimmed.isEmpty || !draft.name.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        VehicleThumbnail(data: draft.photo, size: 72)
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(draft.photo == nil ? "Add Photo" : "Change Photo")
                            }
                            if draft.photo != nil {
                                Button("Remove Photo", role: .destructive) {
                                    draft.photo = nil
                                    photoItem = nil
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section("Vehicle") {
                    TextField("Unit number or nickname (e.g. Truck 12)", text: $draft.name)
                    TextField("Make (e.g. Ford)", text: $draft.make)
                        .textInputAutocapitalization(.words)
                    TextField("Model (e.g. Transit 250)", text: $draft.model)
                        .textInputAutocapitalization(.words)
                    Picker("Year", selection: $draft.year) {
                        ForEach(Self.years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }

                Section("Details") {
                    HStack {
                        TextField("Current \(unit.readingName.lowercased())", text: $odometerText)
                            .keyboardType(.numberPad)
                        Text(unit.abbreviation).foregroundStyle(Color.secondary)
                    }
                    Picker("Reading", selection: Binding(
                        get: { DistanceUnit.resolved(draft.readingUnit) },
                        set: { draft.readingUnit = $0.rawValue }
                    )) {
                        ForEach(DistanceUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("License plate", text: $draft.licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("VIN", text: $draft.vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if original == nil {
                    Section {
                        Text("Fluids, tires and pressures can be filled in from the vehicle's Specs page after saving.")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .keyboardDoneButton()
            .navigationTitle(original == nil ? "New Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Small enough to store with the vehicle record (works offline, no extra storage).
                        draft.photo = ImageProcessing.downscaledJPEG(data, maxDimension: 600, quality: 0.6)
                    }
                }
            }
        }
    }

    private func save() {
        var vehicle = draft
        vehicle.name = vehicle.name.trimmed
        vehicle.make = vehicle.make.trimmed
        vehicle.model = vehicle.model.trimmed
        vehicle.vin = vehicle.vin.trimmed.uppercased()
        vehicle.licensePlate = vehicle.licensePlate.trimmed.uppercased()
        vehicle.odometer = NumberParsing.int(odometerText) ?? original?.odometer ?? 0
        if let original {
            fleet.update(vehicle, from: original)
            dismiss()
            return
        }
        do {
            try fleet.add(vehicle)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
