import 'package:artisans_app/services/auth_service.dart';
import 'package:artisans_app/widgets/rating_stars.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../models/job.dart';

class ArtisanDashboardScreen extends StatefulWidget {
  const ArtisanDashboardScreen({super.key});

  @override
  ArtisanDashboardScreenState createState() => ArtisanDashboardScreenState();
}

class ArtisanDashboardScreenState extends State<ArtisanDashboardScreen> {
  late Future<List<Job>> _jobsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _jobsFuture = _apiService.getJobsForUser(
      authService.user!.uid,
      isArtisan: true,
    );
  }

  Future<void> _refreshJobs() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _jobsFuture = _apiService.getJobsForUser(
        authService.user!.uid,
        isArtisan: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Artisan Dashboard'),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _refreshJobs),
        ],
      ),
      body: FutureBuilder<List<Job>>(
        future: _jobsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading jobs'));
          }

          final jobs = snapshot.data ?? [];

          if (jobs.isEmpty) {
            return Center(child: Text('No jobs found'));
          }

          return RefreshIndicator(
            onRefresh: _refreshJobs,
            child: ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                return JobCard(
                  job: job,
                  onStatusChanged: (newStatus) async {
                    try {
                      await _apiService.updateJobStatus(job.id, newStatus);
                      _refreshJobs();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error updating job status')),
                        );
                      }
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final Job job;
  final Function(JobStatus) onStatusChanged;

  const JobCard({super.key, required this.job, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.description,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Location: ${job.location}'),
            Text(
              'Scheduled: ${DateFormat.yMMMd().add_jm().format(job.scheduledTime)}',
            ),
            Text('Price: \$${job.agreedPrice.toStringAsFixed(2)}'),
            SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(job.status.toString().split('.').last),
                  backgroundColor: _getStatusColor(job.status),
                ),
                Spacer(),

                if (job.status == JobStatus.scheduled)
                  ElevatedButton(
                    onPressed: () => onStatusChanged(JobStatus.inProgress),
                    child: Text('Start Job'),
                  ),

                if (job.status == JobStatus.inProgress)
                  ElevatedButton(
                    onPressed: () => onStatusChanged(JobStatus.completed),
                    child: Text('Complete Job'),
                  ),
              ],
            ),
            if (job.status == JobStatus.completed && job.rating != null)
              Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Text('Rating: '),
                    RatingStars(rating: job.rating!),
                  ],
                ),
              ),
            if (job.status == JobStatus.completed && job.review != null)
              Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text('Review: ${job.review}'),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.scheduled:
        return Colors.blue;
      case JobStatus.inProgress:
        return Colors.orange;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.cancelled:
        return Colors.red;
      case JobStatus.disputed:
        return Colors.purple;
    }
  }
}
