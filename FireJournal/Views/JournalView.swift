//
//  JournalView.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/25/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import PhotosUI
import UIKit

/// Main screen after login.
/// Shows a live Firestore-backed list of entries for one user.
struct JournalView: View {
    
    @Environment(AuthController.self) private var authController
    /// Stable UID injected from ContentView.
    /// Keeping this as a constant avoids querying a moving/empty path.
    private let userId: String
    private let entryTagger = EntryTagger()
    
    /// Live Firestore query.
    /// Any add/delete/update in this collection automatically refreshes `entries`.
    @FirestoreQuery var entries: [Entry]

    init(userId: String) {
        self.userId = userId
        // Per-user subcollection path:
        // users/{uid}/entry
        _entries = FirestoreQuery(collectionPath: "users/\(userId)/entry")
    }
    
    /// Text typed in the search field.
    @State private var searchText = ""
    @State private var isShowingEntryComposer = false
    
    /// Client-side filtered list used by `List`.
    /// Search is case-insensitive and ignores leading/trailing spaces.
    var searchResults: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.caption.localizedCaseInsensitiveContains(query) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(searchResults) { entry in
                    NavigationLink(value: entry) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let photoURL = entry.photoURL, let url = URL(string: photoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 120)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    case .failure:
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .frame(height: 120)
                                            .frame(maxWidth: .infinity)
                                    case .empty:
                                        ProgressView()
                                            .frame(height: 120)
                                            .frame(maxWidth: .infinity)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else if let photoData = entry.photoData,
                                      let image = UIImage(data: photoData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.caption)
                                    .font(.headline)
                                    .lineLimit(3)

                                Spacer(minLength: 8)

                                Button {
                                    toggleFavorite(for: entry)
                                } label: {
                                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                        .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.isFavorite ? "Unfavorite entry" : "Favorite entry")
                            }

                            if let createdAt = entry.createdAt {
                                Label(createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("Pending timestamp", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let tags = entry.autoTags, !tags.isEmpty {
                                EntryTagChipsView(tags: tags)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: deleteItem)
            }
            .listStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            .navigationTitle("Journal Entries")
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entry: entry)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Add Entry", systemImage: "plus") {
                        isShowingEntryComposer = true
                    }
                    Button("Logout") { authController.signOut()}
                }
            }
        }
        // White text
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(
            Color.purple,
            for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        
        
        .searchable(
            text: $searchText,
            placement: .automatic,
            prompt: "Search captions"
        )
        .modifier(IOS26SearchToolbarBehavior())
        .sheet(isPresented: $isShowingEntryComposer) {
            EntryComposerView(
                onSave: { caption, isFavorite, photoData, photoMetadata in
                    try await addEntry(
                        caption: caption,
                        isFavorite: isFavorite,
                        photoData: photoData,
                        photoMetadata: photoMetadata
                    )
                },
                onAddDataDemo: {
                    try await addData()
                },
                onAddObjectDemo: {
                    try await addFromObject()
                }
            )
        }
    }
    
    
    /// Removes selected row from Firestore.
    func deleteItem(at offsets: IndexSet) {
        guard let index = offsets.first else {
            return
        }

        let itemToDelete = searchResults[index]
        guard let documentID = itemToDelete.id else { return }

        Task {
            await deletePhoto(for: itemToDelete)
            await deleteDocument(documentID: documentID)
        }
    }
    
    /// Deletes a Firestore document by id.
    /// Marked `@MainActor` because this method is triggered from UI interactions.
    @MainActor
    func deleteDocument(documentID: String) async {
        let db = Firestore.firestore()
        let documentPath = "users/\(userId)/entry/\(documentID)"
        let documentReference = db.document(documentPath)
        
        do {
            try await documentReference.delete()
            print("Document successfully deleted")
            // The snapshot listener will automatically update the list
        } catch {
            print("Error deleting document: \(error)")
            // Consider showing an alert to the user
        }
    }
    
    
    /// Writes a new entry using a raw dictionary payload.
    /// Useful for demonstrating direct field/value writes.
    func addData() async throws {
        // Get reference to the collection
        let db = Firestore.firestore()
        let caption = "Demo: added with dictionary"
        let autoTags = entryTagger.tags(for: caption, photoData: nil)
        
        // Data to send
        let data: [String: Any] = [
            "createdAt": FieldValue.serverTimestamp(),
            "caption" : caption,
            "isFavorite" : false,
            "userId" : userId,
            "autoTags": autoTags
        ]
        
        do {
            
            let ref = try await db.collection("users")
                .document(userId)
                .collection("entry")
                .addDocument(data: data)
            print("Document added successfully: \(ref.documentID)")
        } catch {
            print("Error adding document: \(error)")
            throw error // Re-throw the error
        }
        
    }
    
    /// Writes a new entry using the strongly typed `Entry` model.
    /// `addDocument(from:)` encodes the struct with `Codable`.
    func addFromObject() async throws {
        // Get reference to the collection
        let db = Firestore.firestore()
        // Create custom object
        let caption = "Demo: added from Entry object"
        var entry = Entry(caption: caption, userId: userId)
        let tags = entryTagger.tags(for: caption, photoData: nil)
        entry.autoTags = tags.isEmpty ? nil : tags
        
        let ref = try db.collection("users")
            .document(userId)
            .collection("entry")
            .addDocument(from: entry)
        print("Document added successfully: \(ref.documentID)")
    }

    /// Saves a user-typed entry.
    func addEntry(
        caption: String,
        isFavorite: Bool,
        photoData: Data?,
        photoMetadata: EntryTagger.PhotoMetadata?
    ) async throws {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return }

        let db = Firestore.firestore()
        var entry = Entry(caption: trimmedCaption, userId: userId)
        entry.isFavorite = isFavorite
        entry.metadataTimestamp = photoMetadata?.timestamp
        entry.metadataLongitude = photoMetadata?.longitude
        entry.metadataLatitute = photoMetadata?.latitude
        let tags = entryTagger.tags(for: trimmedCaption, photoData: photoData)
        if let photoData {
            entry.photoURL = try await uploadPhotoToStorage(photoData: photoData)
        }
        entry.autoTags = tags.isEmpty ? nil : tags

        let ref = try db.collection("users")
            .document(userId)
            .collection("entry")
            .addDocument(from: entry)
        print("Document added successfully: \(ref.documentID)")
    }

    /// Toggles favorite state for an existing entry.
    func toggleFavorite(for entry: Entry) {
        guard let documentID = entry.id else { return }
        Task {
            await updateFavorite(documentID: documentID, isFavorite: !entry.isFavorite)
        }
    }

    @MainActor
    func updateFavorite(documentID: String, isFavorite: Bool) async {
        let db = Firestore.firestore()
        let documentReference = db
            .collection("users")
            .document(userId)
            .collection("entry")
            .document(documentID)

        do {
            try await documentReference.updateData(["isFavorite": isFavorite])
        } catch {
            print("Error updating favorite state: \(error)")
        }
    }

    /// Compresses photo bytes to JPEG before uploading.
    func preparePhotoData(_ photoData: Data) -> Data {
        if let image = UIImage(data: photoData),
           let jpegData = image.jpegData(compressionQuality: 0.82) {
            return jpegData
        }
        return photoData
    }

    /// Uploads compressed photo bytes to Firebase Cloud Storage.
    /// Returns the public download URL string for storage in Firestore.
    func uploadPhotoToStorage(photoData: Data) async throws -> String {
        let preparedData = preparePhotoData(photoData)

        let photoPath = "users/\(userId)/entryPhotos/\(UUID().uuidString).jpg"
        let photoRef = Storage.storage().reference().child(photoPath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await photoRef.putDataAsync(preparedData, metadata: metadata)
        let downloadURL = try await photoRef.downloadURL()

        return downloadURL.absoluteString
    }

    /// Deletes the photo from Cloud Storage if the entry has a photoURL.
    func deletePhoto(for entry: Entry) async {
        guard let photoURL = entry.photoURL else { return }
        do {
            let ref = Storage.storage().reference(forURL: photoURL)
            try await ref.delete()
            print("Photo deleted from Storage")
        } catch {
            print("Error deleting photo from Storage: \(error)")
        }
    }

}

