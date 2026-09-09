# Society Management - Workspace Rules

## Mandatory Local Execution & Hot Reload Rule
- **Automatic Local Hot Reload / Refresh:** Whenever any local change or edit to Dart/Flutter code is completed, always trigger a **Hot Reload** (or **Hot Restart / Hot Refresh** if state or structural changes require it) to ensure the running application immediately reflects the modifications.
- **Only Deploy When Explicitly Asked:** Do NOT perform remote builds or deployments (`firebase deploy`, `flutter build web --release`, etc.) automatically. Only deploy when the user explicitly requests deployment.
- **Local Quality Verification:** For all features and bug fixes, verify locally with `dart analyze` (0 issues) and `flutter test`.
