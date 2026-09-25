import 'package:flutter/material.dart';

class EventAvatar extends StatelessWidget {
  static const double radius = 20;
  static const double iconSize = 24;
  static const double backgroundAlpha = 0.16;

  final IconData icon;
  final Color color;

  const EventAvatar({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color.withValues(alpha: backgroundAlpha),
        foregroundColor: color,
        child: Icon(icon, size: iconSize),
      ),
    );
  }
}
