import 'package:artisans_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart'
    as picker;
import '../services/api_service.dart';
import '../services/payment_service.dart';
import '../models/artisan.dart';
import '../models/job.dart';
import '../widgets/rating_stars.dart';

class JobDetailScreen extends StatefulWidget {
  final Artisan? artisan;
  final Job? job;

  const JobDetailScreen({super.key, this.artisan, this.job});

  @override
  JobDetailScreenState createState() => JobDetailScreenState();
}

class JobDetailScreenState extends State<JobDetailScreen> {
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  double? _agreedPrice;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.job != null) {
      _descriptionController.text = widget.job!.description;
      _selectedDate = widget.job!.scheduledTime;
      _agreedPrice = widget.job!.agreedPrice;
    } else if (widget.artisan != null) {
      _agreedPrice = widget.artisan!.hourlyRate;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    picker.DatePicker.showDateTimePicker(
      context,
      showTitleActions: true,
      minTime: DateTime.now(),
      onConfirm: (date) => setState(() => _selectedDate = date),
      currentTime: _selectedDate ?? DateTime.now(),
      locale: picker.LocaleType.en,
    );
  }

  Future<void> _bookArtisan() async {
    if (_descriptionController.text.isEmpty ||
        _selectedDate == null ||
        _agreedPrice == null) {
      _showSnackBar('Please fill all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final apiService = Provider.of<ApiService>(context, listen: false);
      final paymentService = Provider.of<PaymentService>(
        context,
        listen: false,
      );

      final balance = await paymentService.getWalletBalance(
        authService.user!.uid,
      );
      if (balance < _agreedPrice!) {
        _showSnackBar('Insufficient wallet balance');
        return;
      }

      await apiService.createJob(
        customerId: authService.user!.uid,
        artisanId: widget.artisan!.id,
        description: _descriptionController.text,
        scheduledTime: _selectedDate!,
        agreedPrice: _agreedPrice!,
        location: widget.artisan!.location,
        latitude: widget.artisan!.latitude,
        longitude: widget.artisan!.longitude,
      );

      await paymentService.transferToArtisan(
        authService.user!.uid,
        widget.artisan!.id,
        _agreedPrice!,
        '',
      );

      _showSnackBar('Job booked successfully');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackBar('Error booking job: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rateJob() async {
    final ratingController = TextEditingController();
    final reviewController = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Rate this job'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ratingController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Rating (1-5)'),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'Review'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final rating = double.tryParse(ratingController.text);
                  if (rating == null || rating < 1 || rating > 5) {
                    _showSnackBar('Please enter a valid rating (1-5)');
                    return;
                  }

                  try {
                    final apiService = Provider.of<ApiService>(
                      context,
                      listen: false,
                    );
                    await apiService.rateJob(
                      widget.job!.id,
                      rating,
                      reviewController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      _showSnackBar('Rating submitted');
                      Navigator.pop(context);
                    }
                  } catch (_) {
                    _showSnackBar('Error submitting rating');
                  }
                },
                child: Text('Submit'),
              ),
            ],
          ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.scheduled:
        return Colors.blueAccent;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.job != null ? 'Job Details' : 'Book Artisan'),
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.artisan != null) _buildArtisanDetails(),
                    if (widget.job != null) _buildJobDetails(),
                    if (widget.artisan != null) _buildBookingForm(),
                  ],
                ),
              ),
    );
  }

  Widget _buildArtisanDetails() {
    final artisan = widget.artisan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          artisan.name,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          artisan.profession,
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            RatingStars(rating: artisan.rating),
            SizedBox(width: 8),
            Text('(${artisan.jobsCompleted} jobs)'),
          ],
        ),
        SizedBox(height: 16),
        _buildSectionTitle('About'),
        Text(artisan.bio),
        SizedBox(height: 16),
        _buildSectionTitle('Skills'),
        Wrap(
          spacing: 8.0,
          children:
              artisan.skills.map((skill) => Chip(label: Text(skill))).toList(),
        ),
      ],
    );
  }

  Widget _buildJobDetails() {
    final job = widget.job!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Job Description'),
        Text(job.description),
        SizedBox(height: 16),
        _buildSectionTitle('Details'),
        Text(
          'Scheduled: ${DateFormat.yMMMd().add_jm().format(job.scheduledTime)}',
        ),
        Text('Location: ${job.location}'),
        Text('Price: \$${job.agreedPrice.toStringAsFixed(2)}'),
        SizedBox(height: 8),
        Chip(
          label: Text(job.status.toString().split('.').last),
          backgroundColor: _getStatusColor(job.status),
        ),
        if (job.status == JobStatus.completed && job.rating == null) ...[
          SizedBox(height: 16),
          ElevatedButton(onPressed: _rateJob, child: Text('Rate this Job')),
        ],
        if (job.rating != null) ...[
          SizedBox(height: 16),
          _buildSectionTitle('Your Rating'),
          RatingStars(rating: job.rating!),
          if (job.review != null) Text(job.review!),
        ],
      ],
    );
  }

  Widget _buildBookingForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24),
        _buildSectionTitle('Book This Artisan'),
        SizedBox(height: 16),
        TextField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'Job Description',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedDate == null
                    ? 'Select Date & Time'
                    : 'Scheduled: ${DateFormat.yMMMd().add_jm().format(_selectedDate!)}',
              ),
            ),
            TextButton(
              onPressed: () => _selectDate(context),
              child: Text('Select'),
            ),
          ],
        ),
        SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            labelText: 'Agreed Price',
            prefixText: '\$',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged:
              (value) => setState(() => _agreedPrice = double.tryParse(value)),
          controller: TextEditingController(
            text: _agreedPrice?.toStringAsFixed(2),
          ),
        ),
        SizedBox(height: 24),
        ElevatedButton(
          onPressed: _bookArtisan,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 50),
          ),
          child: Text('Book Now'),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) =>
      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
}
