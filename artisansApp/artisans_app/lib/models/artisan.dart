class Artisan {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String profession;
  final String bio;
  final double rating;
  final int jobsCompleted;
  final String location;
  final double latitude;
  final double longitude;
  final double hourlyRate;
  final List<String> skills;
  final List<String> certificates;
  final String bankAccount;
  final String bankName;
  final bool isVerified;

  Artisan({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.profession,
    required this.bio,
    this.rating = 0.0,
    this.jobsCompleted = 0,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.hourlyRate,
    required this.skills,
    required this.certificates,
    required this.bankAccount,
    required this.bankName,
    this.isVerified = false,
  });

  factory Artisan.fromMap(Map<String, dynamic> map) {
    return Artisan(
      id: map['id'],
      name: map['name'],
      email: map['email'],
      phone: map['phone'],
      profession: map['profession'],
      bio: map['bio'],
      rating: map['rating']?.toDouble() ?? 0.0,
      jobsCompleted: map['jobsCompleted'] ?? 0,
      location: map['location'],
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      hourlyRate: map['hourlyRate']?.toDouble() ?? 0.0,
      skills: List<String>.from(map['skills'] ?? []),
      certificates: List<String>.from(map['certificates'] ?? []),
      bankAccount: map['bankAccount'],
      bankName: map['bankName'],
      isVerified: map['isVerified'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'profession': profession,
      'bio': bio,
      'rating': rating,
      'jobsCompleted': jobsCompleted,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'hourlyRate': hourlyRate,
      'skills': skills,
      'certificates': certificates,
      'bankAccount': bankAccount,
      'bankName': bankName,
      'isVerified': isVerified,
    };
  }
}
