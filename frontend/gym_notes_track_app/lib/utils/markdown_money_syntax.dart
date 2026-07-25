/// Shared definition, scanning, and arithmetic for "money ledger"
/// lines — a line-led syntax for tracking a running sum inside a note:
///
/// ```text
/// $= 100          set the balance (initial sum / period checkpoint)
/// $+ 12.50 label  add an amount
/// $- 8 label      subtract an amount
/// $* 1.19         multiply the balance (e.g. tax)
/// $/ 2            divide the balance (e.g. split)
/// $$ label        show the running total at this point
/// $? label        show the net change since the last `$=` checkpoint
/// $! 500 label    spending target: shows the remaining budget
/// $^ label        show the change caused by the most recent entry
/// $^ 3 label      show the change across the last 3 entries
/// $~ label        show the change since the last `$=` checkpoint
/// $~ 3 label      show the change across the last 3 `$=` checkpoints
/// ```
///
/// `$=` doubles as a period boundary: place one under a month/year
/// heading and a later `$?` reports that period's total +/- change,
/// while `$$` always reports the absolute balance. `$^` compares the
/// current balance to its value N *entries* back — an entry is any
/// `$=`/`$+`/`$-`/`$*`/`$/` line; the display-only rows (`$$` `$?` `$!`
/// `$^` `$~`) never count. N defaults to 1 (the single most recent
/// entry) and clamps to the note's start balance when the history is
/// shorter. The count is a digit run of any length ending at a space or
/// the line end — an over-large count simply clamps, so any leading
/// number is a window (`$^ 2024 spending` means 2024 entries back; put
/// the number after the label to keep it as text). A non-count shape
/// (`3x`, a zero count) stays label text. Unlike `$?` (always "since the last `$=`", however
/// many entries that spans), `$^ N` is a fixed transaction count
/// regardless of any `$=` crossed — so `$^ 3` is "the last 3 lines that
/// touched the balance," not "the last 3 checkpoints."
///
/// `$~ N` is the checkpoint counterpart of `$^ N`: it compares the
/// current balance to its value N `$=` checkpoints back — so `$~ 3` is
/// "the change since the 3rd-most-recent `$=`," spanning however many
/// `$+`/`$-`/`$*`/`$/` lines fall between. N defaults to 1, making `$~`
/// with no count identical to `$?` (since the single last `$=`), and
/// clamps to the **first** `$=` checkpoint when fewer than N checkpoints
/// precede it — so an over-large N (or `ALL`) reports the change since the
/// oldest checkpoint, staying a change *between checkpoints* rather than
/// the absolute balance from the note start. Only a note with no `$=` at
/// all falls back to the start balance. Where `$?` never reaches past the
/// last checkpoint and `$^` never reaches past it *by counting entries*,
/// `$~ N` deliberately reaches across N of them.
///
/// Two optional prefixes compose with every money line:
///
/// ```text
/// ## $$ Net worth     1–6 `#` (space optional): renders header-sized
/// $+ blue: 250 rent   colour name + `:` after the op: the value's
///                     accent takes that colour instead of the
///                     semantic green/red/neutral
/// ```
///
/// Both are matched **by shape only** — the ledger never depends on the
/// colour palette (or any other setting), so what counts as money and
/// every balance is a pure function of note content. A name that does
/// not resolve at render time simply renders literally with the
/// semantic accent; the line still counts.
///
/// Op rows (`$= $+ $- $* $/`) may also be written **label-first**, with
/// the typed amount trailing behind a `:`:
///
/// ```text
/// $= Net worth: 5000                 renders  Net worth = 5000
/// ## $- blue: Loss/Gain/Whatever: 5000
/// $* VAT: 1.19                       renders  VAT × 1.19
/// ```
///
/// The spelling picks the layout: amount-first puts the op glyph in
/// front (`+ 12.50 rent`), label-first renders it **where the `:` is**
/// so the row reads as an equation (`rent + 12.50`). On a label-first
/// row the `:` is chrome, exactly like the `$=` marker it replaces.
///
/// The colon is what makes this unambiguous, and it is required: without
/// it `$- food 2024` would silently subtract 2024. The whole tail after
/// the last `:` must be the amount and nothing else, so
/// `$= Net worth: 5000 as of today` stays plain text rather than guessing
/// which number was meant. Everything before that colon is label, colons
/// included (`$= Assets: cash: 5000` labels "Assets: cash:"). Display
/// rows (`$$ $? $! $^ $~`) are unaffected — `$$`/`$?`/`$^`/`$~` take no
/// amount at all, and `$!`'s target reads naturally amount-first.
///
/// This is the **only** shape where [MoneyLineMatch.labelStart] is below
/// [MoneyLineMatch.amountStart]; renderers compare the two to pick an
/// order and must use [MoneyLineMatch.labelEnd] rather than assuming the
/// label runs to the line end.
///
/// A lone `$` anywhere in the label is the **value slot**: the row's
/// computed value renders there instead of at its default position, so
/// label text can precede the number without the marker leaving the
/// line start:
///
/// ```text
/// $$ Current sum: $          →  Current sum: 600.00 lei
/// ## $$ blue: Net worth: $   →  header-sized, blue, value inline
/// $+ 12.50 groceries, now $  →  + 12.50 groceries, now 462.50 lei
/// $= 600 start of month: $   →  = 600 start of month: 600.00 lei
/// ```
///
/// The slot is shape-matched too: a `$` delimited by spaces or the line
/// end, so `$5`/`US$`/`$$` inside a label stay literal text. The first
/// one wins; later ones render as typed. It composes with every op —
/// including `$=`, whose value is otherwise not shown — and is purely a
/// display concern: the balance fold never sees it. Crucially the slot
/// scan runs only on lines already confirmed to be money lines, so
/// [leadsWithMoney] — the prefix probe every document line pays — is
/// untouched by the feature.
///
/// This is the single source of truth consumed by:
///   * the preview renderer (styled change rows + running balance),
///   * the editor span builder (tinted ops, painted `$$` total),
///   * the editor line index (incremental balance pass), and
///   * the preview builder's ledger pass in `prepare`.
///
/// Keeping one matcher and one arithmetic core here guarantees all
/// surfaces agree on exactly what is a money line and what the balance
/// is at every point of the document.
///
/// The balance is a pure function of note content — nothing is
/// persisted and no counter is mutated, so re-rendering can never
/// double-count. All arithmetic is fixed-point over ints (cents for
/// balances, 1/10000ths for parsed amounts): no floating-point drift.
/// Lines inside code fences are inert (both surfaces skip them), and a
/// leading backslash or any non-matching shape renders as plain text.
library;

