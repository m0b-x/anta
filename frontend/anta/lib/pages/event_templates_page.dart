import 'package:flutter/material.dart';

import '../constants/calendar_templates.dart';
import '../l10n/app_localizations.dart';
import '../models/event_template.dart';
import '../services/event_template_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/event_template_summary.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/event_template_editor_sheet.dart';
import '../widgets/unified_app_bars.dart';

/// Management page for event templates. Mirrors [CalendarCategoriesPage]:
/// mutations go directly through [EventTemplateService] (the same
/// service-direct pattern the category and holiday pages use), and the
/// in-memory [CalendarTemplates] cache is republished by the service, so the
/// calendar's quick-add reflects changes as soon as the user returns to it.
class EventTemplatesPage extends StatefulWidget {
  const EventTemplatesPage({super.key});

  @override
  State<EventTemplatesPage> createState() => _EventTemplatesPageState();
}

class _EventTemplatesPageState extends State<EventTemplatesPage> {
  EventTemplateService? _service;
  List<EventTemplate> _templates = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await EventTemplateService.getInstance();
    if (!mounted) return;
    setState(() {
      _service = service;
      _templates = service.templates;
      _isLoading = false;
    });
  }

  void _refresh() {
    final service = _service;
    if (service == null) return;
    setState(() => _templates = service.templates);
  }

  Future<void> _create() async {
    final created = await EventTemplateEditorSheet.show(context);
    if (created == null || !mounted) return;
    _refresh();
  }

  Future<void> _edit(EventTemplate template) async {
    final updated = await EventTemplateEditorSheet.show(
      context,
      initial: template,
    );
    if (updated == null || !mounted) return;
    _refresh();
  }

  Future<void> _delete(EventTemplate template) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteTemplate,
      content: l10n.deleteTemplateConfirm(template.name),
      confirmText: l10n.delete,
      icon: Icons.delete_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _service?.deleteTemplate(template.id);
    if (!mounted) return;
    _refresh();
    CustomSnackbar.showSuccess(context, l10n.templateDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.eventTemplates,
        showMenuButton: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.createTemplate),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
          ? _EmptyState(
              title: l10n.noEventTemplates,
              body: l10n.noEventTemplatesDesc,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _templates.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final template = _templates[index];
                final color = CalendarTemplates.colorFor(template);
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainer,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.18),
                      foregroundColor: color,
                      child: Icon(CalendarTemplates.iconFor(template)),
                    ),
                    title: Text(
                      template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      templateSummary(template, l10n, l10n.localeName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: false,
                    trailing: IconButton(
                      tooltip: l10n.deleteTemplate,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      onPressed: () => _delete(template),
                    ),
                    onTap: () => _edit(template),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
