# Society Management - Workspace Rules

## Mandatory APK Build & Emulator Installation Rule
- **Always Deploy via APK to Specific Emulators:** Always deploy new code by building the APK (e.g. `flutter build apk --flavor <flavor> -t lib/main_<flavor>.dart` or `flutter build apk --debug --flavor <flavor> -t lib/main_<flavor>.dart`) and installing it via `adb -s <device> install -r <apkPath>`. Do NOT use `flutter run` on the emulators anymore.
  - **Guard App (`guard` flavor / `main_guard.dart`):** ALWAYS install into the **Small Phone** emulator (e.g. `emulator-5556`).
  - **Resident App (`resident` flavor / `main_resident.dart`):** ALWAYS install into the **Pixel** emulator (e.g. `emulator-5554`).
- **Do Not Self-Test After Installation:** Once the APK installation is complete on the emulators, immediately inform the user and stop. Do NOT try to test the code, interact with the UI, inject inputs, or simulate user flows on the emulator on your own.
- **Local Quality Verification Before Build:** For all features and bug fixes, verify locally with `dart analyze` (0 issues) and `flutter test` before building and installing the APKs.
- **Only Deploy Remotely When Explicitly Asked:** Do NOT perform remote deployments (`firebase deploy`, `flutter build web --release`, etc.) automatically. Only deploy remotely when explicitly requested.

## Non-Destructive Code & Feature Preservation Rule
- **Never Overwrite Existing Code or Features Unintentionally:** Whenever any new line of code or feature is written, it must never overwrite, break, or delete existing functionality, business logic, UI components, or previous fixes.
- **Coexistence by Refactoring:** Always design new code to coexist harmoniously with existing code.
- **Mandatory User Notification on Conflict:** If a change cannot avoid altering or replacing existing code or functionality, immediately inform the user before or when doing so, explain the trade-offs, and proactively refactor the architecture so that both the existing and new capabilities coexist seamlessly without regression.

## Mandatory Human-Readable Code Commenting Rule
- **Mandatory Explanatory Comments on New Code:** Whenever any new line of code, logic branch, function, calculation, state transition, or UI widget is written or modified, insert clear, human-readable, and easily understandable comments explaining what the code is doing and the rationale/context from the perspective of that specific code block.
- **Facilitate Manual Maintenance & Editing:** All comments must provide enough clarity and context so that any human developer can read through, grasp the architectural and business logic intent immediately, and perform safe manual edits without confusion or guesswork.

