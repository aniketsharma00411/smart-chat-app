# Smart Chat App

A modern messaging application built with Flutter and Firebase, featuring real-time chat, AI-powered tone analysis, and message translation.

## Features

*   **Real-time Messaging**: Instant message delivery using Cloud Firestore.
*   **Google Sign-In**: Secure authentication with Firebase Auth.
*   **Share ID System**: Unique 6-digit IDs for easy user discovery.
*   **AI Integration**: Tone analysis and translation for messages.
*   **Cross-Platform**: Runs on Web, Android, and iOS.

## Getting Started

### Prerequisites

*   [Flutter SDK](https://flutter.dev/docs/get-started/install)
*   [Git](https://git-scm.com/)
*   **For iOS**: [Xcode](https://developer.apple.com/xcode/) (Mac only)
*   **For Android**: [Android Studio](https://developer.android.com/studio)
*   Top-secret configuration files (ask the project owner!)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd smart-chat-app
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase:**
    **IMPORTANT:** This project connects to a private Firebase backend. You need to obtain the configuration files/credentials from the project owner.

    *   **Web**:
        *   Obtain `lib/firebase_options.dart`.
        *   Place it in `lib/firebase_options.dart`.
        *   Ensure `lib/main.dart` imports and uses `DefaultFirebaseOptions.currentPlatform`.
        *   **API URL**: Obtain `lib/core/config/api_config.dart` and place it there.

    *   **Android**:
        *   Obtain `google-services.json`.
        *   Place it in `android/app/google-services.json`.

    *   **iOS**:
        *   Obtain `GoogleService-Info.plist`.
        *   Place it in `ios/Runner/GoogleService-Info.plist`.

4.  **Run the App:**
    ```bash
    # For Web (Chrome)
    flutter run -d chrome

    # For Android/iOS (Emulator or Device)
    flutter run
    ```

## Project Structure

*   `lib/core/services`: Backend services (Auth, Firestore, API).
*   `lib/features/auth`: Login screen and logic.
*   `lib/features/chat`: Chat lists, detailed chat view, and message models.
*   `lib/features/call`: UI for audio/video calls (frontend only).

## Troubleshooting

*   **Missing User ID**: If your Share ID doesn't appear in the side menu, refresh the app. The app attempts to self-repair missing IDs on reload.
*   **Firebase Errors**: Ensure your `firebase_options.dart` or `google-services.json` matches the package name/bundle ID of the app.