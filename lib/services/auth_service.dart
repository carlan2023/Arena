import '../models/user_model.dart';

class AuthService {
  // Simulated delay for network calls
  static const Duration _networkDelay = Duration(seconds: 1);

  /// Login with email and password
  /// Returns User if successful, null otherwise
  Future<User?> login(String email, String password) async {
    // Simulate network delay
    await Future.delayed(_networkDelay);

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      return null;
    }

    // TODO: Replace with actual HTTP call to backend
    // Example:
    // final response = await http.post(
    //   Uri.parse('https://api.example.com/login'),
    //   body: {'email': email, 'password': password},
    // );
    // if (response.statusCode == 200) {
    //   final json = jsonDecode(response.body);
    //   return User.fromJson(json['user']);
    // }

    // Local stub for testing
    return User(id: '123', email: email, name: 'John Doe');
  }

  /// Register a new user
  /// Returns User if successful, null otherwise
  Future<User?> register(String email, String password, String name) async {
    // Simulate network delay
    await Future.delayed(_networkDelay);

    // Basic validation
    if (email.isEmpty || password.isEmpty || name.isEmpty) {
      return null;
    }

    // TODO: Replace with actual HTTP call to backend
    // Example:
    // final response = await http.post(
    //   Uri.parse('https://api.example.com/register'),
    //   body: {'email': email, 'password': password, 'name': name},
    // );
    // if (response.statusCode == 201) {
    //   final json = jsonDecode(response.body);
    //   return User.fromJson(json['user']);
    // }

    // Local stub for testing
    return User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: email,
      name: name,
    );
  }

  /// Logout (placeholder for future implementation)
  Future<void> logout() async {
    // TODO: Implement logout logic (clear tokens, etc.)
    await Future.delayed(_networkDelay);
  }
}
