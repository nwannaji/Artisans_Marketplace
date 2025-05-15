// rating_selector.dart
import 'package:flutter/material.dart';

class RatingSelector extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double> onRatingSelected;

  const RatingSelector({
    super.key,
    required this.initialRating,
    required this.onRatingSelected,
  });

  @override
  RatingSelectorState createState() => RatingSelectorState();
}

class RatingSelectorState extends State<RatingSelector> {
  late double _selectedRating;

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Ratings:', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Row(
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRating = index + 1.0;
                });
                widget.onRatingSelected(_selectedRating); // callback
              },
              child: Icon(
                index < _selectedRating ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 20,
              ),
            );
          }),
        ),
        const SizedBox(width: 6),
        Text(
          '${_selectedRating.toStringAsFixed(1)} Stars',
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
