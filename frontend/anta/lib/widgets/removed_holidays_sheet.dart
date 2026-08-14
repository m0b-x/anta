import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../services/public_holiday_service.dart';
import '../utils/custom_snackbar.dart';

/// Bottom sheet listing every built-in holiday the user has suppressed for
/// a specific date, each with a "Restore" action. Suppressing (rather than
/// deleting) a built-in row is what makes the removal survive an app
/// restart or backup restore; this sheet is the durable undo path for
/// someone who changes their mind after the snackbar's Undo has expired.
class RemovedHolidaysSheet extends StatefulWidget {
  final PublicHolidayService holidayService;

  const RemovedHolidaysSheet({super.key, required this.holidayService});

  static Future<void> show(
    BuildContext context,
    PublicHolidayService holidayService,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.6,
        child: RemovedHolidaysSheet(holidayService: holidayService),
      ),
    );
  }

  @override
  State<RemovedHolidaysSheet> createState() => _RemovedHolidaysSheetState();
}

class _RemovedHolidaysSheetState extends State<RemovedHolidaysSheet> {
  List<SuppressedHoliday>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.holidayService.suppressedHolidays();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _restore(SuppressedHoliday item) async {
    await widget.holidayService.restoreSuppressed(item.date, item.holiday);
    if (!mounted) return;
    setState(() => _items?.remove(item));
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.holidayRestored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final items = _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.removedHolidays,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.removedHolidaysEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(PublicHolidays.nameOf(item.holiday, l10n)),
                      subtitle: Text(
                        DateFormat.yMMMMd(l10n.localeName).format(item.date),
                      ),
                      trailing: TextButton(
                        onPressed: () => _restore(item),
                        child: Text(l10n.holidayRestore),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
