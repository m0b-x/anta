import 'package:equatable/equatable.dart';

enum PermissionImportance { essential, recommended }

enum AppPermission {
  notifications(PermissionImportance.essential),
  exactAlarms(PermissionImportance.essential),
  fullScreenIntent(PermissionImportance.recommended),
  batteryOptimization(PermissionImportance.recommended);

  const AppPermission(this.importance);

  final PermissionImportance importance;

  bool get isEssential => importance == PermissionImportance.essential;
}

enum PermissionStatus { granted, denied, unknown, notApplicable }

enum PermissionPromptResult { granted, denied, blocked }

enum PermissionRequestOutcome { granted, denied, openedSettings, unavailable }

class PermissionEntry extends Equatable {
  const PermissionEntry({
    required this.permission,
    required this.status,
    required this.canPrompt,
  });

  final AppPermission permission;
  final PermissionStatus status;
  final bool canPrompt;

  bool get isMissing => status == PermissionStatus.denied;

  bool get isGranted => status == PermissionStatus.granted;

  bool get isUnknown => status == PermissionStatus.unknown;

  @override
  List<Object?> get props => [permission, status, canPrompt];
}

class PermissionSnapshot extends Equatable {
  const PermissionSnapshot(this.entries);

  static const PermissionSnapshot empty = PermissionSnapshot([]);

  final List<PermissionEntry> entries;

  bool get isEmpty => entries.isEmpty;

  PermissionEntry? entryOf(AppPermission permission) {
    for (final entry in entries) {
      if (entry.permission == permission) return entry;
    }
    return null;
  }

  PermissionStatus statusOf(AppPermission permission) =>
      entryOf(permission)?.status ?? PermissionStatus.notApplicable;

  bool isMissing(AppPermission permission) =>
      statusOf(permission) == PermissionStatus.denied;

  List<PermissionEntry> get missing => [
    for (final entry in entries)
      if (entry.isMissing) entry,
  ];

  List<PermissionEntry> get missingEssential => [
    for (final entry in entries)
      if (entry.isMissing && entry.permission.isEssential) entry,
  ];

  List<PermissionEntry> withImportance(PermissionImportance importance) => [
    for (final entry in entries)
      if (entry.permission.importance == importance) entry,
  ];

  bool get needsAttention =>
      entries.any((entry) => entry.isMissing && entry.permission.isEssential);

  bool get hasMissing => entries.any((entry) => entry.isMissing);

  bool get hasUnknown => entries.any((entry) => entry.isUnknown);

  @override
  List<Object?> get props => [entries];
}
