import SwiftUI

/// Switch fleets, accept invites, or create a new fleet.
struct FleetPickerView: View {
    var isInitialSetup = false

    @Environment(SessionModel.self) private var session
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreate = false
    @State private var acceptingInvite: Invite?

    var body: some View {
        List {
            if isInitialSetup && session.memberships.isEmpty && session.invites.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome!").font(.title2.bold())
                        Text("**Managers:** create a fleet, then invite your drivers.")
                        Text("**Drivers:** ask your manager to invite **\(session.email)**. The invite will appear here.")
                    }
                    .padding(.vertical, 4)
                }
            }

            if !session.invites.isEmpty {
                Section("Invitations") {
                    ForEach(session.invites) { invite in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(invite.fleetName).font(.headline)
                            Text("\(invite.invitedByName) invited you as a \(invite.role.displayName.lowercased()).")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            HStack {
                                Button("Join") { acceptingInvite = invite }
                                    .buttonStyle(.borderedProminent)
                                Button("Decline", role: .destructive) { session.decline(invite) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !session.memberships.isEmpty {
                Section {
                    ForEach(session.memberships) { membership in
                        Button {
                            if let id = membership.id {
                                session.select(fleetId: id)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Label(membership.fleetName, systemImage: "car.2")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if membership.id == session.fleetModel?.fleetId {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Your Fleets")
                } footer: {
                    Text("Each fleet keeps its own profile, role and vehicles.")
                }
            }

            Section {
                Button {
                    showingCreate = true
                } label: {
                    Label("Create a New Fleet", systemImage: "plus.circle")
                }
            }

            if isInitialSetup {
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                } footer: {
                    Text("Signed in as \(session.email)")
                }
            }
        }
        .navigationTitle(isInitialSetup ? "Get Started" : "Fleets")
        .sheet(isPresented: $showingCreate) {
            CreateFleetView { dismiss() }
        }
        .sheet(item: $acceptingInvite) { invite in
            AcceptInviteView(invite: invite) { dismiss() }
        }
    }
}

struct ProfileFields: View {
    @Binding var profile: ProfileDraft

    var body: some View {
        TextField("Your name", text: $profile.displayName)
            .textContentType(.name)
            .textInputAutocapitalization(.words)
        TextField("Phone (optional)", text: $profile.phone)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
    }
}

struct CreateFleetView: View {
    var onCreated: () -> Void = {}

    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var profile = ProfileDraft()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Fleet name (e.g. Acme Delivery)", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("You'll be the fleet's manager. You can invite drivers and other managers next.")
                }
                Section {
                    ProfileFields(profile: $profile)
                } header: {
                    Text("Your Profile in This Fleet")
                } footer: {
                    Text("Shown to other members of this fleet.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Fleet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        do {
                            try session.createFleet(name: name, profile: profile)
                            dismiss()
                            onCreated()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmed.isEmpty || !profile.isValid)
                }
            }
        }
    }
}

struct AcceptInviteView: View {
    let invite: Invite
    var onJoined: () -> Void = {}

    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ProfileDraft()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Fleet", value: invite.fleetName)
                    LabeledContent("Role", value: invite.role.displayName)
                    LabeledContent("Invited by", value: invite.invitedByName)
                }
                Section {
                    ProfileFields(profile: $profile)
                } header: {
                    Text("Your Profile in This Fleet")
                } footer: {
                    Text("Each fleet has its own profile, so you can use different details in different fleets.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Join Fleet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        do {
                            try session.accept(invite, profile: profile)
                            dismiss()
                            onJoined()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(!profile.isValid)
                }
            }
        }
    }
}
