# Society Management - Workspace Rules

## Mandatory Local Execution & Hot Reload Rule
- **Automatic Local Hot Reload / Refresh:** Whenever any local change or edit to Dart/Flutter code is completed, always trigger a **Hot Reload** (or **Hot Restart / Hot Refresh** if state or structural changes require it) to ensure the running application immediately reflects the modifications.
- **Only Deploy When Explicitly Asked:** Do NOT perform remote builds or deployments (`firebase deploy`, `flutter build web --release`, etc.) automatically. Only deploy when the user explicitly requests deployment.
- **Local Quality Verification:** For all features and bug fixes, verify locally with `dart analyze` (0 issues) and `flutter test`.

## Non-Destructive Code & Feature Preservation Rule
- **Never Overwrite Existing Code or Features Unintentionally:** Whenever any new line of code or feature is written, it must never overwrite, break, or delete existing functionality, business logic, UI components, or previous fixes.
- **Coexistence by Refactoring:** Always design new code to coexist harmoniously with existing code.
- **Mandatory User Notification on Conflict:** If a change cannot avoid altering or replacing existing code or functionality, immediately inform the user before or when doing so, explain the trade-offs, and proactively refactor the architecture so that both the existing and new capabilities coexist seamlessly without regression.

## Mandatory Human-Readable Code Commenting Rule
- **Mandatory Explanatory Comments on New Code:** Whenever any new line of code, logic branch, function, calculation, state transition, or UI widget is written or modified, insert clear, human-readable, and easily understandable comments explaining what the code is doing and the rationale/context from the perspective of that specific code block.
- **Facilitate Manual Maintenance & Editing:** All comments must provide enough clarity and context so that any human developer can read through, grasp the architectural and business logic intent immediately, and perform safe manual edits without confusion or guesswork.

