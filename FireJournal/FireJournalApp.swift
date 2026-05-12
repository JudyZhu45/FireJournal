//
//  FireJournalApp.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/24/25.
//

import SwiftUI
import FirebaseCore

@main

/// App entry point.
/// Responsibilities:
/// 1. Configure Firebase once at launch.
/// 2. Create shared authentication state.
/// 3. Inject that state into the SwiftUI environment.
struct FireJournalApp: App {
    /// Shared authentication/session state used by multiple views.
    @State private var authController = AuthController()
    
    init() {
        // Connect app to the Firebase project defined in GoogleService-Info.plist.
        FirebaseApp.configure()
        
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authController)
                .onAppear {
                    // Begin listening so the root UI can switch between auth and journal views.
                    authController.listenToAuthChanges()
                }
        }
    }
}
