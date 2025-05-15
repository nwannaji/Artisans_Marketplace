class Artisan {
  final String id;
  String firstName;
  String lastName;
  final String profilePicture;
  final String expertise; // Plumbing, Electrical, etc.
  final String location;
  final String accountNumber;
  final String bankName;
  final int ratings; //5=highest stars or one Gold
  final List<String> status;

  Artisan({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.profilePicture,
    required this.expertise,
    required this.location,
    required this.accountNumber,
    required this.bankName,
    required this.ratings,
    required this.status,
  });
}