/// Kinds of money line. [total], [delta], [target], [diff], and [span]
/// perform no arithmetic — [total] displays the running balance where it
/// appears, [delta] the net change since the last [set] (or the note
/// start), [target] declares a spending goal whose displayed value is
/// the remaining budget (target − spent since the last [set]), [diff]
/// the change across the last N balance-changing *entries*, and [span]
/// the change across the last N `$=` *checkpoints*.
enum MoneyLineKind {
  set,
  add,
  subtract,
  multiply,
  divide,
  total,
  delta,
  target,
  diff,
  span,
}

/// Error states in money line parsing. Lines with errors render but do not
/// count toward the ledger balance, and display a yellow error indicator.
/// [amountTooLarge] and [tooManyDecimals] fire when an otherwise clean
/// amount exceeds the digit limits — deliberately an error rather than a
/// silent fall-through to plain text, so an over-limit `$=` is visibly
/// broken instead of quietly not counting.
enum MoneyLineError {
  labelFirstMissingAmount,
  unresolvedAccent,
  nonNumericAmount,
  nonNumericWindowCount,
  divideByZero,
  amountTooLarge,
  tooManyDecimals,
}

/// A parsed money line. All offsets are relative to the scanned line.
///
/// `[markerStart, markerEnd)` covers the `$` + op character (or `$$`),
/// `[amountStart, amountEnd)` covers the amount digits (empty for
/// [MoneyLineKind.total]), and `[labelStart, line.length)` is the
/// optional trailing label (`labelStart == line.length` when absent).
class MoneyLineMatch {
  final MoneyLineKind kind;

  /// Offset of the first `#` of an optional heading prefix, or -1. The
  /// hashes span `[headerStart, headerStart + headerLevel)`; the row
  /// renders at that heading's scale while the ledger is unaffected.
  final int headerStart;

  /// Heading level 1..6, or 0 when the line has no heading prefix.
  final int headerLevel;

  /// Offset of the leading `$`.
  final int markerStart;

  /// Offset just past the op character (`=`, `+`, `-`, `*`, `/`, `$`).
  final int markerEnd;

  /// `[accentStart, accentEnd)` covers an optional colour-name token
  /// after the op (`$+ blue: 250` → `blue`; the `:` sits at
  /// [accentEnd]), or -1/-1. Matched by shape only — renderers resolve
  /// the name against their palette, and an unresolved name renders
  /// literally with the semantic accent (the line still counts).
  final int accentStart;
  final int accentEnd;

  /// Offset of the first amount digit. For display rows this covers the
  /// optional `$^`/`$~` count digits and is empty (equal to [amountEnd])
  /// for every other valueless row.
  final int amountStart;

  /// Offset just past the last amount code unit.
  final int amountEnd;

  /// Offset of the first label character, or the line length.
  final int labelStart;

  /// Offset just past the last label character. Equals the line length
  /// on every row except a **label-first** op row (`$- Loss: 5000`),
  /// where the label ends at its `:` and the amount trails behind it —
  /// the one shape where [labelStart] is *below* [amountStart]. Compare
  /// the two to know which order to render in; never assume the label
  /// runs to the end of the line.
  final int labelEnd;

  /// The amount in fixed-point 1/10000ths (`12.5` → `125000`). Zero
  /// for totals. Always non-negative — the op carries the sign.
  final int amountFixed;

  /// How far back a windowed display row compares against: for
  /// [MoneyLineKind.diff] a count of balance-changing *entries* (`$^ 3`
  /// → 3; an entry is any `$=`/`$+`/`$-`/`$*`/`$/` line), for
  /// [MoneyLineKind.span] a count of `$=` *checkpoints* (`$~ 3` → 3).
  /// Defaults to 1 — the single most recent entry / checkpoint.
  final int windowCount;

  /// Offset of the label's lone `$` value slot — where this row's
  /// computed value renders instead of its default position — or -1
  /// when the label has none. One code unit wide, so the live editor
  /// substitutes its painted chip 1:1 exactly like the second `$` of a
  /// `$$` marker.
  final int valueSlot;

  /// If non-null, this line has a syntax error and does not count toward
  /// the ledger balance. Renderers show a yellow error indicator instead
  /// of normal rendering.
  final MoneyLineError? error;

  const MoneyLineMatch({
    required this.kind,
    this.headerStart = -1,
    this.headerLevel = 0,
    required this.markerStart,
    required this.markerEnd,
    this.accentStart = -1,
    this.accentEnd = -1,
    required this.amountStart,
    required this.amountEnd,
    required this.labelStart,
    required this.labelEnd,
    required this.amountFixed,
    this.windowCount = 1,
    this.valueSlot = -1,
    this.error,
  });
}

