class Job {
  final String id;
  final String customerId;
  final String artisanId;
  final String jobType;
  final String location;
  final double estimatedCost;
  final String description;
  final String status; // e.g., 'pending', 'completed'

  Job({
    required this.id,
    required this.customerId,
    required this.artisanId,
    required this.jobType,
    required this.location,
    required this.estimatedCost,
    required this.description,
    required this.status,
  });
}
