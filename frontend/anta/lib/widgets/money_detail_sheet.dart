import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import '../l10n/app_localizations.dart';
import '../utils/markdown_money_syntax.dart';
import '../utils/money_display_config.dart';

/// Bottom sheet listing the ledger entries that feed a tapped `$$`
/// total, `$?` net-change, bare-`$!` target-status, `$^` entry-diff, or
/// `$~` checkpoint-span row — reached from both the preview pill and
/// the live editor's painted chip. Read-only: rows mirror the
/// inline rendering (same glyphs and accent palette) so the sheet and
/// the note always read as one system.
class MoneyDetailSheet extends StatelessWidget {
  final List<MoneyLedgerEntry> entries;
  final MoneyLineKind tappedKind;
  final MoneyDisplayConfig config;

  const MoneyDetailSheet({
    super.key,
    required this.entries,
    required this.tappedKind,
    required this.config,
  });

  static Future<void> show(
    BuildContext context, {
    required List<MoneyLedgerEntry> entries,
    required MoneyLineKind tappedKind,
    required MoneyDisplayConfig config,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MoneyDetailSheet(
        entries: entries,
        tappedKind: tappedKind,
        config: config,
      ),
    );
  }

  String _format(int cents, {required bool signed}) => signed
      ? MarkdownMoneySyntax.formatCentsSignedWithSymbol(
          cents,
          symbol: config.currencySymbol,
          suffix: config.currencySuffix,
        )
      : MarkdownMoneySyntax.formatCentsWithSymbol(
          cents,
          symbol: config.currencySymbol,
          suffix: config.currencySuffix,
        );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final tapped = entries.isNotEmpty ? entries.last : null;
    final headerValue = tapped?.valueAfter ?? 0;
    final signedHeader = MarkdownMoneySyntax.isSignedKind(tappedKind);
    // A bare-`$!` header wears the row's own status colour — green
    // while the budget holds (zero included), red once overspent — and
    // warns when there is no target to measure, exactly like the inline
    // chip it was opened from.
    final noTargetHeader =
        tappedKind == MoneyLineKind.remaining &&
        MarkdownMoneySyntax.isNoTarget(headerValue);
    final headerColor =
        noTargetHeader || MarkdownMoneySyntax.valuePinned(headerValue)
        ? MarkdownConstants.moneyWarning(dark: dark)
        : tappedKind == MoneyLineKind.remaining
        ? (headerValue < 0
              ? MarkdownConstants.moneyNegative(dark: dark)
              : MarkdownConstants.moneyPositive(dark: dark))
        : signedHeader
        ? (headerValue > 0
              ? MarkdownConstants.moneyPositive(dark: dark)
              : headerValue < 0
              ? MarkdownConstants.moneyNegative(dark: dark)
              : primary)
        : (headerValue < 0
              ? MarkdownConstants.moneyNegative(dark: dark)
              : primary);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    MarkdownMoneySyntax.glyph(tappedKind),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: headerColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.moneyDetailTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    noTargetHeader
                        ? 'no target'
                        : _format(headerValue, signed: signedHeader),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: headerColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final m = e.match;
                  // Error lines show a yellow indicator and the shared
                  // (localized) error message from the display config —
                  // the same resolution the preview renderer uses.
                  if (MarkdownMoneySyntax.hasError(m)) {
                    final errorColor = MarkdownConstants.moneyWarning(
                      dark: dark,
                    );
                    final errorMsg = config.errorText(m.error!);
                    return ListTile(
                      dense: true,
                      leading: Text(
                        '!',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: errorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      title: Text(
                        errorMsg,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: errorColor,
                        ),
                      ),
                      subtitle: Text(
                        e.line,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }
                  final isDisplay = MarkdownMoneySyntax.isDisplayKind(m.kind);
                  // Glyph from the shared palette; the row accent stays
                  // the sheet's deliberately flatter policy — display
                  // rows read in primary (their sign colour lives in
                  // the header value) and `$! N` declarations are
                  // neutral statements, like `$=`.
                  final glyph = MarkdownMoneySyntax.glyph(m.kind);
                  final accent = switch (m.kind) {
                    MoneyLineKind.set || MoneyLineKind.target => primary,
                    _ when isDisplay => primary,
                    _ => MarkdownConstants.moneyAccent(
                      m.kind,
                      e.valueAfter,
                      dark: dark,
                      primary: primary,
                    ),
                  };
                  final amount = isDisplay
                      ? (m.kind == MoneyLineKind.remaining &&
                                MarkdownMoneySyntax.isNoTarget(e.valueAfter)
                            ? 'no target'
                            : _format(
                                e.valueAfter,
                                signed: MarkdownMoneySyntax.isSignedKind(
                                  m.kind,
                                ),
                              ))
                      : e.line.substring(m.amountStart, m.amountEnd);
                  // One lib call composes the label the way the preview
                  // renders it inline: label-first colon trimmed,
                  // currency word skipped, free trailing text joined.
                  final label = MarkdownMoneySyntax.displayLabel(
                    e.line,
                    m,
                    config.currencySymbol,
                  );
                  return ListTile(
                    dense: true,
                    leading: Text(
                      glyph,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    title: Text(
                      label.isEmpty ? amount : '$amount  $label',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDisplay ? accent : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDisplay
                        ? null
                        : Text(
                            _format(e.valueAfter, signed: false),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.6),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
