import 'package:flutter/material.dart';

/// A small rounded chip used to display metadata (e.g. step size, start value)
/// on counter cards.
class InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const InfoChip({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}
