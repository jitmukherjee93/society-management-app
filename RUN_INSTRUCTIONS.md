# Society Management App - Run Instructions

## Prerequisites
1. **Flutter SDK**: Ensure Flutter is installed and added to your PATH (v3.19 or higher recommended).
2. **Firebase Account**: Ensure you have access to the Firebase project \society-management-app-a808b\.
3. **Node.js & npm**: Required for Firebase CLI.

## 1. Environment Setup
Open your terminal and navigate to the project directory:
\\\ash
cd "C:\Personal Projects\Society Management"
\\\`n
## 2. Install Dependencies
Run the following command to fetch all Flutter packages:
\\\ash
flutter pub get
\\\`n
## 3. Firebase Configuration
If this is your first time setting it up on a new machine:
1. Install Firebase CLI globally: \
pm install -g firebase-tools\`n2. Log in to Firebase: \irebase login\`n3. Configure FlutterFire: \dart pub global activate flutterfire_cli\ then \lutterfire configure --project=society-management-app-a808b\`n
*(Note: The configuration file \lib/firebase_options.dart\ is already generated and included in the project.)*

## 4. Run the Application
You can run the app on an Android emulator, iOS simulator, Web, or Windows Desktop.

To see available devices:
\\\ash
flutter devices
\\\`n
To run the app:
\\\ash
flutter run
\\\`n
## 5. Testing the Roles
When you first launch the app:
1. Enter a phone number (e.g., +1 555-555-5555) and use the test OTP code (usually 123456 if set up in Firebase console, otherwise use Email login).
2. You will be prompted to complete your profile.
3. Select your role (Resident, Guard, or Admin) to test the respective dashboards.
