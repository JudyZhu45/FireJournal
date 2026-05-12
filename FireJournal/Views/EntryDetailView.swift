//
//  EntryDetailView.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/25/25.
//

import SwiftUI
import UIKit

/// Detail screen for one journal entry.
/// Presented when a row is tapped in `JournalView`.
struct EntryDetailView: View {
    let entry: Entry
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let createdAt = entry.createdAt {
                    Label(createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let photoURL = entry.photoURL, let url = URL(string: photoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                        case .empty:
                            ProgressView()
                                .frame(height: 240)
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
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text(entry.caption)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )

                if let tags = entry.autoTags, !tags.isEmpty {
                    EntryTagChipsView(tags: tags)
                }
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
