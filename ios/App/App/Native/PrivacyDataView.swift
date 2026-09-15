import SwiftUI

/// Sept 15 — Profile → "Your data & privacy": the policies, a copy of
/// everything REX holds about you, and deleting your account. The last two
/// are GDPR rights (access/portability and erasure), and Apple requires the
/// deletion one for any app you can create an account in.
struct PrivacyRoute: Hashable {}

struct PrivacyDataView: View {
    var onSignedOut: () -> Void

    @State private var legalSection: LegalContentView.Section?
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                group("Our policies") {
                    row(icon: "doc.text", title: "Privacy Policy", subtitle: "What we collect, why, and who processes it") {
                        legalSection = .privacy
                    }
                    Divider().padding(.leading, 52)
                    row(icon: "checkmark.shield", title: "Terms of Use", subtitle: "The agreement for using Rex") {
                        legalSection = .terms
                    }
                }

                group("Your data") {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        HStack(alignment: .top, spacing: RexSpacing.md) {
                            icon("square.and.arrow.down")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download my data")
                                    .font(RexFont.text(15, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                Text("Your profile, Rex, trips, lists, collections, comments, likes, friends and settings, as one file (JSON). Photos are included as links.")
                                    .font(RexFont.text(12.5))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Save or send the file", systemImage: "square.and.arrow.up")
                                    .font(RexFont.text(14, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 42)
                                    .background(RexColor.primary)
                                    .foregroundStyle(RexColor.primaryForeground)
                                    .clipShape(Capsule())
                            }
                            .padding(.leading, 40)
                        } else {
                            Button {
                                Task { await export() }
                            } label: {
                                Group {
                                    if isExporting {
                                        HStack(spacing: 8) { ProgressView(); Text("Gathering your data\u{2026}") }
                                    } else {
                                        Text("Prepare my data")
                                    }
                                }
                                .font(RexFont.text(14, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(RexColor.primary)
                            .disabled(isExporting)
                            .padding(.leading, 40)
                        }
                        if let exportError {
                            Text(exportError).font(RexFont.text(12)).foregroundStyle(RexColor.destructive)
                                .padding(.leading, 40)
                        }
                    }
                    .padding(RexSpacing.md)
                }

                group("Delete account") {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Permanently deletes your account and everything in it — your profile, Rex, trips, lists, collections, photos, comments, likes and friend connections. This can't be undone.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) {
                            showingDelete = true
                        } label: {
                            Text("Delete my account")
                                .font(RexFont.text(14, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .overlay(Capsule().stroke(RexColor.destructive, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(RexColor.destructive)
                    }
                    .padding(RexSpacing.md)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Your data & privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalSection) { LegalContentView(section: $0) }
        .fullScreenCover(isPresented: $showingDelete) {
            DeleteAccountView(onDeleted: {
                showingDelete = false
                onSignedOut()
            })
        }
    }

    private func export() async {
        isExporting = true
        exportError = nil
        do {
            exportURL = try await RexAPI.shared.exportMyData()
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(RexColor.mutedForeground)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16))
            .foregroundStyle(RexColor.primary)
            .frame(width: 28)
    }

    private func row(icon name: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RexSpacing.md) {
                icon(name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(RexFont.text(15, weight: .semibold)).foregroundStyle(RexColor.foreground)
                    Text(subtitle).font(RexFont.text(12.5)).foregroundStyle(RexColor.mutedForeground)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.placeholder)
            }
            .padding(RexSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// The deletion itself: say exactly what goes, offer the export first, and
/// make the person type DELETE so it can't happen by a stray tap.
struct DeleteAccountView: View {
    var onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var confirmed: Bool { confirmation.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.top, RexSpacing.lg)
                    Text("Delete your account?")
                        .font(RexFont.display(26, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("This permanently deletes:")
                            .font(RexFont.text(15, weight: .semibold))
                        ForEach([
                            "Your profile, name, username and photo",
                            "Every Rex, trip, list, blast and want to try",
                            "Your collections and everything saved in them",
                            "Your comments, likes and photos",
                            "Your friend connections and notifications",
                        ], id: \.self) { line in
                            Label(line, systemImage: "minus.circle")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.foreground)
                        }
                    }
                    Text("Friends will no longer see anything you posted. It can't be undone — if you might want a copy, download your data first.")
                        .font(RexFont.text(13.5))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        Text("Type DELETE to confirm").font(RexFont.text(13, weight: .semibold))
                        TextField("DELETE", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                    }

                    if let errorMessage {
                        Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await delete() }
                    } label: {
                        Group {
                            if isDeleting {
                                HStack(spacing: 8) { ProgressView().tint(.white); Text("Deleting\u{2026}") }
                            } else {
                                Text("Permanently delete my account")
                            }
                        }
                        .font(RexFont.text(16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(confirmed ? RexColor.destructive : RexColor.destructive.opacity(0.35))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!confirmed || isDeleting)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(isDeleting)
                }
            }
        }
        .tint(RexColor.primary)
        .interactiveDismissDisabled(isDeleting)
    }

    private func delete() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await RexAPI.shared.deleteMyAccount()
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}

/// Sept 15 — shown when the Terms / Privacy Policy have changed since this
/// account last agreed (or it never had a recorded agreement). Agreeing is
/// logged with a timestamp and the version, the same as at sign-up.
struct ConsentUpdateView: View {
    var onAgreed: () -> Void
    @State private var legalSection: LegalContentView.Section?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Spacer(minLength: RexSpacing.xxl)
            Image(systemName: "checkmark.shield")
                .font(.system(size: 38))
                .foregroundStyle(RexColor.primary)
            Text("We\u{2019}ve updated our policies")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Our Privacy Policy now explains how Rex handles your location, contacts and imported photos, and how to download your data or delete your account. Please take a look and agree to carry on.")
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RexSpacing.lg) {
                Button("Read the Privacy Policy") { legalSection = .privacy }
                Button("Terms of Use") { legalSection = .terms }
            }
            .font(RexFont.text(14, weight: .semibold))
            .foregroundStyle(RexColor.primary)

            Spacer()

            if let errorMessage {
                Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
            }
            Button {
                Task { await agree() }
            } label: {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("I agree").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .disabled(isSaving)
            .padding(.bottom, RexSpacing.lg)
        }
        .padding(.horizontal, RexSpacing.page)
        .background(RexColor.background.ignoresSafeArea())
        .sheet(item: $legalSection) { LegalContentView(section: $0) }
        .interactiveDismissDisabled()
    }

    private func agree() async {
        isSaving = true
        errorMessage = nil
        do {
            try await RexAPI.shared.recordConsent(source: "update")
            onAgreed()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
