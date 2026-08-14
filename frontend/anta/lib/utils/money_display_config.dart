import '../l10n/app_localizations.dart';
import 'markdown_money_syntax.dart';

/// Localized display strings for [MoneyLineError], carried by value so
/// render-cache keys change when the locale does. Value-equal on every
/// field: two instances with the same strings are the same messages.
class MoneyErrorMessages {
  final String missingAmount;
  final String unknownColour;
  final String invalidAmount;
  final String invalidCount;
  final String divideByZero;
  final String amountTooLarge;
  final String tooManyDecimals;

  const MoneyErrorMessages({
    required this.missingAmount,
    required this.unknownColour,
    required this.invalidAmount,
    required this.invalidCount,
    required this.divideByZero,
    required this.amountTooLarge,
    required this.tooManyDecimals,
  });

  /// The localized messages for [l10n] — the one place the ARB keys map
  /// onto [MoneyLineError], shared by the preview renderer and the
  /// detail sheet.
  factory MoneyErrorMessages.of(AppLocalizations l10n) => MoneyErrorMessages(
    missingAmount: l10n.moneyErrorMissingAmount,
    unknownColour: l10n.moneyErrorUnknownColour,
    invalidAmount: l10n.moneyErrorInvalidAmount,
    invalidCount: l10n.moneyErrorInvalidCount,
    divideByZero: l10n.moneyErrorDivideByZero,
    amountTooLarge: l10n.moneyErrorAmountTooLarge,
    tooManyDecimals: l10n.moneyErrorTooManyDecimals,
  );

  String resolve(MoneyLineError e) {
    switch (e) {
      case MoneyLineError.labelFirstMissingAmount:
        return missingAmount;
      case MoneyLineError.unresolvedAccent:
        return unknownColour;
      case MoneyLineError.nonNumericAmount:
        return invalidAmount;
      case MoneyLineError.nonNumericWindowCount:
        return invalidCount;
      case MoneyLineError.divideByZero:
        return divideByZero;
      case MoneyLineError.amountTooLarge:
        return amountTooLarge;
      case MoneyLineError.tooManyDecimals:
        return tooManyDecimals;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyErrorMessages &&
          missingAmount == other.missingAmount &&
          unknownColour == other.unknownColour &&
          invalidAmount == other.invalidAmount &&
          invalidCount == other.invalidCount &&
          divideByZero == other.divideByZero &&
          amountTooLarge == other.amountTooLarge &&
          tooManyDecimals == other.tooManyDecimals;

  @override
  int get hashCode => Object.hash(
    missingAmount,
    unknownColour,
    invalidAmount,
    invalidCount,
    divideByZero,
    amountTooLarge,
    tooManyDecimals,
  );
}

/// The money ledger's resolved display configuration — one value-equal
/// object threaded everywhere the settings used to travel as four loose
/// parameters (enabled flag, start balance, currency symbol/position).
///
/// Passing a single object is the point: the preview's two
/// `prepareWithStyle` call sites and the editor's `configureMoney` used
/// to each receive the fields separately with a documented
/// "must pass identical values" footgun; with one object, half a config
/// is unrepresentable. Value equality doubles as the render-cache key
/// contribution — and because [errorMessages] participates, a locale
/// change invalidates cached renders automatically.
///
/// Display-only by definition: nothing here can change what parses as a
/// money line or what any balance is (that is a pure function of note
/// content — see [MarkdownMoneySyntax]).
class MoneyDisplayConfig {
  final bool enabled;
  final int startCents;
  final String currencySymbol;
  final bool currencySuffix;

  /// Localized error strings, or null for the EN fallback
  /// ([MarkdownMoneySyntax.errorMessage]).
  final MoneyErrorMessages? errorMessages;

  const MoneyDisplayConfig({
    required this.enabled,
    this.startCents = 0,
    this.currencySymbol = '',
    this.currencySuffix = false,
    this.errorMessages,
  });

  static const disabled = MoneyDisplayConfig(enabled: false);

  /// The message for [e]: localized when messages are present, EN
  /// otherwise. Single resolution point for the preview renderer and
  /// the detail sheet.
  String errorText(MoneyLineError e) =>
      errorMessages?.resolve(e) ?? MarkdownMoneySyntax.errorMessage(e);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyDisplayConfig &&
          enabled == other.enabled &&
          startCents == other.startCents &&
          currencySymbol == other.currencySymbol &&
          currencySuffix == other.currencySuffix &&
          errorMessages == other.errorMessages;

  @override
  int get hashCode => Object.hash(
    enabled,
    startCents,
    currencySymbol,
    currencySuffix,
    errorMessages,
  );
}
