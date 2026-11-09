import SwiftUI

struct MembersView: View {
    @Environment(FleetModel.self) private var fleet
    @State private var showingInvite = false

    var body: some View {
        List {
            Section {
                ForEach(fleet.members) { member in
                    if fleet.isManager {
                        NavigationLink {
                            MemberDetailView(memberId: member.id ?? "")
                        } label: {
                            MemberRow(member: member, isMe: member.id == fleet.uid,
                                      email: fleet.contacts[member.id ?? ""]?.email)
                        }
                    } else {
                        MemberRow(member: member, isMe: member.id == fleet.uid)
                    }
                }
            } header: {
                Text("Members (\(fleet.members.count))")
            } footer: {
                Text(fleet.isManager
                     ? "Email addresses and phone numbers are only visible to managers."
                     : "Only managers can see members' email addresses and phone numbers.")
            }

            if fleet.isManager {
                Section {
                    ForEach(fleet.invites) { invite in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.email)
                                Text("Invited as \(invite.role.displayName.lowercased())")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            ShareLink(item: InviteMessage.text(for: invite)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Share invite")
                        }
                        .swipeActions {
                            Button("Revoke", role: .destructive) { fleet.revoke(invite) }
                        }
                    }
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite Someone", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Pending Invites")
                } footer: {
                    Text("People join by creating an account with the invited email address. Swipe left on an invite to revoke it.")
                }
            }
        }
        .navigationTitle("Members")
        .sheet(isPresented: $showingInvite) {
            InviteFormView()
        }
    }
}

struct MemberRow: View {
    let member: Member
    var isMe = false
    /// Only passed in for managers.
    var email: String?

    var body: some View {
        HStack {
            Image(systemName: member.role == .manager ? "person.badge.key.fill" : "person.fill")
                .foregroundStyle(member.role == .manager ? Color.brand : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName + (isMe ? " (you)" : ""))
                if let email {
                    Text(email).font(.caption).foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            Text(member.role.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.secondary)
        }
    }
}

struct MemberDetailView: View {
    let memberId: String

    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var confirmingRemove = false

    var body: some View {
        if let member = fleet.member(memberId) {
            Form {
                Section {
                    LabeledContent("Name", value: member.displayName)
                    if let contact = fleet.contacts[memberId] {
                        LabeledContent("Email", value: contact.email)
                        if !contact.phone.isEmpty {
                            LabeledContent("Phone") {
                                if let url = URL(string: "tel:\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                                    Link(contact.phone, destination: url)
                                } else {
                                    Text(contact.phone)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Email and phone are only visible to managers.")
                }

                Section {
                    Picker("Role", selection: Binding(
                        get: { member.role },
                        set: { newRole in
                            do { try fleet.setRole(newRole, for: member) } catch { errorMessage = error.localizedDescription }
                        }
                    )) {
                        ForEach(FleetRole.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("Managers can edit vehicles, checklists and specs, approve services, close defects, and manage members.")
                }

                if member.role == .driver {
                    Section {
                        Toggle("Can See All Vehicles", isOn: Binding(
                            get: { member.seesAllVehicles },
                            set: { fleet.setSeesAllVehicles($0, for: member) }
                        ))
                        if !member.seesAllVehicles {
                            ForEach(fleet.sortedVehicles) { vehicle in
                                let assigned = vehicle.assignedUids.contains(memberId)
                                Button {
                                    if let vehicleId = vehicle.id {
                                        fleet.setAssigned(!assigned, member: memberId, vehicle: vehicleId)
                                    }
                                } label: {
                                    HStack {
                                        Text(vehicle.displayName).foregroundStyle(Color.primary)
                                        Spacer()
                                        Image(systemName: assigned ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(assigned ? Color.brand : .secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Vehicle Access")
                    } footer: {
                        Text(member.seesAllVehicles
                             ? "Turn off to choose which vehicles \(member.displayName) can see."
                             : "\(member.displayName) only sees the checked vehicles.")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if memberId != fleet.uid {
                    Section {
                        Button("Remove from Fleet", role: .destructive) { confirmingRemove = true }
                    } footer: {
                        Text("Their past checklists and reports stay in the fleet's records.")
                    }
                }
            }
            .navigationTitle(member.displayName)
            .confirmationDialog("Remove \(member.displayName) from the fleet?", isPresented: $confirmingRemove,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    do {
                        try fleet.remove(member)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            ContentUnavailableView("Member Not Found", systemImage: "person.slash")
        }
    }
}

enum InviteMessage {
    static func text(for invite: Invite) -> String {
        """
        You've been invited to join "\(invite.fleetName)" as a \(invite.role.displayName.lowercased()) in the CrewReady app.

        1. Install the CrewReady app.
        2. Create an account with this email address: \(invite.email)
        3. Confirm your email, then tap Join.
        """
    }
}

struct InviteFormView: View {
    @Environment(FleetModel.self) private var fleet
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role: FleetRole = .driver
    @State private var sentInvite: Invite?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let sentInvite {
                    Section {
                        Label("Invite created for \(sentInvite.email)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Send them the instructions so they know to install the app and sign up with that email.")
                            .font(.subheadline)
                        ShareLink(item: InviteMessage.text(for: sentInvite)) {
                            Label("Send Instructions", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("Role", selection: $role) {
                            ForEach(FleetRole.allCases) { Text($0.displayName).tag($0) }
                        }
                    } footer: {
                        Text("New members can see every vehicle by default. You can limit what drivers see from their member page.")
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentInvite == nil ? "Cancel" : "Done") { dismiss() }
                }
                if sentInvite == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Invite") {
                            do {
                                sentInvite = try fleet.invite(email: email, role: role)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(email.trimmed.isEmpty)
                    }
                }
            }
        }
    }
}
