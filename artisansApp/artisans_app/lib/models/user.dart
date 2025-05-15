class AppUser {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String phoneNumber;
  final String? password;
  final String role; // 'artisan' or 'customer'

  AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    required this.phoneNumber,
    this.password,
    required this.role,
  });
}
