//
//  Entry.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/24/25.
//

import FirebaseFirestore
import Foundation

/// Firestore model for a single journal record.
/// This type is encoded/decoded automatically via `Codable`.
struct Entry: Identifiable, Codable, Hashable {

    /// Main text shown in the list/detail screens.
    var caption: String
    /// Owner UID. Used by security rules and per-user paths.
    var userId: String
    /// Cloud Storage download URL for the entry photo.
    var photoURL: String?
    /// Legacy field kept for backward compatibility with old entries that stored bytes in Firestore.
    var photoData: Data?
    var isFavorite: Bool = false
    var autoTags: [String]?
    /// Typo kept for compatibility with existing stored field name.
    var uesrTags: [String]?
    /// Optional metadata fields for future enhancements.
    var metadataTimestamp: Date?
    var metadataLongitude: Double?
    var metadataLatitute: Double?
    
    /// Firestore document id (not part of document body).
    @DocumentID var id: String?
    /// Firestore server-generated creation timestamp.
    @ServerTimestamp var createdAt: Date?

}
