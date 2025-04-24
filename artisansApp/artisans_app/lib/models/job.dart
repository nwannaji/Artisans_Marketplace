enum JobStatus { scheduled, inProgress, completed, cancelled, disputed }

class Job {
  final String id;
  final String customerId;
  final String artisanId;
  final String description;
  final DateTime scheduledTime;
  final double agreedPrice;
  final String location;
  final double latitude;
  final double longitude;
  final JobStatus status;
  final double? rating;
  final String? review;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Job({
    required this.id,
    required this.customerId,
    required this.artisanId,
    required this.description,
    required this.scheduledTime,
    required this.agreedPrice,
    required this.location,
    required this.latitude,
    required this.longitude,
    this.status = JobStatus.scheduled,
    this.rating,
    this.review,
    required this.createdAt,
    this.updatedAt,
  });

  factory Job.fromMap(Map<String, dynamic> map) {
    return Job(
      id: map['id'],
      customerId: map['customerId'],
      artisanId: map['artisanId'],
      description: map['description'],
      scheduledTime: DateTime.parse(map['scheduledTime']),
      agreedPrice: map['agreedPrice']?.toDouble() ?? 0.0,
      location: map['location'],
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      status: JobStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => JobStatus.scheduled,
      ),
      rating: map['rating']?.toDouble(),
      review: map['review'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt:
          map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'artisanId': artisanId,
      'description': description,
      'scheduledTime': scheduledTime.toIso8601String(),
      'agreedPrice': agreedPrice,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.name,
      'rating': rating,
      'review': review,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