struct EntryTagChipsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

/// Applies iOS 26 search toolbar behavior only when available.
/// On earlier iOS versions this is a no-op.
private struct IOS26SearchToolbarBehavior: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.searchToolbarBehavior(.minimize)
        } else {
            content
        }
    }
}

private struct EntryComposerView: View {
    @Environment(\.dismiss) private var dismiss
    private let entryTagger = EntryTagger()
    @State private var caption = ""
    @State private var isFavorite = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var selectedPhotoMetadata: EntryTagger.PhotoMetadata?

    let onSave: (String, Bool, Data?, EntryTagger.PhotoMetadata?) async throws -> Void
    let onAddDataDemo: () async throws -> Void
    let onAddObjectDemo: () async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("New Journal Entry") {
                    TextField("What happened today?", text: $caption, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Favorite", isOn: $isFavorite)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(selectedPhotoData == nil ? "Add Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isWorking)

                    if let selectedPhotoData,
                       let selectedImage = UIImage(data: selectedPhotoData) {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Section("Demonstrations Only") {
                    Button("Add Data (Dictionary)") {
                        Task {
                            await runAction {
                                try await onAddDataDemo()
                                dismiss()
                            }
                        }
                    }
                    .disabled(isWorking)

                    Button("Add Object (Entry Model)") {
                        Task {
                            await runAction {
                                try await onAddObjectDemo()
                                dismiss()
                            }
                        }
                    }
                    .disabled(isWorking)
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await runAction {
                                try await onSave(caption, isFavorite, selectedPhotoData, selectedPhotoMetadata)
                                dismiss()
                            }
                        }
                    }
                    .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, _ in
            Task {
                await loadSelectedPhoto()
            }
        }
    }

    @MainActor
    private func runAction(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else {
            selectedPhotoData = nil
            selectedPhotoMetadata = nil
            return
        }

        do {
            selectedPhotoData = try await selectedPhotoItem.loadTransferable(type: Data.self)
            if let selectedPhotoData {
                selectedPhotoMetadata = entryTagger.extractPhotoMetadata(from: selectedPhotoData)
            } else {
                selectedPhotoMetadata = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


#Preview {
    NavigationView {
        var authController = AuthController()
        return JournalView(userId: authController.userId)
    }
}
