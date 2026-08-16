import 'package:flutter/material.dart';

import '../models/app_user.dart';

/// The signed-in account's Google picture, falling back to a person icon.
///
/// Offline-first: a failed fetch degrades to the icon silently. The error
/// handler must stay null when there is no image, or `CircleAvatar` asserts.
class UserAvatar extends StatelessWidget {
  final AppUser user;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = user.photoUrl;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Icon(
        Icons.person_rounded,
        size: radius,
        color: foregroundColor ?? colorScheme.primary,
      ),
    );
  }
}
