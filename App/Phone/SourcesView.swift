import PhotosUI
import SourcesKit
import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SourceDraft?
    @State private var importingFiles = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.library.sources) { source in
                        Button { editing = SourceDraft(source: source) } label: {
                            VStack(alignment: .leading) {
                                Text(source.name).foregroundStyle(.primary)
                                Text(source.kindLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { model.removeSource(model.library.sources[index]) }
                    }
                    Menu {
                        Button("M3U / M3U8 playlist link") { editing = SourceDraft(kind: .m3u) }
                        Button("Xtream Codes account") { editing = SourceDraft(kind: .xtream) }
                        Button("Jellyfin server") { editing = SourceDraft(kind: .jellyfin) }
                        Button("Emby server") { editing = SourceDraft(kind: .emby) }
                    } label: {
                        Label("Add source", systemImage: "plus")
                    }
                } header: {
                    Text("Your sources")
                } footer: {
                    Text("CarPlayTV ships with no content. Passwords are kept in the iPhone's Keychain and only sent to the server you enter.")
                }

                Section {
                    ForEach(model.localVideos) { video in
                        Text(video.name)
                    }
                    .onDelete { offsets in
                        for index in offsets { model.deleteLocalVideo(model.localVideos[index]) }
                    }
                    Button { importingFiles = true } label: { Label("Import from Files", systemImage: "folder") }
                    PhotosPicker(selection: $pickedVideo, matching: .videos) {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }
                    if isImporting { ProgressView("Importing…") }
                    if let importError { Text(importError).foregroundStyle(.red) }
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text("Imported videos play offline. Formats include MP4, MOV, MKV, AVI and more.")
                }
            }
            .navigationTitle("Sources")
            .toolbar { EditButton() }
            .sheet(item: $editing) { draft in SourceEditor(draft: draft) }
            .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.movie, .video, .audiovisualContent, .data],
                          allowsMultipleSelection: true) { result in
                importError = nil
                guard case .success(let urls) = result else { return }
                for url in urls {
                    do { try model.importLocalVideo(from: url) } catch { importError = error.localizedDescription }
                }
            }
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                Task { await importFromPhotos(item) }
            }
        }
    }

    private func importFromPhotos(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false; pickedVideo = nil }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            try model.importLocalVideo(from: movie.url)
            try? FileManager.default.removeItem(at: movie.url)
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// A video from the Photos library, copied to a temporary file.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

/// Form state for adding or editing a source.
struct SourceDraft: Identifiable {
    enum Kind: String, CaseIterable { case m3u, xtream, jellyfin, emby }

    let id: UUID
    let isNew: Bool
    var kind: Kind
    var name = ""
    var address = ""
    var username = ""
    var password = ""

    init(kind: Kind) {
        id = UUID()
        isNew = true
        self.kind = kind
    }

    init(source: Source) {
        id = source.id
        isNew = false
        name = source.name
        switch source.kind {
        case .m3u(let url): kind = .m3u; address = url.absoluteString
        case .xtream(let server, let user): kind = .xtream; address = server.absoluteString; username = user
        case .jellyfin(let server, let user): kind = .jellyfin; address = server.absoluteString; username = user
        case .emby(let server, let user): kind = .emby; address = server.absoluteString; username = user
        case .localFiles: kind = .m3u
        }
    }

    var title: String {
        switch kind {
        case .m3u: return "Playlist"
        case .xtream: return "Xtream Codes"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        }
    }

    var needsLogin: Bool { kind != .m3u }

    /// Accepts "host:port" without a scheme and trims trailing slashes.
    var normalizedURL: URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") && kind != .m3u { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    var isValid: Bool {
        normalizedURL != nil && (!needsLogin || (!username.isEmpty && (!isNew || !password.isEmpty)))
    }

    func makeSource() -> Source? {
        guard let url = normalizedURL else { return nil }
        let displayName = name.isEmpty ? (url.host ?? title) : name
        let sourceKind: Source.Kind
        switch kind {
        case .m3u: sourceKind = .m3u(url: url)
        case .xtream: sourceKind = .xtream(server: url, username: username)
        case .jellyfin: sourceKind = .jellyfin(server: url, username: username)
        case .emby: sourceKind = .emby(server: url, username: username)
        }
        return Source(id: id, name: displayName, kind: sourceKind)
    }
}

struct SourceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: SourceDraft
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $draft.name)
                    TextField(draft.kind == .m3u ? "https://example.com/playlist.m3u" : "http://server:port", text: $draft.address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if draft.needsLogin {
                    Section {
                        TextField("Username", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField(draft.isNew ? "Password" : "Password (leave empty to keep)", text: $draft.password)
                    }
                }
                if let error = model.contents.first(where: { $0.source.id == draft.id })?.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(draft.isNew ? "Add \(draft.title)" : draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(!draft.isValid || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let source = draft.makeSource() else { return }
        let password = draft.password.isEmpty ? nil : draft.password
        isSaving = true
        Task {
            if draft.isNew {
                await model.addSource(source, password: password)
            } else {
                await model.updateSource(source, password: password)
            }
            isSaving = false
            if model.contents.first(where: { $0.source.id == source.id })?.error == nil { dismiss() }
        }
    }
}
