import PhotosUI
import SwiftData
import SwiftUI

struct VehicleFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = DistanceUnit.localeDefault

    /// `nil` when adding a new vehicle.
    let vehicle: Vehicle?

    @State private var name: String
    @State private var make: String
    @State private var modelName: String
    @State private var year: Int
    @State private var vin: String
    @State private var licensePlate: String
    @State private var odometerText: String
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?

    private static let years: [Int] = {
        let current = Calendar.current.component(.year, from: .now)
        return Array((1900...(current + 1)).reversed())
    }()

    init(vehicle: Vehicle? = nil) {
        self.vehicle = vehicle
        _name = State(initialValue: vehicle?.name ?? "")
        _make = State(initialValue: vehicle?.make ?? "")
        _modelName = State(initialValue: vehicle?.modelName ?? "")
        _year = State(initialValue: vehicle?.year ?? Calendar.current.component(.year, from: .now))
        _vin = State(initialValue: vehicle?.vin ?? "")
        _licensePlate = State(initialValue: vehicle?.licensePlate ?? "")
        _odometerText = State(initialValue: vehicle.map { String($0.odometer) } ?? "")
        _photoData = State(initialValue: vehicle?.photoData)
    }

    private var isValid: Bool {
        !make.trimmed.isEmpty || !name.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        VehicleThumbnail(data: photoData, size: 72)
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(photoData == nil ? "Add Photo" : "Change Photo")
                            }
                            if photoData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    photoData = nil
                                    photoItem = nil
                                }
                            }
                        }
                        // Keep the two buttons independently tappable inside one row.
                        .buttonStyle(.borderless)
                    }
                }

                Section("Vehicle") {
                    TextField("Make (e.g. Toyota)", text: $make)
                        .textInputAutocapitalization(.words)
                    TextField("Model (e.g. Camry)", text: $modelName)
                        .textInputAutocapitalization(.words)
                    Picker("Year", selection: $year) {
                        ForEach(Self.years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    TextField("Nickname (optional)", text: $name)
                }

                Section("Details") {
                    HStack {
                        TextField("Current Odometer", text: $odometerText)
                            .keyboardType(.numberPad)
                        Text(unit.abbreviation).foregroundStyle(.secondary)
                    }
                    TextField("License Plate", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("VIN", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(vehicle == nil ? "New Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onChange(of: photoItem) { _, item in
                loadPhoto(from: item)
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData = ImageProcessing.downscaledJPEG(data) ?? data
            }
        }
    }

    private func save() {
        let target = vehicle ?? Vehicle()
        target.name = name.trimmed
        target.make = make.trimmed
        target.modelName = modelName.trimmed
        target.year = year
        target.vin = vin.trimmed.uppercased()
        target.licensePlate = licensePlate.trimmed.uppercased()
        target.odometer = NumberParsing.int(odometerText) ?? 0
        target.photoData = photoData
        if vehicle == nil {
            modelContext.insert(target)
        }
        dismiss()
    }
}

#Preview {
    VehicleFormView()
        .modelContainer(SampleData.previewContainer)
}
