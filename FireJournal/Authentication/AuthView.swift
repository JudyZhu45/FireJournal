//
//  AuthView.swift
//  FireJournal
//
//  Created by Andrew Binkowski on 4/25/25.
//

import SwiftUI

/// Simple authentication screen.
/// Allows user to toggle between Sign In and Sign Up flows.
struct AuthView: View {
    @Environment(AuthController.self) private var authController
    
    /// Local form values typed by the user.
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp  = false
    
    
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding()

            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            
            Button {
                authenticate()
            } label: {
                HStack {
                    Text("\(isSignUp ? "Sign Up" : "Sign In")")
                        .font(.title)
                }
            }
            .padding()
            .buttonStyle(.borderedProminent)
            
            Button("\(isSignUp ? "I have an account" : "I need an account")") {
                isSignUp.toggle()
            }
            
            if let errorMessage = authController.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .navigationTitle("Welcome")
    }
    
    //
    // MARK: - Sign Up/In
    //
    /// Routes button tap to the active auth action.
    func authenticate () {
        isSignUp ? signUp() : signIn()
        
    }
    
    /// Attempts sign in using email/password entered in this form.
    func signIn() {
        Task {
            do {
                try await authController.signIn(email: email, password: password)
            } catch {
                authController.errorMessage = error.localizedDescription
            }
        }
        
    }
    
    /// Attempts account creation using email/password entered in this form.
    func signUp() {
        Task {
            await authController.signUp(email: email, password: password)
        }
    }
}


#Preview {
    var authController = AuthController()
    return AuthView()
        .environment(authController)
        .onAppear {
            authController.listenToAuthChanges()
        }
}
