## Quick context for AI coding agents

This is a small Flutter app named `Arena`. Key entry points and conventions:

- App root: `lib/main.dart` — sets `initialRoute: '/'` and routes for `/` (login) and `/home`.
- Screens live under `lib/screens/` (example: `login_screen.dart`, `home_screen.dart`).
- Reusable UI components are in `lib/widgets/` (example: `custom_button.dart`).
- Business logic / integrations should go in `lib/services/` (currently `auth_service.dart` is a placeholder).
- Domain models belong in `lib/models/` (`user_model.dart` is currently empty).

## Big-picture architecture

This is a typical small Flutter app with UI (screens + widgets) and a light service layer. The current structure is:

- Presentation: `lib/screens/*` — mostly StatefulWidgets for pages.
- UI components: `lib/widgets/*` — StatelessWidgets such as `CustomButton`.
- Services: `lib/services/*` — intended for network/auth/business logic (not implemented yet).
- Models: `lib/models/*` — data transfer and domain types (mostly empty now).

The app uses named routes (see `MaterialApp.routes` in `lib/main.dart`) and simple Navigator usage (example: `Navigator.pushReplacementNamed(context, '/home')` in `login_screen.dart`).

## Project-specific conventions to follow

- Keep widget-only UI in `lib/widgets/` and avoid embedding networking there.
- Put API calls, authentication, and persistence in `lib/services/` (e.g., implement `AuthService` in `lib/services/auth_service.dart`).
- Define DTOs and domain types in `lib/models/` (create fields and JSON (de)serialization only if you add network integration).
- Screens use form validation patterns with `GlobalKey<FormState>` (see `login_screen.dart`). Follow that style for other forms.
- Theme is configured in `lib/main.dart` (primary color deepPurple and scaffold background color); reuse theme colors instead of hard-coded colors where possible.

## Integration points & TODOs

- `lib/screens/login_screen.dart` includes a TODO comment: "// TODO: connect to backend later" — this is the expected place to call an AuthService.
- `lib/services/auth_service.dart` and `lib/models/user_model.dart` are empty files — implement login/register functions and model fields here.
- `test/widget_test.dart` exists — use `flutter test` to run unit/widget tests.

## Build / test / debug commands (Windows dev environment)

- Install deps: `flutter pub get`
- Analyze: `flutter analyze` (project uses `flutter_lints` and `analysis_options.yaml` exists)
- Run on Windows: `flutter run -d windows` (the repo contains `windows/`)
- Run on connected device/emulator: `flutter devices` then `flutter run -d <id>`
- Build APK: `flutter build apk`
- Run tests: `flutter test`

Note: Android/iOS builds follow normal Flutter workflows (see `android/` and `ios/` directories). Gradle files are present under `android/`.

## Short examples (follow these patterns)

- Calling auth service from `login_screen.dart` (pseudo):

  1. Implement `class AuthService { Future<User?> login(String email, String pwd) {...} }` in `lib/services/auth_service.dart`.
  2. From `_login()` in `login_screen.dart` call:
     - `final user = await AuthService().login(_emailController.text, _passwordController.text);`
     - On success: `Navigator.pushReplacementNamed(context, '/home');`

- Model hint: `lib/models/user_model.dart` should contain a small POJO-like class and optional `fromJson/toJson` if you add HTTP calls.

## Files to inspect when making changes

- `lib/main.dart` — app routing & theme
- `lib/screens/login_screen.dart` — forms and navigation example
- `lib/widgets/custom_button.dart` — preferred button styling
- `lib/services/auth_service.dart` — implement authentication here
- `lib/models/user_model.dart` — model definitions

## What not to assume

- There is no backend integration yet — tests or logic that expect a remote API will need mocks or a local stub.
- `auth_service.dart` and `user_model.dart` are intentionally empty — they should be implemented to add functionality.

If any of the TODOs are unclear (expected API shape, auth flow, or navigation edge-cases), ask the repo owner for the backend contract or preferred user flow before implementing.

---

If you'd like, I can: (A) implement a minimal `AuthService` with a local stub and update `login_screen.dart` to call it, or (B) add a simple `User` model and a unit test for the login form. Which should I do next?