/// One collected money line with its folded running value — the
/// on-demand (tap-time) counterpart of the incremental render passes.
class MoneyLedgerEntry {
  final int lineIndex;

  /// The full source line, so presenters can show the amount and label
  /// exactly as typed without re-fetching the document.
  final String line;
  final MoneyLineMatch match;

  /// Balance after this line; the net change since the last `$=` for
  /// [MoneyLineKind.delta] lines, the move across the row's window for
  /// [MoneyLineKind.diff] (N entries) and [MoneyLineKind.span] (N `$=`
  /// checkpoints) lines.
  final int valueAfter;

  const MoneyLedgerEntry({
    required this.lineIndex,
    required this.line,
    required this.match,
    required this.valueAfter,
  });
}

/// Money ledger syntax + scanning + fixed-point arithmetic helpers.
class MarkdownMoneySyntax {
  MarkdownMoneySyntax._();

  /// Lines longer than this never parse as money lines, mirroring the
  /// editor's raw-render guard so preview and editor ledgers can never
  /// disagree about an oversized line.
  static const int maxLineLength = 4096;

  /// Balances are clamped to ±[balanceLimitCents] (999,999,999,999.99)
  /// after every op. Multiplication and division go through the split
  /// helpers below, whose intermediates stay under 2^53 — the arithmetic
  /// is exact on every platform Flutter targets, including web. A value
  /// pinned at exactly ±this renders with the warning accent so a capped
  /// balance is never mistaken for a real one.
  static const int balanceLimitCents = 99999999999999;

  /// Fixed-point scale of [MoneyLineMatch.amountFixed].
  static const int amountScale = 10000;

  static const int _kDollar = 0x24; // $
  static const int _kEquals = 0x3D; // =
  static const int _kPlus = 0x2B; // +
  static const int _kMinus = 0x2D; // -
  static const int _kStar = 0x2A; // *
  static const int _kSlash = 0x2F; // /
  static const int _kDot = 0x2E; // .
  static const int _kComma = 0x2C; // ,
  static const int _kQuestion = 0x3F; // ?
  static const int _kBang = 0x21; // !
  static const int _kCaret = 0x5E; // ^
  static const int _kTilde = 0x7E; // ~
  static const int _kHash = 0x23; // #
  static const int _kColon = 0x3A; // :

  /// Longest accepted colour-name token, mirroring
  /// `MarkdownColorPalette.maxNameLength` (kept local so this library
  /// stays import-free; the accent grammar is a strict subset of the
  /// colour-name grammar, letter-led to never shadow a numeric amount).
  static const int _maxAccentNameLength = 24;

  /// Set/add/subtract amounts: up to 11 integer digits
  /// (99,999,999,999.99), 2 decimals. Capped below [balanceLimitCents]
  /// so a single amount can never be silently clamped — in particular a
  /// `$=` row's displayed amount is always exactly the balance it sets —
  /// and low enough that [MoneyLineMatch.amountFixed] stays under 2^53.
  /// A digit run past either limit parses as an *error row* (yellow,
  /// does not count), never as silent plain text.
  static const int _maxAmountIntDigits = 11;
  static const int _maxAmountDecimals = 2;

  /// Multiply/divide factors: up to 4 integer digits, 4 decimals.
  static const int _maxFactorIntDigits = 4;
  static const int _maxFactorDecimals = 4;

  /// Whether [line] can possibly be a money line: its first
  /// non-whitespace run is the `$` marker, optionally preceded by a
  /// 1–6 `#` heading prefix + space (cheap pre-check so hot per-line
  /// paths can skip the full parse).
  static bool leadsWithMoney(String line) =>
      leadsWithMoneyInRange(line, 0, line.length);

