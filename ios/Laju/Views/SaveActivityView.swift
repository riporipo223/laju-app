import SwiftUI

/// T4.21: shown right after Finish (before `RunSummaryView`) — the run is only `pause()`d at this point,
/// not `stop()`d, specifically so Back can `resume()` it and this whole screen never happened (see
/// `onBack`). Only `onPublish` actually finalizes the run (`RunViewModel.finishAndRequestPost`).
struct SaveActivityView: View {
    @ObservedObject var model: RunViewModel
    let onBack: () -> Void
    let onPublish: () -> Void

    @StateObject private var gearModel = GearViewModel()
    @State private var title = ""
    @State private var description = ""
    @State private var privateNotes = ""
    @State private var selectedGearId: String?
    @State private var mapType = "standard"
    @State private var visibility = "public"
    @State private var isAddingGear = false
    @State private var newGearBrand = GearViewModel.brands[0]
    @State private var newGearModel = ""
    @State private var newGearSize = ""

    private static let mapTypes: [(value: String, label: String)] = [
        ("standard", "Standard"),
        ("activity_heat", "Activity Heat (Satellite)"),
    ]
    private static let visibilities: [(value: String, label: String)] = [
        ("public", "Public"),
        ("private", "Private"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        summaryStat("Jarak", DistanceFormatter.format(meters: model.distanceMeters))
                        Divider()
                        summaryStat("Poin", String(format: "+%.1f", model.currentEstimatedPoints))
                    }
                }

                Section("Judul (opsional)") {
                    TextField("Judul aktivitas...", text: $title)
                }

                Section("Deskripsi (opsional)") {
                    TextField("Ceritain lari kamu...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Private Notes (opsional)") {
                    TextField("Catatan buat kamu sendiri...", text: $privateNotes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Jenis Sepatu") {
                    gearPicker
                }

                Section("Map Type") {
                    Picker("Map Type", selection: $mapType) {
                        ForEach(Self.mapTypes, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(Self.visibilities, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Save Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onBack)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Activity") { publish() }
                }
            }
        }
        .task { await gearModel.load() }
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(LajuFont.sectionNumber).foregroundStyle(LajuColor.textPrimary)
            LajuLabelText(text: label)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var gearPicker: some View {
        if !gearModel.gear.isEmpty {
            Picker("Sepatu", selection: $selectedGearId) {
                Text("Tidak pilih").tag(String?.none)
                ForEach(gearModel.gear) { item in
                    Text(item.displayName).tag(String?.some(item.gearId))
                }
            }
        }
        if isAddingGear {
            addGearForm
        } else {
            Button("Add Gear") { isAddingGear = true }
        }
    }

    private var addGearForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Brand", selection: $newGearBrand) {
                ForEach(GearViewModel.brands, id: \.self) { brand in
                    Text(brand).tag(brand)
                }
            }
            TextField("Model (mis. AirMax 95)", text: $newGearModel)
            TextField("Ukuran", text: $newGearSize)
            HStack {
                Button("Batal") { isAddingGear = false }
                Spacer()
                Button("Simpan Gear") {
                    Task {
                        let trimmedModel = newGearModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedSize = newGearSize.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let created = await gearModel.addGear(
                            brand: newGearBrand,
                            model: trimmedModel.isEmpty ? nil : trimmedModel,
                            size: trimmedSize.isEmpty ? nil : trimmedSize
                        ) {
                            selectedGearId = created.gearId
                            newGearModel = ""
                            newGearSize = ""
                            isAddingGear = false
                        }
                    }
                }
            }
        }
    }

    private func publish() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = privateNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        model.finishAndRequestPost(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            privateNotes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            mapType: mapType,
            visibility: visibility,
            gearId: selectedGearId
        )
        onPublish()
    }
}

#Preview {
    let persistence = PersistenceController(inMemory: true)
    return SaveActivityView(
        model: RunViewModel(locationService: LocationTrackingService(), context: persistence.container.viewContext),
        onBack: {},
        onPublish: {}
    )
    .preferredColorScheme(.dark)
}
