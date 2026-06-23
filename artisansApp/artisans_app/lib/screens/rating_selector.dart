// rating_selector.dart
import 'package:flutter/material.dart';

/// A reusable star rating widget.
///
/// [initialRating] sets the starting rating (default 0).
/// [onRatingSelected] fires when a star is tapped.
/// [starSize] controls icon size.
/// [color] controls star color.
/// [showLabel] whether to show the numeric label.
/// [enabled] when false, stars are display-only (read-only).
class RatingSelector extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double> onRatingSelected;
  final double starSize;
  final Color color;
  final bool showLabel;
  final bool enabled;

  const RatingSelector({
    super.key,
    this.initialRating = 0,
    required this.onRatingSelected,
    this.starSize = 24,
    this.color = Colors.amber,
    this.showLabel = true,
    this.enabled = true,
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
  void didUpdateWidget(covariant RatingSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRating != widget.initialRating) {
      _selectedRating = widget.initialRating;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: List.generate(5, (index) {
            final starValue = (index + 1).toDouble();
            final isFull = _selectedRating >= starValue;
            final isHalf = !isFull && _selectedRating >= starValue - 0.5;

            return GestureDetector(
              onTap: widget.enabled
                  ? () {
                      setState(() => _selectedRating = starValue);
                      widget.onRatingSelected(starValue);
                    }
                  : null,
              child: Icon(
                isFull
                    ? Icons.star
                    : isHalf
                        ? Icons.star_half
                        : Icons.star_border,
                color: (isFull || isHalf) ? widget.color : Colors.grey[400],
                size: widget.starSize,
              ),
            );
          }),
        ),
        if (widget.showLabel) ...[
          const SizedBox(width: 6),
          Text(
            _selectedRating > 0 ? '${_selectedRating.toStringAsFixed(1)} Stars' : 'Tap to rate',
            style: TextStyle(
              fontSize: widget.starSize > 20 ? 14 : 12,
              color: _selectedRating > 0 ? widget.color : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// A read-only star display for showing existing ratings.
class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final double starSize;
  final Color color;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.reviewCount = 0,
    this.starSize = 16,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          final starValue = (index + 1).toDouble();
          final isFull = rating >= starValue;
          final isHalf = !isFull && rating >= starValue - 0.5;
          return Icon(
            isFull ? Icons.star : isHalf ? Icons.star_half : Icons.star_border,
            color: (isFull || isHalf) ? color : Colors.grey[400],
            size: starSize,
          );
        }),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        if (reviewCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '($reviewCount)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }
}