  /// Range form of [leadsWithMoney] over [source] `[start, end)`, so
  /// whole-document folds can probe without allocating line substrings.
  static bool leadsWithMoneyInRange(String source, int start, int end) {
    var i = start;
    while (i < end && _isSpace(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= end) return false;
    final c = source.codeUnitAt(i);
    if (c == _kDollar) return true;
    if (c != _kHash) return false;
    final h = i;
    while (i < end && source.codeUnitAt(i) == _kHash) {
      i++;
    }
    if (i - h > 6 || i >= end) return false;
    // The space between the hashes and the `$` is optional (`##$$` and
    // `## $$` both lead with money) — unambiguous, since a no-space hash
    // run is not a valid heading and nothing else claims the shape.
    while (i < end && _isSpace(source.codeUnitAt(i))) {
      i++;
    }
    return i < end && source.codeUnitAt(i) == _kDollar;
  }

  /// Parses [line] as a money line, or `null` when it is not one.
  ///
  /// Shape: optional leading spaces/tabs, an optional 1–6 `#` heading
  /// prefix (space before the `$` optional), `$` + op char, an optional
  /// letter-led colour-name token ending in `:` (followed by a space or
  /// the line end), then for ops an amount (`digits` with optional
  /// `.`/`,` decimals) that must end at a space or the line end, then
  /// an optional label. `$$` / `$?` / `$^` take no amount. A malformed
  /// amount rejects the whole line so it renders as plain text; a
  /// *well-formed* amount past the digit limits (and `$/ 0`) instead
  /// parses as an error row — yellow, does not count — so an over-limit
  /// line is visibly broken rather than silently inert.
  static MoneyLineMatch? parse(String line) {
    final n = line.length;
    if (n < 2 || n > maxLineLength) return null;
    var i = 0;
    while (i < n && _isSpace(line.codeUnitAt(i))) {
      i++;
    }
    var headerStart = -1;
    var headerLevel = 0;
    if (i < n && line.codeUnitAt(i) == _kHash) {
      final h = i;
      while (i < n && line.codeUnitAt(i) == _kHash) {
        i++;
      }
      final level = i - h;
      if (level > 6 || i >= n) return null;
      // Space after the hashes is optional (`##$$` = `## $$`): a
      // no-space hash run is not a valid heading, so the `$` that must
      // follow keeps the shape unambiguous. Mirrors
      // [leadsWithMoneyInRange].
      while (i < n && _isSpace(line.codeUnitAt(i))) {
        i++;
      }
      if (i >= n || line.codeUnitAt(i) != _kDollar) return null;
      headerStart = h;
      headerLevel = level;
    }
    if (i >= n || line.codeUnitAt(i) != _kDollar) return null;
    final markerStart = i;
    i++;
    if (i >= n) return null;
    final op = line.codeUnitAt(i);
    final MoneyLineKind kind;
    switch (op) {
      case _kEquals:
        kind = MoneyLineKind.set;
      case _kPlus:
        kind = MoneyLineKind.add;
      case _kMinus:
        kind = MoneyLineKind.subtract;
      case _kStar:
        kind = MoneyLineKind.multiply;
      case _kSlash:
        kind = MoneyLineKind.divide;
      case _kDollar:
        kind = MoneyLineKind.total;
      case _kQuestion:
        kind = MoneyLineKind.delta;
      case _kBang:
        kind = MoneyLineKind.target;
      case _kCaret:
        kind = MoneyLineKind.diff;
      case _kTilde:
        kind = MoneyLineKind.span;
      default:
        return null;
    }
    i++;
    final markerEnd = i;

    final isDisplay =
        kind == MoneyLineKind.total ||
        kind == MoneyLineKind.delta ||
        kind == MoneyLineKind.diff ||
        kind == MoneyLineKind.span;
    if (isDisplay && i < n && !_isSpace(line.codeUnitAt(i))) return null;

    while (i < n && _isSpace(line.codeUnitAt(i))) {
      i++;
    }
    var accentStart = -1;
    var accentEnd = -1;
    final colon = _scanAccentEnd(line, i, n);
    if (colon > 0) {
      accentStart = i;
      accentEnd = colon;
      i = colon + 1;
      while (i < n && _isSpace(line.codeUnitAt(i))) {
        i++;
      }
    }

    if (isDisplay) {
      // `$^`/`$~` take an optional window count: a digit run of any
      // length or `ALL` ending at a space or the line end (`$^` counts
      // entries, `$~` counts `$=` checkpoints; `ALL` means all
      // entries/checkpoints since this period/note start). An over-large
      // count clamps to the oldest entry/checkpoint in the fold, so any
      // leading number is a valid window. Only a non-count shape (`3x`,
      // and a zero count — a window of 0 measures nothing) stays label
      // text; [MoneyLineMatch.windowCount] is always ≥ 1 (or -1 for ALL).
      final amountStart = i;
      var amountEnd = i;
      var windowCount = 1;
      final bool takesCount =
          kind == MoneyLineKind.diff || kind == MoneyLineKind.span;
      if (takesCount && i < n) {
        // Check for "ALL" keyword
        if (i + 3 <= n &&
            line.codeUnitAt(i) == 0x41 && // A
            line.codeUnitAt(i + 1) == 0x4C && // L
            line.codeUnitAt(i + 2) == 0x4C && // L
            (i + 3 >= n || _isSpace(line.codeUnitAt(i + 3)))) {
          amountEnd = i + 3;
          windowCount = -1; // Sentinel: all entries/checkpoints
          i = i + 3;
          while (i < n && _isSpace(line.codeUnitAt(i))) {
            i++;
          }
        } else if (_isDigit(line.codeUnitAt(i))) {
          // Numeric window count. Accumulation saturates at 10^9 so an
          // absurd digit run can't overflow — a saturated count already
          // clamps to the oldest entry/checkpoint anyway.
          var j = i;
          var v = 0;
          while (j < n && _isDigit(line.codeUnitAt(j))) {
            if (v < 1000000000) {
              v = v * 10 + (line.codeUnitAt(j) - 0x30);
            }
            j++;
          }
          if (v > 0 && (j >= n || _isSpace(line.codeUnitAt(j)))) {
            amountEnd = j;
            windowCount = v;
            i = j;
            while (i < n && _isSpace(line.codeUnitAt(i))) {
              i++;
            }
          }
        }
      }
      // A count-taking display row (`$^`/`$~`) may place its accent token
      // *after* the count (`$~ 2 teal:`) instead of before it
      // (`$~ teal: 2`) — the more natural spelling, since the count belongs
      // to the operator and the colour to the whole row. Scan for one here
      // when the pre-count scan found none, so both orders resolve to the
      // same match (accent offsets then sit above the count, the one shape
      // where [accentStart] is past [amountEnd]).
      if (takesCount && accentStart < 0) {
        final colon2 = _scanAccentEnd(line, i, n);
        if (colon2 > 0) {
          accentStart = i;
          accentEnd = colon2;
          i = colon2 + 1;
          while (i < n && _isSpace(line.codeUnitAt(i))) {
            i++;
          }
        }
      }
      return MoneyLineMatch(
        kind: kind,
        headerStart: headerStart,
        headerLevel: headerLevel,
        markerStart: markerStart,
        markerEnd: markerEnd,
        accentStart: accentStart,
        accentEnd: accentEnd,
        amountStart: amountStart,
        amountEnd: amountEnd,
        labelStart: i,
        labelEnd: n,
        amountFixed: 0,
        windowCount: windowCount,
        valueSlot: _scanValueSlot(line, i, n),
      );
    }

    final bool isFactor =
        kind == MoneyLineKind.multiply || kind == MoneyLineKind.divide;
    final maxInt = isFactor ? _maxFactorIntDigits : _maxAmountIntDigits;
    final maxDec = isFactor ? _maxFactorDecimals : _maxAmountDecimals;

    final int amountStart;
    final int amountEnd;
    final int amountFixed;
    final int labelStart;
    final int labelEnd;

    // Amount-first (`$+ 12.50 rent`): the classic shape, and the only
    // one that allows a label with no separator rules at all.
    final head = _parseAmount(line, i, n, maxInt, maxDec);
    if (head != null && (head.end >= n || _isSpace(line.codeUnitAt(head.end)))) {
      var j = head.end;
      while (j < n && _isSpace(line.codeUnitAt(j))) {
        j++;
      }
      if (head.error != null) {
        // A clean amount shape past the digit limits: an error row, so
        // the over-limit line is visibly broken instead of silently
        // rendering plain and not counting.
        return MoneyLineMatch(
          kind: kind,
          headerStart: headerStart,
          headerLevel: headerLevel,
          markerStart: markerStart,
          markerEnd: markerEnd,
          accentStart: accentStart,
          accentEnd: accentEnd,
          amountStart: i,
          amountEnd: head.end,
          labelStart: j,
          labelEnd: n,
          amountFixed: 0,
          error: head.error,
        );
      }
      amountStart = i;
      amountEnd = head.end;
      amountFixed = head.fixed;
      labelStart = j;
      labelEnd = n;
    } else {
      // Label-first (`$- Loss on trade: 5000`): the amount trails at the
      // line end behind a `:`. Requiring the colon is what keeps this
      // unambiguous — without it `$- food 2024` would silently subtract
      // 2024 — and it costs nothing, since a label ending in `:` is how
      // you would write the line anyway.
      final tail = _scanTrailingAmount(line, i, n, maxInt, maxDec);
      if (tail == null) {
        // Check if the label ends with a colon (syntax error: missing amount)
        var trimEnd = n;
        while (trimEnd > i && _isSpace(line.codeUnitAt(trimEnd - 1))) {
          trimEnd--;
        }
        if (trimEnd > i && line.codeUnitAt(trimEnd - 1) == _kColon) {
          // Label-first shape detected (ends with `:`) but no trailing amount
          return MoneyLineMatch(
            kind: kind,
            headerStart: headerStart,
            headerLevel: headerLevel,
            markerStart: markerStart,
            markerEnd: markerEnd,
            accentStart: accentStart,
            accentEnd: accentEnd,
            amountStart: i,
            amountEnd: i,
            labelStart: i,
            labelEnd: trimEnd,
            amountFixed: 0,
            error: MoneyLineError.labelFirstMissingAmount,
          );
        }
        return null;
      }
      if (tail.error != null) {
        // Same over-limit rule as the amount-first shape: a clean
        // trailing amount past the digit limits is an error row.
        return MoneyLineMatch(
          kind: kind,
          headerStart: headerStart,
          headerLevel: headerLevel,
          markerStart: markerStart,
          markerEnd: markerEnd,
          accentStart: accentStart,
          accentEnd: accentEnd,
          amountStart: tail.amountStart,
          amountEnd: tail.amountEnd,
          labelStart: i,
          labelEnd: tail.labelEnd,
          amountFixed: 0,
          error: tail.error,
        );
      }
      amountStart = tail.amountStart;
      amountEnd = tail.amountEnd;
      amountFixed = tail.fixed;
      labelStart = i;
      labelEnd = tail.labelEnd;
    }

    return MoneyLineMatch(
      kind: kind,
      headerStart: headerStart,
      headerLevel: headerLevel,
      markerStart: markerStart,
      markerEnd: markerEnd,
      accentStart: accentStart,
      accentEnd: accentEnd,
      amountStart: amountStart,
      amountEnd: amountEnd,
      labelStart: labelStart,
      labelEnd: labelEnd,
      amountFixed: amountFixed,
      valueSlot: _scanValueSlot(line, labelStart, labelEnd),
      // `$/ 0` is an error row (yellow, does not count) rather than
      // silent plain text — the enum and sheet always promised this
      // message; parse used to bail to `null` instead of emitting it.
      error: kind == MoneyLineKind.divide && amountFixed == 0
          ? MoneyLineError.divideByZero
          : null,
    );
  }

  /// Parses an amount at [start]: up to [maxInt] integer digits and an
  /// optional `.`/`,` fraction of up to [maxDec] digits. Returns the
  /// offset just past it plus its fixed-point value, or `null` when the
  /// run is not an amount shape at all. A run that *is* an amount shape
  /// but exceeds a limit still consumes to its end and comes back with
  /// [MoneyLineError.amountTooLarge] / [MoneyLineError.tooManyDecimals]
  /// set (and `fixed` 0) — callers turn that into an error row rather
  /// than silent plain text. Accumulation stops at the limit, so an
  /// over-long run can never overflow. Callers decide what must follow.
  static ({int end, int fixed, MoneyLineError? error})? _parseAmount(
    String line,
    int start,
    int n,
    int maxInt,
    int maxDec,
  ) {
    var i = start;
    var intPart = 0;
    var intDigits = 0;
    while (i < n && _isDigit(line.codeUnitAt(i))) {
      if (intDigits < maxInt) {
        intPart = intPart * 10 + (line.codeUnitAt(i) - 0x30);
      }
      i++;
      intDigits++;
    }
    if (intDigits == 0) return null;
    MoneyLineError? error;
    if (intDigits > maxInt) error = MoneyLineError.amountTooLarge;

    var decPart = 0;
    var decDigits = 0;
    if (i < n &&
        (line.codeUnitAt(i) == _kDot || line.codeUnitAt(i) == _kComma)) {
      var j = i + 1;
      while (j < n && _isDigit(line.codeUnitAt(j))) {
        if (decDigits < maxDec) {
          decPart = decPart * 10 + (line.codeUnitAt(j) - 0x30);
        }
        j++;
        decDigits++;
      }
      if (decDigits == 0) return null;
      i = j;
      if (decDigits > maxDec) error ??= MoneyLineError.tooManyDecimals;
    }
    if (error != null) return (end: i, fixed: 0, error: error);
    var scale = amountScale;
    for (var d = 0; d < decDigits; d++) {
      scale ~/= 10;
    }
    return (end: i, fixed: intPart * amountScale + decPart * scale, error: null);
  }

  /// Scans a label-first op row's trailing amount: `label: 5000` ending
  /// at the line end (trailing spaces allowed). Returns the label's end
  /// (just past the `:`), the amount's bounds, and its value — or `null`
  /// when the tail is not a lone well-formed amount behind a colon.
  ///
  /// The whole tail after the last `:` must be the amount and nothing
  /// else, so `$= Net worth: 5000 as of today` stays plain text rather
  /// than guessing which number was meant.
  static ({
    int labelEnd,
    int amountStart,
    int amountEnd,
    int fixed,
    MoneyLineError? error,
  })?
  _scanTrailingAmount(String line, int from, int n, int maxInt, int maxDec) {
    var end = n;
    while (end > from && _isSpace(line.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= from) return null;
    var s = end;
    while (s > from) {
      final c = line.codeUnitAt(s - 1);
      if (!_isDigit(c) && c != _kDot && c != _kComma) break;
      s--;
    }
    if (s >= end) return null;
    final parsed = _parseAmount(line, s, end, maxInt, maxDec);
    if (parsed == null || parsed.end != end) return null;
    var c = s;
    while (c > from && _isSpace(line.codeUnitAt(c - 1))) {
      c--;
    }
    if (c <= from || line.codeUnitAt(c - 1) != _kColon) return null;
    return (
      labelEnd: c,
      amountStart: s,
      amountEnd: end,
      fixed: parsed.fixed,
      error: parsed.error,
    );
  }

  /// Scans the label region `[from, n)` for the value slot: a lone `$`
  /// preceded by the label start or a space and followed by a space or
  /// the line end. Returns its index, or -1 when the label has none.
  ///
  /// The delimiter rule is what keeps ordinary label text intact —
  /// `$5`, `US$`, and `$$` never match, so only a deliberate bare `$`
  /// moves the value. Runs only on lines the full [parse] has already
  /// accepted, never from [leadsWithMoney], so non-money lines pay
  /// nothing for the feature.
  static int _scanValueSlot(String line, int from, int n) {
    for (var i = from; i < n; i++) {
      if (line.codeUnitAt(i) != _kDollar) continue;
      if (i > from && !_isSpace(line.codeUnitAt(i - 1))) continue;
      if (i + 1 < n && !_isSpace(line.codeUnitAt(i + 1))) continue;
      return i;
    }
    return -1;
  }

  /// Scans an accent colour-name token at [start]: a letter-led run of
  /// `[a-z0-9_-]` (≤ [_maxAccentNameLength]) ending in `:`, with a
  /// space or the line end after the `:`. Returns the `:` index, or -1.
  /// The letter-led rule keeps amounts unambiguous (`$+ 250: x` can
  /// never read as an accent) and the trailing-space rule keeps label
  /// text like `http://…` intact on display rows.
  static int _scanAccentEnd(String line, int start, int n) {
    if (start >= n) return -1;
    final c0 = line.codeUnitAt(start);
    if (c0 < 0x61 || c0 > 0x7A) return -1;
    var i = start;
    final max = start + _maxAccentNameLength;
    final stop = n < max ? n : max;
    while (i < stop && _isAccentNameChar(line.codeUnitAt(i))) {
      i++;
    }
    if (i >= n || line.codeUnitAt(i) != _kColon) return -1;
    final after = i + 1;
    if (after < n && !_isSpace(line.codeUnitAt(after))) return -1;
    return i;
  }

  static bool _isAccentNameChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x5F || // _
      c == 0x2D; // -

  /// Returns true if [m] has a syntax error. Error lines render but do
  /// not mutate the ledger balance.
  static bool hasError(MoneyLineMatch m) => m.error != null;

  /// Short description of [e], shared by the preview, the live editor,
  /// and the detail sheet so every surface names an error identically.
  /// Hardcoded EN like the money toolbar shortcut labels.
  static String errorMessage(MoneyLineError e) {
    switch (e) {
      case MoneyLineError.labelFirstMissingAmount:
        return 'missing amount after ":"';
      case MoneyLineError.unresolvedAccent:
        return 'unknown colour name';
      case MoneyLineError.nonNumericAmount:
        return 'invalid amount';
      case MoneyLineError.nonNumericWindowCount:
        return 'invalid count';
      case MoneyLineError.divideByZero:
        return 'divide by zero';
      case MoneyLineError.amountTooLarge:
        return 'amount too large (max 99,999,999,999.99)';
      case MoneyLineError.tooManyDecimals:
        return 'too many decimals';
    }
  }

  /// Whether [cents] sits exactly at the clamp limit — i.e. the
  /// computed value is the cap, not real arithmetic. Renderers show
  /// pinned values in the warning accent so a capped balance is never
  /// mistaken for a genuine one.
  static bool valuePinned(int cents) =>
      cents == balanceLimitCents || cents == -balanceLimitCents;

  /// Applies [m] to a running [balanceCents] and returns the new
  /// balance in cents, clamped to ±[balanceLimitCents]. Totals return
  /// the balance unchanged. Error lines return unchanged. Multiplication/division
  /// round half away from zero to the nearest cent.
  static int apply(int balanceCents, MoneyLineMatch m) {
    if (hasError(m)) return balanceCents;
    switch (m.kind) {
      case MoneyLineKind.set:
        return _clamp(m.amountFixed ~/ 100);
      case MoneyLineKind.add:
        return _clamp(balanceCents + m.amountFixed ~/ 100);
      case MoneyLineKind.subtract:
        return _clamp(balanceCents - m.amountFixed ~/ 100);
      case MoneyLineKind.multiply:
        return _clamp(_mulScaled(balanceCents, m.amountFixed));
      case MoneyLineKind.divide:
        return _clamp(_divScaled(balanceCents, m.amountFixed));
      case MoneyLineKind.total:
      case MoneyLineKind.delta:
      case MoneyLineKind.target:
      case MoneyLineKind.diff:
      case MoneyLineKind.span:
        return balanceCents;
    }
  }

  /// Whether [kind] is a balance-changing ledger entry (`$= $+ $- $* $/`)
  /// as opposed to a display-only row (`$$ $? $! $^ $~`). The entry kinds
  /// are exactly the ones that append to the [history] passed to
  /// [displayValue], so the `$^ N` window counts transactions, not
  /// display rows.
  static bool isEntryKind(MoneyLineKind kind) {
    switch (kind) {
      case MoneyLineKind.set:
      case MoneyLineKind.add:
      case MoneyLineKind.subtract:
      case MoneyLineKind.multiply:
      case MoneyLineKind.divide:
        return true;
      case MoneyLineKind.total:
      case MoneyLineKind.delta:
      case MoneyLineKind.target:
      case MoneyLineKind.diff:
      case MoneyLineKind.span:
        return false;
    }
  }

  /// The display value a money line's stored entry carries: the running
  /// balance, except `$?` (net change since the last `$=`), `$!` (the
  /// remaining budget: target − spent since it), `$^ N` (the change over
  /// the last N balance-changing entries), and `$~ N` (the change over
  /// the last N `$=` checkpoints).
  ///
  /// [history] is the append-only entry-balance history: index 0 is the
  /// note's start balance, and every balance-changing entry (`$=`,
  /// `$+`, `$-`, `$*`, `$/`) appends its resulting balance — display
  /// rows never append. [periodStart] is the index in [history] of the
  /// current period's start (the last `$=`, or 0 before any `$=`). A
  /// `$=` marks a hard reset for `$?`/`$^`, so their window can never
  /// reach across it: `$^ N` clamps its reference to [periodStart], and
  /// once N spans the whole period `$^` equals `$?`.
  ///
  /// [anchors] is the parallel append-only *checkpoint*-balance history:
  /// index 0 is the note's start balance and every `$=` appends its
  /// resulting balance. `$~ N` counts back N entries in it — deliberately
  /// reaching across checkpoints, floored at the first checkpoint (index 1,
  /// or index 0 only when the note has no `$=`) — so `$~ 1` equals `$?`
  /// while `$~ 3` spans the last three `$=` periods and any larger N
  /// reports the change since the oldest checkpoint.
  ///
  /// Single source of truth for the editor index pass, the preview
  /// ledger fold, and [collectEntries], so the three can never disagree.
  static int displayValue(
    MoneyLineMatch m,
    int balance,
    List<int> history,
    int periodStart,
    List<int> anchors,
  ) {
    switch (m.kind) {
      case MoneyLineKind.delta:
        return balance - history[periodStart];
      case MoneyLineKind.target:
        return m.amountFixed ~/ 100 + balance - history[periodStart];
      case MoneyLineKind.diff:
        final count = m.windowCount < 0 ? history.length : m.windowCount;
        final back = history.length - 1 - count;
        final ref = back < periodStart ? periodStart : back;
        return balance - history[ref];
      case MoneyLineKind.span:
        final count = m.windowCount < 0 ? anchors.length : m.windowCount;
        final back = anchors.length - count;
        // Floor at the first `$=` checkpoint (index 1) rather than the
        // note start (index 0), so a `$~ N` reaching past the oldest
        // checkpoint still reports a change *between checkpoints* — never
        // the absolute balance measured from a synthetic zero start. Falls
        // back to the note start only when the note has no `$=` at all.
        final floor = anchors.length > 1 ? 1 : 0;
        final ref = back < floor ? floor : back;
        return balance - anchors[ref];
      default:
        return balance;
    }
  }

  /// Formats [cents] as a plain decimal with exactly two decimals and a
  /// leading `-` when negative (`-1250` → `-12.50`). Content-level like
  /// the syntax itself, so no locale formatting is applied.
  static String formatCents(int cents) {
    final sign = cents < 0 ? '-' : '';
    final a = cents.abs();
    final units = a ~/ 100;
    final f = a % 100;
    return '$sign$units.${f < 10 ? '0$f' : '$f'}';
  }

  /// Formats [cents] like [formatCents] but with an explicit sign:
  /// `+12.50`, `-8.00`, `±0.00`. Used by `$?` net-change rows.
  static String formatCentsSigned(int cents) {
    if (cents == 0) return '±0.00';
    return cents > 0 ? '+${formatCents(cents)}' : formatCents(cents);
  }

  /// [formatCents] with a currency symbol: prefix symbols attach to the
  /// number after the sign (`-lei12.50` never happens — `-` first, then
  /// symbol), suffix symbols follow with a space (`12.50 lei`). An
  /// empty [symbol] falls back to the plain form.
  static String formatCentsWithSymbol(
    int cents, {
    required String symbol,
    required bool suffix,
  }) {
    final plain = formatCents(cents);
    if (symbol.isEmpty) return plain;
    if (suffix) return '$plain $symbol';
    return cents < 0 ? '-$symbol${plain.substring(1)}' : '$symbol$plain';
  }

  /// [formatCentsSigned] with a currency symbol; the sign char stays
  /// first (`+€12.50`, `-€8.00`, `±€0.00`), suffix symbols follow with
  /// a space (`+12.50 lei`).
  static String formatCentsSignedWithSymbol(
    int cents, {
    required String symbol,
    required bool suffix,
  }) {
    final plain = formatCentsSigned(cents);
    if (symbol.isEmpty) return plain;
    if (suffix) return '$plain $symbol';
    return '${plain.substring(0, 1)}$symbol${plain.substring(1)}';
  }

  /// Collects every money line from line 0 through [toLine] (inclusive;
  /// -1 = whole document), folding the ledger exactly like the render
  /// passes: [startCents] seeds the balance and the entry history,
  /// [isInert] excludes fence/block lines (each surface passes its own
  /// predicate so the collector always agrees with what is rendered).
  /// `valueAfter` is the running balance after the line (the net change
  /// since the last `$=` for delta lines, the move across the row's
  /// window for diff and span lines). `entryLines` lists the line index
  /// of every balance-changing entry in document order (parallel to the
  /// append-only history from index 1), so a caller can resolve any
  /// `$^ N` window to its source lines; `anchorLines` lists just the
  /// `$=` line indices, which resolve a `$~ N` window the same way.
  /// Runs on tap (rare, user-initiated), so the O(document) scan is fine
  /// — this is deliberately not part of the incremental passes.
  static ({
    List<MoneyLedgerEntry> entries,
    List<int> entryLines,
    List<int> anchorLines,
  })
  collectEntries({
    required int lineCount,
    required String Function(int) lineAt,
    required bool Function(int) isInert,
    int toLine = -1,
    int startCents = 0,
  }) {
    final last = toLine < 0 ? lineCount - 1 : toLine;
    final entries = <MoneyLedgerEntry>[];
    final history = <int>[startCents];
    final anchors = <int>[startCents];
    final entryLines = <int>[];
    final anchorLines = <int>[];
    var periodStart = 0;
    var balance = startCents;
    for (var i = 0; i <= last && i < lineCount; i++) {
      final line = lineAt(i);
      if (line.isEmpty || !leadsWithMoney(line) || isInert(i)) continue;
      final m = parse(line);
      if (m == null) continue;
      // Error lines don't mutate the balance, but still appear in entries.
      if (!hasError(m)) {
        balance = apply(balance, m);
        if (isEntryKind(m.kind)) {
          history.add(balance);
          entryLines.add(i);
          if (m.kind == MoneyLineKind.set) {
            periodStart = history.length - 1;
            anchors.add(balance);
            anchorLines.add(i);
          }
        }
      }
      entries.add(
        MoneyLedgerEntry(
          lineIndex: i,
          line: line,
          match: m,
          valueAfter: displayValue(m, balance, history, periodStart, anchors),
        ),
      );
    }
    return (
      entries: entries,
      entryLines: entryLines,
      anchorLines: anchorLines,
    );
  }

  static int _clamp(int cents) => cents < -balanceLimitCents
      ? -balanceLimitCents
      : cents > balanceLimitCents
      ? balanceLimitCents
      : cents;

  /// `balance × factor` where [f] is the factor in fixed-point
  /// 1/[amountScale]ths, rounding half away from zero to the cent.
  /// Split so no intermediate exceeds ~[balanceLimitCents]: the naive
  /// `balance * f` product overflows 2^53 (web) and can overflow 2^63
  /// with the raised balance limit. Splitting the balance at the scale
  /// keeps every term exact: `(hi·S + lo)·f/S = hi·f + lo·f/S`, where
  /// the first term is a plain integer product bounded by the early
  /// clamp check and the second stays under S·f.
  static int _mulScaled(int balanceCents, int f) {
    if (balanceCents == 0 || f == 0) return 0;
    final neg = balanceCents < 0;
    final a = neg ? -balanceCents : balanceCents;
    final hi = a ~/ amountScale;
    final lo = a % amountScale;
    if (hi > balanceLimitCents ~/ f) {
      return neg ? -balanceLimitCents : balanceLimitCents;
    }
    final r = hi * f + _roundedDiv(lo * f, amountScale);
    return neg ? -r : r;
  }

  /// `balance ÷ factor` with [f] as in [_mulScaled] (never 0 — the
  /// parser turns `$/ 0` into an error row), i.e. `balance·S/f`,
  /// rounding half away from zero. Same splitting rationale:
  /// `(q·f + rem)·S/f = q·S + rem·S/f`, early-clamped so `q·S` can
  /// never overflow even when dividing by a factor below 1.
  static int _divScaled(int balanceCents, int f) {
    if (balanceCents == 0) return 0;
    final neg = balanceCents < 0;
    final a = neg ? -balanceCents : balanceCents;
    final q = a ~/ f;
    if (q > balanceLimitCents ~/ amountScale) {
      return neg ? -balanceLimitCents : balanceLimitCents;
    }
    final r = q * amountScale + _roundedDiv(a % f * amountScale, f);
    return neg ? -r : r;
  }

  static int _roundedDiv(int a, int b) {
    final r = (a.abs() + (b >> 1)) ~/ b;
    return a < 0 ? -r : r;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}
