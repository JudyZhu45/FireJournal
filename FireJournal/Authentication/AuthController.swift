//
//  AuthController.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/25/25.
//

import SwiftUI
import FirebaseAuth

/// High-level authentication state that drives root navigation.
enum AuthState {
    case undefined, authenticated, notAuthenticated
}

/// Central authentication manager for the app.
/// Keeps UI-facing state (auth status, user id, errors) in one place.
@Observable class AuthController {
    
    var email = ""
    var password = ""
    var isLoggedIn = false
    var errorMessage: String?
    var authState: AuthState = .undefined
    
    /// Firebase UID of the signed-in user.
    /// Used to scope Firestore reads/writes to the current user.
    var userId: String = ""
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    
    /// Starts listening to Firebase Auth state changes.
    /// Call this once when the app starts.
    func listenToAuthChanges() {
        guard authStateListener == nil else { return }
        authStateListener = Auth.auth().addStateDidChangeListener { auth, user in
            self.authState = user != nil ? .authenticated : .notAuthenticated
            if let user {
                self.userId = user.uid
                print("User ID: \(self.userId)")
            } else {
                self.userId = ""
                print("No user is signed in.")
            }
        }
    }
    
    /// Creates a new user account in Firebase Authentication.
    func signUp(email: String, password: String) async {
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    /// Signs in an existing user.
    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }
    
    /// Signs out current user and resets UI-facing auth state.
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.isLoggedIn = false
            self.errorMessage = nil
            self.authState = .notAuthenticated
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
    }

    deinit {
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }
    
}
