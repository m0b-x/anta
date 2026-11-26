part of '../settings_service.dart';

/// The money ledger's config, a note's own currency, and the colour palette
/// markdown colours are picked from.
mixin _MoneyAndColourSettings on _SettingsStore {
  /// The effective money display config for a note: whether the
  /// feature is enabled at all, the global start balance, and the
  /// note's currency override when present (else the global currency).
  /// Resolved once per note load by the editor page.
  Future<({bool enabled, int startCents, String symbol, bool suffix})>
  getMoneyConfig({String? noteId}) async {
    final enabled = await getMoneyLedgerEnabled();
    final startCents = await _getInt(
      SettingsKeys.moneyStartCents,
      SettingsKeys.defaultMoneyStartCents,
    );
    if (noteId != null && noteId.isNotEmpty) {
      final override = await _db.userSettingsDao.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId',
      );
      if (override != null && override.isNotEmpty) {
        final sep = override.lastIndexOf('|');
        if (sep > 0) {
          return (
            enabled: enabled,
            startCents: startCents,
            symbol: override.substring(0, sep),
            suffix: override.substring(sep + 1) == 'true',
          );
        }
        return (
          enabled: enabled,
          startCents: startCents,
          symbol: override,
          suffix: false,
        );
      }
    }
    return (
      enabled: enabled,
      startCents: startCents,
      symbol:
          await _db.userSettingsDao.getValue(
            SettingsKeys.moneyCurrencySymbol,
          ) ??
          SettingsKeys.defaultMoneyCurrencySymbol,
      suffix: await _getBool(
        SettingsKeys.moneyCurrencySuffix,
        SettingsKeys.defaultMoneyCurrencySuffix,
      ),
    );
  }

  Future<bool> getMoneyLedgerEnabled() => _getBool(
    SettingsKeys.moneyLedgerEnabled,
    SettingsKeys.defaultMoneyLedgerEnabled,
  );

  Future<void> setMoneyLedgerEnabled(bool value) =>
      _setBool(SettingsKeys.moneyLedgerEnabled, value);

  Future<void> setMoneyStartCents(int cents) =>
      _setInt(SettingsKeys.moneyStartCents, cents);

  Future<void> setMoneyCurrencySymbol(String symbol) =>
      _db.userSettingsDao.setValue(SettingsKeys.moneyCurrencySymbol, symbol);

  Future<void> setMoneyCurrencySuffix(bool suffix) =>
      _setBool(SettingsKeys.moneyCurrencySuffix, suffix);

  /// The raw per-note currency override (`null` = inherits global).
  Future<({String symbol, bool suffix})?> getNoteMoneyCurrency(
    String noteId,
  ) async {
    final raw = await _db.userSettingsDao.getValue(
      '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId',
    );
    if (raw == null || raw.isEmpty) return null;
    final sep = raw.lastIndexOf('|');
    if (sep > 0) {
      return (
        symbol: raw.substring(0, sep),
        suffix: raw.substring(sep + 1) == 'true',
      );
    }
    return (symbol: raw, suffix: false);
  }

  /// Sets or clears (`null`) the per-note currency override.
  Future<void> setNoteMoneyCurrency(
    String noteId, {
    ({String symbol, bool suffix})? currency,
  }) async {
    final key = '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId';
    // `|` is the encoding separator — strip it from the symbol so a
    // pathological custom symbol can never corrupt the round-trip. A
    // symbol that is empty after sanitizing (e.g. the user typed only
    // `|`) has nothing to override with, so it clears like null (the
    // decoders require the separator at index > 0, so an empty symbol
    // part could never be read back anyway).
    final symbol = currency?.symbol.replaceAll('|', '') ?? '';
    if (currency == null || symbol.isEmpty) {
      await _db.userSettingsDao.deleteValue(key);
    } else {
      await _db.userSettingsDao.setValue(key, '$symbol|${currency.suffix}');
    }
  }

  /// Memoized palette, so repeated note opens skip the decode and the
  /// per-colour contrast resolution. Keyed by the persisted source, and
  /// returning the same instance also lets the render-cache key hit its
  /// `identical` fast path.
  MarkdownColorPalette? _colorPalette;

  /// The effective markdown colour palette: the built-in presets
  /// overlaid with the user's custom colours. Resolved by the editor
  /// page on note open and after returning from settings.
  MarkdownColorPalette _decodeColorPalette(String? raw) {
    final source = raw ?? SettingsKeys.defaultMarkdownCustomColors;
    final cached = _colorPalette;
    if (cached != null && cached.source == source) return cached;
    return _colorPalette = MarkdownColorPalette.decode(source);
  }

  Future<MarkdownColorPalette> getColorPalette() async {
    return _decodeColorPalette(
      await _db.userSettingsDao.getValue(SettingsKeys.markdownCustomColors),
    );
  }

  /// Persists the custom colours (name -> colour). Names must already be
  /// normalized by [MarkdownColorPalette.normalizeName].
  Future<void> setCustomColors(Map<String, Color> colors) async {
    final source = MarkdownColorPalette.encode(colors);
    await _db.userSettingsDao.setValue(
      SettingsKeys.markdownCustomColors,
      source,
    );
    _colorPalette = MarkdownColorPalette.decode(source);
  }
}
