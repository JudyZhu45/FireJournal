//
//  ContentView.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/24/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

/// Root router for the app's UI.
/// Decides which screen to show based on authentication state.
struct ContentView: View {
    
    @Environment(AuthController.self) private var authController
    
    var body: some View {
        Group {
            switch authController.authState {
            case .undefined:
                // Initial loading state while Firebase auth resolves current user.
                ProgressView()
            case .notAuthenticated:
                AuthView()
            case .authenticated:
                if authController.userId.isEmpty {
                    // Auth says signed in, but UID has not been populated yet.
                    ProgressView("Loading account...")
                } else {
                    // .id(userId) forces a fresh JournalView + FirestoreQuery
                    // if a different user signs in.
                    JournalView(userId: authController.userId)
                        .id(authController.userId)
                }
            }
        }
    }
    
}


#Preview {
    NavigationView {
        ContentView()
    }
}
