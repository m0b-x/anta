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
/// $! 500 label    declare a spending target (budget)
/// $! label        show the remaining budget vs the active target
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
/// `$!` splits on the presence of an amount. With one it *declares* a
/// spending target — a pure statement whose displayed value is the
/// target itself — and remembers the balance at that point as the
/// budget's baseline. Without one it is the *status* row ([remaining]):
/// its value is `target − spent since the declaration` (equivalently
/// `target + balance − baseline`), rendered green while ≥ 0 and red
/// once overspent. The baseline survives `$=` checkpoints on purpose:
/// updating the balance with `$= 450` counts as spending against the
/// budget, so a ledger kept entirely with `$=` set-rows still measures
/// its targets. A later `$!` declaration replaces the active target and
/// re-anchors the baseline; a status row with no declaration above it
/// has nothing to measure and renders a "no target" chip
/// ([noTargetSentinel]) instead of a number. The status shape needs a
/// space (or line end) after `$!`, so `$!important` stays plain text.
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

/// Kinds of money line. [total], [delta], [target], [remaining],
/// [diff], and [span] perform no arithmetic — [total] displays the
/// running balance where it appears, [delta] the net change since the
/// last [set] (or the note start), [target] declares a spending goal
/// (`$!` with an amount; its displayed value is the target itself, and
/// the fold remembers the balance at the declaration as the budget's
/// baseline), [remaining] is the target's status row (`$!` with no
/// amount; displays `target − spent since the declaration`, the
/// [noTargetSentinel] when no declaration precedes it), [diff] the
/// change across the last N balance-changing *entries*, and [span] the
/// change across the last N `$=` *checkpoints*.
enum MoneyLineKind {
  set,
  add,
  subtract,
  multiply,
  divide,
  total,
  delta,
  target,
  remaining,
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

  /// `[listMarkerStart, listMarkerEnd)` covers an optional list-marker
  /// prefix before the `$` — a bullet (`- $= 500`, markers `-`/`*`/`+`/
  /// `•`) or an ordered marker incl. its delimiter (`1. $+ 50`) — or
  /// -1/-1. Shape-only like the heading prefix: the row renders as a
  /// list item (indent + glyph + hanging wrap) while the ledger is
  /// unaffected. Leading indent runs `[0, listMarkerStart)`; nesting
  /// level comes from `MarkdownListSyntax.indentLevel`. Mutually
  /// exclusive with the heading prefix — after a list marker only `$`
  /// is accepted — and task items (`- [ ]`) never parse as money, so
  /// checkbox lines keep their checkbox behaviour.
  final int listMarkerStart;
  final int listMarkerEnd;

  /// An optional emphasis wrapper around the whole row —
  /// `*$~ 2 Change: $ *`, `**$$ Total: $**` — recorded as the opening
  /// run `[emphasisStart, emphasisStart + emphasisLen)` (uniform `*` or
  /// `_`, 1–3 chars, tight against the `$`) and the matching closing
  /// run starting at [emphasisCloseStart] (same char, same length, at
  /// the line end after optional trailing spaces). -1/0/-1 when absent.
  /// Shape-only chrome like the other prefixes: the ledger is
  /// unaffected, renderers style the row italic/bold and conceal the
  /// runs. The row's content ends at [emphasisCloseStart] — every
  /// in-row offset (label, amount, slot) already respects it. An
  /// opening run without its matching closer rejects the whole line
  /// (visibly raw, never a half-styled guess).
  final int emphasisStart;
  final int emphasisLen;
  final int emphasisCloseStart;

  /// `*`/`_` (1 marker char) and `***` (3) render italic.
  bool get emphasisItalic => emphasisLen == 1 || emphasisLen == 3;

  /// `**`/`__` (2 marker chars) and `***` (3) render bold.
  bool get emphasisBold => emphasisLen >= 2;

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
  /// runs to the end of the line. A label-first row may also carry free
  /// trailing text in `[amountEnd, line.length)` (`$= Worth: 500 lei so
  /// far`), covered by no offset pair here — renderers emit it like a
  /// second label region.
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
    this.listMarkerStart = -1,
    this.listMarkerEnd = -1,
    this.emphasisStart = -1,
    this.emphasisLen = 0,
    this.emphasisCloseStart = -1,
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

/// The per-row rendering decisions every surface shares, derived once
/// from a [MoneyLineMatch] plus the note's currency symbol — so the
/// preview, the live editor, and the detail sheet can never disagree
/// about a row's *shape*. Pure data: each surface keeps its own
/// emission (paint, conceal, offset mapping) but reads the same facts.
/// This is the render-side counterpart of [MoneyFold] — that class
/// stopped the folds drifting apart, this one stops the decision trees.
///
/// The currency-skipping offsets ([labelFrom], [trailingFrom]) encode
/// the *preview/sheet* reading, where the currency word is chrome; the
/// editor renders source-faithfully and deliberately keeps reading its
/// raw `m` offsets for label text, consuming only the shape flags and
/// [slot] from here.
class MoneyRowLayout {
  /// `$$` / `$?` / `$^` / `$~` — the row features its value as a pill.
  final bool isDisplay;

  /// The amount trails its label (`$= Worth: 500`), so the op glyph
  /// renders at the `:` and free trailing text may follow the amount.
  final bool labelFirst;

  /// A count-taking display row carries its accent token *after* the
  /// count (`$~ 2 teal:`) — the token then sits between the count and
  /// the label instead of in the marker gap.
  final bool accentAfterCount;

  /// The effective value slot ([MarkdownMoneySyntax.effectiveValueSlot]
  /// — currency-voided), or -1.
  final int slot;

  /// End of the inline currency word, or -1
  /// ([MarkdownMoneySyntax.inlineCurrencyEnd]).
  final int currencyEnd;

  /// Currency-skipped label start
  /// ([MarkdownMoneySyntax.labelStartAfterCurrency]).
  final int labelFrom;

  /// Label end with the label-first colon trimmed off.
  final int labelTo;

  /// First char of a label-first row's free trailing text with the
  /// currency word skipped, or -1 on every other shape.
  final int trailingFrom;

  /// End of the row's content: the emphasis closer when the row is
  /// wrapped (`*$~ 2 x*`), else the line length. Renderers bound every
  /// free-running emission with this, never `line.length`, so the
  /// closing run stays chrome.
  final int contentEnd;

  const MoneyRowLayout._({
    required this.isDisplay,
    required this.labelFirst,
    required this.accentAfterCount,
    required this.slot,
    required this.currencyEnd,
    required this.labelFrom,
    required this.labelTo,
    required this.trailingFrom,
    required this.contentEnd,
  });

  factory MoneyRowLayout.of(String line, MoneyLineMatch m, String symbol) {
    final labelFirst = m.labelStart < m.amountStart;
    final currencyEnd = MarkdownMoneySyntax.inlineCurrencyEnd(line, m, symbol);
    return MoneyRowLayout._(
      isDisplay: MarkdownMoneySyntax.isDisplayKind(m.kind),
      labelFirst: labelFirst,
      accentAfterCount:
          m.accentStart >= 0 &&
          m.amountEnd > m.amountStart &&
          m.accentStart >= m.amountEnd,
      slot: MarkdownMoneySyntax.effectiveValueSlot(line, m, symbol),
      currencyEnd: currencyEnd,
      labelFrom: MarkdownMoneySyntax.labelStartAfterCurrency(line, m, symbol),
      labelTo: labelFirst ? m.labelEnd - 1 : m.labelEnd,
      trailingFrom: labelFirst
          ? (currencyEnd >= 0 ? currencyEnd : m.amountEnd)
          : -1,
      contentEnd: m.emphasisCloseStart >= 0
          ? m.emphasisCloseStart
          : line.length,
    );
  }
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

/// Everything one whole-document ledger scan produces: each money row
/// with its folded value, plus the line indices of every counted entry,
/// of every `$=` checkpoint, and of every `$!` target declaration (all
/// in document order — the window resolvers below count back through
/// them).
typedef MoneyLedgerCollection = ({
  List<MoneyLedgerEntry> entries,
  List<int> entryLines,
  List<int> anchorLines,
  List<int> targetLines,
});

/// Mutable accumulator for one ledger fold — the single home for how a
/// money line mutates the running state (balance, append-only entry
/// history, append-only checkpoint history, period start). Every fold
/// in the app steps through this: the preview's `_computeMoneyLedger`,
/// the editor index's incremental `_scanMoney`,
/// [MarkdownMoneySyntax.collectEntries], and the calendar's
/// `NoteMoneyLedgerService`. Fold rules living in one place is the
/// point — error-inertness (`hasError` lines touch nothing, *including*
/// the history appends) was once re-implemented per fold and two of the
/// copies missed it.
class MoneyFold {
  int balance;

  /// Append-only entry-balance history: index 0 is the start balance,
  /// one value per counted entry. Adopted by reference in
  /// [MoneyFold.resume], so incremental passes keep truncate-and-append
  /// semantics over their own persistent lists.
  final List<int> history;

  /// Parallel append-only checkpoint-balance history: index 0 is the
  /// start balance, one value per counted `$=`.
  final List<int> anchors;

  /// Index in [history] of the current period's start (the last `$=`,
  /// or 0 before any).
  int periodStart;

  /// The active spending target in cents (the last `$!` declaration),
  /// or null while none has been declared. Targets are note-scoped
  /// scalars, not histories: a new declaration simply replaces the
  /// active one.
  int? targetCents;

  /// The balance at the moment the active target was declared — the
  /// budget's baseline. Deliberately *not* reset by `$=`: a checkpoint
  /// that lowers the balance is spending against the budget, so a
  /// ledger kept entirely with `$=` set-rows still measures its target.
  int targetAnchor;

  MoneyFold(int startCents)
    : balance = startCents,
      history = <int>[startCents],
      anchors = <int>[startCents],
      periodStart = 0,
      targetCents = null,
      targetAnchor = startCents;

  /// Resumes mid-document from persisted state: [history] and [anchors]
  /// are adopted by reference (already truncated to the resume point by
  /// the caller) and mutated in place.
  MoneyFold.resume({
    required this.balance,
    required this.history,
    required this.anchors,
    required this.periodStart,
    required this.targetCents,
    required this.targetAnchor,
  });

  /// Applies [m] and returns the row's display value. Error lines are
  /// fold-inert: no balance change, no history/anchor append, no period
  /// move, no target re-declaration — but they still get a display
  /// value so every money row can carry one.
  int step(MoneyLineMatch m) {
    if (!MarkdownMoneySyntax.hasError(m)) {
      balance = MarkdownMoneySyntax.apply(balance, m);
      if (MarkdownMoneySyntax.isEntryKind(m.kind)) {
        history.add(balance);
        if (m.kind == MoneyLineKind.set) {
          periodStart = history.length - 1;
          anchors.add(balance);
        }
      }
      if (m.kind == MoneyLineKind.target) {
        targetCents = m.amountFixed ~/ 100;
        targetAnchor = balance;
      }
    }
    return MarkdownMoneySyntax.displayValue(
      m,
      balance,
      history,
      periodStart,
      anchors,
      targetCents: targetCents,
      targetAnchor: targetAnchor,
    );
  }
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

  /// Display value of a `$!` status row with no target declared above
  /// it. Sits outside every reachable value — a real display value is
  /// bounded by ±3×[balanceLimitCents] (target + balance − anchor, each
  /// term clamped) — and stays well under 2^53, so it is exact on web.
  /// Renderers check [isNoTarget] before formatting and paint a
  /// "no target" chip in the warning accent instead of a number.
  static const int noTargetSentinel = 4 * balanceLimitCents;

  /// Whether [value] is the [noTargetSentinel] — a `$!` status row with
  /// nothing to measure. One helper so no surface compares raw ints.
  static bool isNoTarget(int value) => value == noTargetSentinel;

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
  static const int _kBullet = 0x2022; // • (list bullet, matching the list grammar)
  static const int _kParen = 0x29; // ) (ordered-list delimiter)
  static const int _kUnderscore = 0x5F; // _ (emphasis wrapper)

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
  /// 1–6 `#` heading prefix + space or a list marker + space (cheap
  /// pre-check so hot per-line paths can skip the full parse).
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
    // Optional list-marker prefix, mirroring [parse]: bullet char or
    // digit run + `.`/`)`, then a space — after which the shared tail
    // below probes for the `$` or a heading prefix leading to one, so
    // all three chrome prefixes compose (`- ## $$`).
    if ((c == _kMinus || c == _kStar || c == _kPlus || c == _kBullet) &&
        i + 1 < end &&
        _isSpace(source.codeUnitAt(i + 1))) {
      i += 2;
      while (i < end && _isSpace(source.codeUnitAt(i))) {
        i++;
      }
      if (i >= end) return false;
    } else if (_isDigit(c)) {
      var j = i + 1;
      while (j < end && _isDigit(source.codeUnitAt(j))) {
        j++;
      }
      if (j + 1 >= end ||
          (source.codeUnitAt(j) != _kDot && source.codeUnitAt(j) != _kParen) ||
          !_isSpace(source.codeUnitAt(j + 1))) {
        return false;
      }
      i = j + 2;
      while (i < end && _isSpace(source.codeUnitAt(i))) {
        i++;
      }
      if (i >= end) return false;
    }
    final c2 = source.codeUnitAt(i);
    if (_probeDollar(source, i, end)) return true;
    if (c2 != _kHash) return false;
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
    return _probeDollar(source, i, end);
  }

  /// Probe tail: a `$` at [i], directly or behind a 1–3 char emphasis
  /// run (`*$$`, `**$=`, `_$~`). Prefix-only — the closing run is
  /// [parse]'s job, and a probe over-accept just falls back to plain
  /// rendering, while the reverse (parse ⊆ probe) is the invariant the
  /// folds depend on.
  static bool _probeDollar(String source, int i, int end) {
    if (i >= end) return false;
    final c = source.codeUnitAt(i);
    if (c == _kDollar) return true;
    if (c != _kStar && c != _kUnderscore) return false;
    var j = i;
    while (j < end && source.codeUnitAt(j) == c) {
      j++;
    }
    return j - i <= 3 && j < end && source.codeUnitAt(j) == _kDollar;
  }

  /// Parses [line] as a money line, or `null` when it is not one.
  ///
  /// Shape: optional leading spaces/tabs, an optional list marker
  /// (bullet or ordered) + space, an optional 1–6 `#` heading prefix
  /// (space before the `$` optional) — all three chrome prefixes
  /// compose (`- ## $$`) — then `$` + op char, an optional letter-led
  /// colour-name token ending in `:` (followed by a space or the line
  /// end), then for ops an amount (`digits` with optional `.`/`,`
  /// decimals) that must end at a space or the line end, then an
  /// optional label. `$$` / `$?` / `$^` take no amount. A malformed
  /// amount rejects the whole line so it renders as plain text; a
  /// *well-formed* amount past the digit limits (and `$/ 0`) instead
  /// parses as an error row — yellow, does not count — so an over-limit
  /// line is visibly broken rather than silently inert.
  static MoneyLineMatch? parse(String line) {
    // Not final: an emphasis wrapper reduces the parse end to its
    // closing run, so the whole body reads only the wrapped content.
    var n = line.length;
    if (n < 2 || n > maxLineLength) return null;
    var i = 0;
    while (i < n && _isSpace(line.codeUnitAt(i))) {
      i++;
    }
    // Optional list-marker prefix (`- $= 500`, `1. $+ 50`), scanned
    // exactly like [MarkdownListSyntax] shapes it: bullet char or
    // digits + `.`/`)`, a space, then — for this grammar — the `$`
    // or a heading prefix leading to one (`- ## $$`; all three chrome
    // prefixes compose). A task box (`- [ ]`) never reaches the `$`,
    // so checkbox lines keep their behaviour.
    var listMarkerStart = -1;
    var listMarkerEnd = -1;
    if (i < n) {
      final c0 = line.codeUnitAt(i);
      if ((c0 == _kMinus || c0 == _kStar || c0 == _kPlus || c0 == _kBullet) &&
          i + 1 < n &&
          _isSpace(line.codeUnitAt(i + 1))) {
        var j = i + 2;
        while (j < n && _isSpace(line.codeUnitAt(j))) {
          j++;
        }
        if (j < n && _isMoneyLeadChar(line.codeUnitAt(j))) {
          listMarkerStart = i;
          listMarkerEnd = i + 1;
          i = j;
        }
      } else if (_isDigit(c0)) {
        var j = i + 1;
        while (j < n && _isDigit(line.codeUnitAt(j))) {
          j++;
        }
        if (j + 1 < n &&
            (line.codeUnitAt(j) == _kDot || line.codeUnitAt(j) == _kParen) &&
            _isSpace(line.codeUnitAt(j + 1))) {
          var k = j + 2;
          while (k < n && _isSpace(line.codeUnitAt(k))) {
            k++;
          }
          if (k < n && _isMoneyLeadChar(line.codeUnitAt(k))) {
            listMarkerStart = i;
            listMarkerEnd = j + 1;
            i = k;
          }
        }
      }
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
      // `$` directly, or an emphasis run wrapping it (`## *$$*`).
      if (i >= n ||
          (line.codeUnitAt(i) != _kDollar &&
              line.codeUnitAt(i) != _kStar &&
              line.codeUnitAt(i) != _kUnderscore)) {
        return null;
      }
      headerStart = h;
      headerLevel = level;
    }
    // Optional emphasis wrapper: 1–3 uniform `*`/`_` tight against the
    // `$` (so `* $=` stays a bullet, never emphasis), whose matching
    // closer — same char, same length — ends the line (trailing spaces
    // allowed). The parse end drops to the closer, so the whole body
    // below reads only the wrapped content and every in-row offset
    // respects it. Tight-but-unclosed rejects the line: it renders as
    // visibly raw text rather than a half-styled guess.
    var emphasisStart = -1;
    var emphasisLen = 0;
    var emphasisCloseStart = -1;
    if (i < n) {
      final ec = line.codeUnitAt(i);
      if (ec == _kStar || ec == _kUnderscore) {
        var j = i;
        while (j < n && line.codeUnitAt(j) == ec) {
          j++;
        }
        final runLen = j - i;
        if (runLen <= 3 && j < n && line.codeUnitAt(j) == _kDollar) {
          var e = n;
          while (e > j && _isSpace(line.codeUnitAt(e - 1))) {
            e--;
          }
          var s = e;
          while (s > j && line.codeUnitAt(s - 1) == ec) {
            s--;
          }
          if (e - s != runLen || s <= j + 1) return null;
          emphasisStart = i;
          emphasisLen = runLen;
          emphasisCloseStart = s;
          i = j;
          n = s;
        }
      }
    }
    if (i >= n || line.codeUnitAt(i) != _kDollar) return null;
    final markerStart = i;
    i++;
    if (i >= n) return null;
    final op = line.codeUnitAt(i);
    // Not final: a `$!` with no amount reshapes to [MoneyLineKind
    // .remaining] below, after both declaration shapes have failed —
    // the [match] closure captures the variable, so it sees the change.
    MoneyLineKind kind;
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

    // Single construction point for every accepted shape: the shared
    // prefix facts (kind, heading, list marker, `$` marker, accent) are
    // threaded here once — a closure, so it sees later mutations like
    // the post-count accent of `$~ 2 teal:`. A new [MoneyLineMatch]
    // field is added here and nowhere else, instead of at five
    // return sites.
    MoneyLineMatch match({
      required int amountStart,
      required int amountEnd,
      required int labelStart,
      required int labelEnd,
      required int amountFixed,
      int windowCount = 1,
      int valueSlot = -1,
      MoneyLineError? error,
    }) {
      return MoneyLineMatch(
        kind: kind,
        headerStart: headerStart,
        headerLevel: headerLevel,
        listMarkerStart: listMarkerStart,
        listMarkerEnd: listMarkerEnd,
        emphasisStart: emphasisStart,
        emphasisLen: emphasisLen,
        emphasisCloseStart: emphasisCloseStart,
        markerStart: markerStart,
        markerEnd: markerEnd,
        accentStart: accentStart,
        accentEnd: accentEnd,
        amountStart: amountStart,
        amountEnd: amountEnd,
        labelStart: labelStart,
        labelEnd: labelEnd,
        amountFixed: amountFixed,
        windowCount: windowCount,
        valueSlot: valueSlot,
        error: error,
      );
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
      return match(
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
        return match(
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
      // Label-first (`$- Loss on trade: 5000 with fees`): the amount
      // trails its label behind a `:`, with free trailing text after
      // it. Requiring the colon is what keeps this unambiguous —
      // without it `$- food 2024` would silently subtract 2024 — and
      // it costs nothing, since a label ending in `:` is how you would
      // write the line anyway.
      final tail = _scanTrailingAmount(line, i, n, maxInt, maxDec);
      if (tail == null) {
        // A `$!` with no amount in either shape is the target's status
        // row: the whole tail (colons included — they are just label
        // text here, unlike the op rows' amount promise) is its label.
        // Gated on a space (or line end) right after the marker, like
        // the other display rows, so `$!important` stays plain text.
        if (kind == MoneyLineKind.target &&
            (markerEnd >= n || _isSpace(line.codeUnitAt(markerEnd)))) {
          kind = MoneyLineKind.remaining;
          return match(
            amountStart: i,
            amountEnd: i,
            labelStart: i,
            labelEnd: n,
            amountFixed: 0,
            valueSlot: _scanValueSlot(line, i, n),
          );
        }
        // Check if the label ends with a colon (syntax error: missing amount)
        var trimEnd = n;
        while (trimEnd > i && _isSpace(line.codeUnitAt(trimEnd - 1))) {
          trimEnd--;
        }
        if (trimEnd > i && line.codeUnitAt(trimEnd - 1) == _kColon) {
          // Label-first shape detected (ends with `:`) but no trailing amount
          return match(
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
        return match(
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

    return match(
      amountStart: amountStart,
      amountEnd: amountEnd,
      labelStart: labelStart,
      labelEnd: labelEnd,
      amountFixed: amountFixed,
      // A label-first row has two text regions — the label before the
      // `:` and the free trailing text after the amount — and a lone
      // `$` slot may sit in either; document order wins. Every other
      // shape's label runs to the line end, so one scan covers it.
      valueSlot: labelStart < amountStart
          ? _firstNonNegative(
              _scanValueSlot(line, labelStart, labelEnd),
              _scanValueSlot(line, amountEnd, n),
            )
          : _scanValueSlot(line, labelStart, labelEnd),
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

  /// Scans a label-first op row for its `label: AMOUNT` pair, allowing
  /// arbitrary trailing text after the amount: `$= Net worth: 5000 lei
  /// as of today`. Returns the label's end (just past the `:`), the
  /// amount's bounds, and its value — or `null` when the line has no
  /// such pair. Trailing text is left in `[amountEnd, line.length)` for
  /// renderers; parsing stays currency-agnostic, so a display setting
  /// can never change which lines count as ledger entries.
  ///
  /// The amount is found deterministically — never guessed: the **last**
  /// whole token in the line that (a) parses as an amount, (b) ends at a
  /// space or the line end, and (c) directly follows a `:` (spaces
  /// allowed between). Candidates are walked right-to-left, so
  /// `$= a: 100 b: 200 end` reads amount 200 with `a: 100 b` as the
  /// label. A colon tight against the token whose left side is also a
  /// digit (`9:30`, `2024:500`) is a time/ratio, not a `label: amount`
  /// pair — that candidate is skipped, so `$= Note: 500 at 9:30` finds
  /// 500. Something must precede the colon (`label:` shape), so a line
  /// with no colon-led amount anywhere stays plain text.
  static ({
    int labelEnd,
    int amountStart,
    int amountEnd,
    int fixed,
    MoneyLineError? error,
  })?
  _scanTrailingAmount(String line, int from, int n, int maxInt, int maxDec) {
    var searchEnd = n;
    while (searchEnd > from) {
      // Rightmost digit at or before [searchEnd], then the maximal
      // amount-shaped run (digits plus decimal marks) it belongs to.
      var e = searchEnd;
      while (e > from && !_isDigit(line.codeUnitAt(e - 1))) {
        e--;
      }
      if (e <= from) return null;
      var s = e;
      while (s > from) {
        final c = line.codeUnitAt(s - 1);
        if (!_isDigit(c) && c != _kDot && c != _kComma) break;
        s--;
      }
      // Every rejection below resumes left of this run, so the walk
      // strictly progresses.
      searchEnd = s;
      // Whole token only: `70897lei` is not an amount.
      if (e < n && !_isSpace(line.codeUnitAt(e))) continue;
      var c = s;
      while (c > from && _isSpace(line.codeUnitAt(c - 1))) {
        c--;
      }
      if (c <= from || line.codeUnitAt(c - 1) != _kColon) continue;
      // digit:digit with a tight colon is a time or ratio, never a
      // `label: amount` pair.
      if (c == s && c - 1 > from && _isDigit(line.codeUnitAt(c - 2))) {
        continue;
      }
      final parsed = _parseAmount(line, s, e, maxInt, maxDec);
      if (parsed == null || parsed.end != e) continue;
      return (
        labelEnd: c,
        amountStart: s,
        amountEnd: e,
        fixed: parsed.fixed,
        error: parsed.error,
      );
    }
    return null;
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

  /// Whether [kind] is a display row — `$$` / `$?` / bare `$!` / `$^` /
  /// `$~` — one that performs no arithmetic and features its computed
  /// value as a pill/chip. The one grouping every surface branches on.
  /// A `$! N` *declaration* is deliberately not one: like `$=`, its
  /// operand is its value, so it renders amount-led with no pill.
  static bool isDisplayKind(MoneyLineKind kind) =>
      kind == MoneyLineKind.total ||
      kind == MoneyLineKind.delta ||
      kind == MoneyLineKind.remaining ||
      kind == MoneyLineKind.diff ||
      kind == MoneyLineKind.span;

  /// Whether rendering [m] needs the folded running balance: display
  /// rows always, plus any row whose label placed a value slot. The
  /// live editor uses this to route a line onto its positional
  /// (balance-keyed) span path instead of the text-keyed memo.
  static bool needsBalance(MoneyLineMatch m) =>
      m.valueSlot >= 0 || isDisplayKind(m.kind);

  /// Whether [kind]'s displayed value carries an **explicit sign** —
  /// `+12.50`, `-8.00`, `±0.00` — rather than reading as a plain
  /// amount. The rule is "a value the surfaces colour by its sign shows
  /// that sign": `$?`/`$^`/`$~` measure movement and bare `$!` measures
  /// a budget surplus (`+`) or deficit (`-`), so all four print signed;
  /// `$$` is an absolute balance (red only when negative, never `+`)
  /// and every op row's value is a balance too. One predicate for the
  /// preview pill, the editor chip, and both the detail sheet's header
  /// and its rows — the four used to spell this out separately and had
  /// already drifted (bare `$!` was signed on none of them while being
  /// colour-coded on all).
  static bool isSignedKind(MoneyLineKind kind) =>
      kind == MoneyLineKind.delta ||
      kind == MoneyLineKind.diff ||
      kind == MoneyLineKind.span ||
      kind == MoneyLineKind.remaining;

  /// Canonical chrome glyph for [kind] — `= + − × ÷ Σ Δ Δ= Δ~ ◎` —
  /// shared by the preview's marker rendering, the editor's op
  /// substitutions and chip labels, and the detail sheet's leading
  /// glyphs, so the three surfaces can never drift apart. The editor's
  /// caret rule still narrows `Δ=`/`Δ~` to `Δ` at its call site where a
  /// substitution must stay one code unit wide.
  static String glyph(MoneyLineKind kind) => switch (kind) {
    MoneyLineKind.set => '=',
    MoneyLineKind.add => '+',
    MoneyLineKind.subtract => '−',
    MoneyLineKind.multiply => '×',
    MoneyLineKind.divide => '÷',
    MoneyLineKind.total => 'Σ',
    MoneyLineKind.delta => 'Δ',
    MoneyLineKind.diff => 'Δ=',
    MoneyLineKind.span => 'Δ~',
    MoneyLineKind.target => '◎',
    MoneyLineKind.remaining => '◎',
  };

  /// The human label a presenter shows for [m], with the row chrome
  /// trimmed: the label-first colon dropped, the inline currency word
  /// skipped, and a label-first row's free trailing text joined on —
  /// the exact composition the preview renders inline, so a list
  /// surface (the detail sheet) reads the same sentence as the note.
  static String displayLabel(String line, MoneyLineMatch m, String symbol) {
    final labelFirst = m.labelStart < m.amountStart;
    final to = labelFirst ? m.labelEnd - 1 : m.labelEnd;
    final from = labelStartAfterCurrency(line, m, symbol);
    var label = from < to ? line.substring(from, to) : '';
    // Content ends at the emphasis closer when the row is wrapped —
    // the closing run is chrome, not label text.
    final contentEnd = m.emphasisCloseStart >= 0
        ? m.emphasisCloseStart
        : line.length;
    if (labelFirst && m.amountEnd < contentEnd) {
      final curEnd = inlineCurrencyEnd(line, m, symbol);
      final tail = line
          .substring(curEnd >= 0 ? curEnd : m.amountEnd, contentEnd)
          .trim();
      if (tail.isNotEmpty) {
        label = label.isEmpty ? tail : '$label $tail';
      }
    }
    return label;
  }

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
      case MoneyLineKind.remaining:
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
      case MoneyLineKind.remaining:
      case MoneyLineKind.diff:
      case MoneyLineKind.span:
        return false;
    }
  }

  /// Whether [m] actually appends to the ledger histories: an entry
  /// kind without a syntax error. The one predicate for "this line
  /// counts", shared by [MoneyFold.step] and the line-list collection
  /// in [collectEntries] so they can never disagree.
  static bool isCountedEntry(MoneyLineMatch m) =>
      !hasError(m) && isEntryKind(m.kind);

  /// The display value a money line's stored entry carries: the running
  /// balance, except `$?` (net change since the last `$=`), `$! N` (the
  /// declared target itself — a declaration is a statement, its operand
  /// *is* its value, like `$=`), bare `$!` (the remaining budget:
  /// target − spent since the declaration, via [targetCents] and
  /// [targetAnchor]; the [noTargetSentinel] when no target is active),
  /// `$^ N` (the change over the last N balance-changing entries), and
  /// `$~ N` (the change over the last N `$=` checkpoints).
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
    List<int> anchors, {
    int? targetCents,
    int targetAnchor = 0,
  }) {
    switch (m.kind) {
      case MoneyLineKind.delta:
        return balance - history[periodStart];
      case MoneyLineKind.target:
        return m.amountFixed ~/ 100;
      case MoneyLineKind.remaining:
        if (targetCents == null) return noTargetSentinel;
        return targetCents + balance - targetAnchor;
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

  /// The end offset (exclusive) of a currency word typed inline right
  /// after the amount — `$= 500 lei`, `$+ 50 lei coffee` — or -1 when
  /// the row has none.
  ///
  /// Recognised **only** when the word is the note's effective currency
  /// [symbol] (ASCII-case-insensitively, so `Lei` matches `lei`), so the
  /// engine never guesses: any other word after the amount stays plain
  /// label text exactly as it always did, and switching the note's
  /// currency turns a no-longer-matching word back into a label.
  ///
  /// Display-only, like every other use of the symbol — [parse] stays
  /// currency-agnostic and [MoneyLineMatch] is unchanged, so no ledger
  /// value can depend on how a row was spelled. Renderers use this to
  /// drop the word from the label, since the row's own value already
  /// prints the currency; a surface that shows source verbatim (the live
  /// editor) simply ignores it and leaves the word visible as typed.
  ///
  /// Works on both spellings, because the word always sits immediately
  /// after the amount in source order: at the label start on an
  /// amount-first row (`$+ 50 lei coffee`), right after the trailing
  /// amount on a label-first one (`$= Net worth: 500 lei as of today`).
  static int inlineCurrencyEnd(String line, MoneyLineMatch m, String symbol) {
    if (symbol.isEmpty) return -1;
    // A row with no typed amount has nothing for the word to attach to.
    if (m.amountEnd <= m.amountStart) return -1;
    final labelFirst = m.labelStart < m.amountStart;
    // Free trailing text ends at the emphasis closer when wrapped —
    // the closing run is chrome and can never be part of the word.
    final limit = labelFirst
        ? (m.emphasisCloseStart >= 0 ? m.emphasisCloseStart : line.length)
        : m.labelEnd;
    var start = m.labelStart;
    if (labelFirst) {
      start = m.amountEnd;
      while (start < limit && _isSpace(line.codeUnitAt(start))) {
        start++;
      }
    }
    final end = start + symbol.length;
    if (end > limit) return -1;
    // Must be a whole word: `lei` never matches inside `leisure`.
    if (end < limit && !_isSpace(line.codeUnitAt(end))) return -1;
    for (var i = 0; i < symbol.length; i++) {
      if (_lower(line.codeUnitAt(start + i)) != _lower(symbol.codeUnitAt(i))) {
        return -1;
      }
    }
    return end;
  }

  /// The row's value slot with the inline-currency rule applied: when
  /// the configured [symbol] is itself `$` and the word right after the
  /// amount matches it, that `$` reads as the typed currency — never as
  /// a slot — so `$= Net worth: 500 $` prints one value, not two.
  /// Renderers must use this instead of [MoneyLineMatch.valueSlot]
  /// whenever a slot decision is made, so both surfaces void it
  /// identically.
  static int effectiveValueSlot(String line, MoneyLineMatch m, String symbol) {
    final slot = m.valueSlot;
    if (slot < 0) return -1;
    final curEnd = inlineCurrencyEnd(line, m, symbol);
    if (curEnd < 0) return slot;
    return slot >= curEnd - symbol.length && slot < curEnd ? -1 : slot;
  }

  /// Start of the label proper on [m], skipping an inline currency word
  /// and the spaces behind it so the caller never has to re-derive the
  /// spacing rule. Returns [MoneyLineMatch.labelStart] unchanged when
  /// the row has no such word — including every label-first row, where
  /// the word trails the amount and so sits outside the label entirely.
  static int labelStartAfterCurrency(
    String line,
    MoneyLineMatch m,
    String symbol,
  ) {
    if (m.labelStart < m.amountStart) return m.labelStart;
    final end = inlineCurrencyEnd(line, m, symbol);
    if (end < 0) return m.labelStart;
    var i = end;
    while (i < m.labelEnd && _isSpace(line.codeUnitAt(i))) {
      i++;
    }
    return i;
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
  static MoneyLedgerCollection collectEntries({
    required int lineCount,
    required String Function(int) lineAt,
    required bool Function(int) isInert,
    int toLine = -1,
    int startCents = 0,
  }) {
    final last = toLine < 0 ? lineCount - 1 : toLine;
    final entries = <MoneyLedgerEntry>[];
    final fold = MoneyFold(startCents);
    final entryLines = <int>[];
    final anchorLines = <int>[];
    final targetLines = <int>[];
    for (var i = 0; i <= last && i < lineCount; i++) {
      final line = lineAt(i);
      if (line.isEmpty || !leadsWithMoney(line) || isInert(i)) continue;
      final m = parse(line);
      if (m == null) continue;
      if (isCountedEntry(m)) {
        entryLines.add(i);
        if (m.kind == MoneyLineKind.set) anchorLines.add(i);
      }
      // Target declarations mirror the fold's error guard: an error
      // declaration never becomes the active target, so it never
      // becomes a window baseline either.
      if (m.kind == MoneyLineKind.target && !hasError(m)) {
        targetLines.add(i);
      }
      // Error lines don't mutate the fold, but still appear in entries.
      entries.add(
        MoneyLedgerEntry(
          lineIndex: i,
          line: line,
          match: m,
          valueAfter: fold.step(m),
        ),
      );
    }
    return (
      entries: entries,
      entryLines: entryLines,
      anchorLines: anchorLines,
      targetLines: targetLines,
    );
  }

  /// The ledger rows a `$^ N` measures across: the last N
  /// balance-changing entries, clamped to the current period's start
  /// `$=`. Resolves the window the same way [displayValue] does — N
  /// entries back in the append-only history, floored at the period
  /// start, `ALL` (windowCount < 0) meaning the whole history — then
  /// lists every money row from the baseline entry through [lineIndex]
  /// so a detail sheet's running column reconstructs the change end to
  /// end. Lives beside [displayValue] deliberately: the two resolve the
  /// same reference and must move together.
  static List<MoneyLedgerEntry> diffWindowEntries(
    MoneyLedgerCollection collected,
    MoneyLineMatch tapped,
    int lineIndex,
  ) {
    final entryLines = collected.entryLines;
    final e = entryLines.length;
    if (e == 0) {
      return [
        for (final row in collected.entries)
          if (row.lineIndex == lineIndex) row,
      ];
    }
    // History index of the current period's start: one past the last
    // `$=` entry (index 0 — the note start — before any `$=`).
    final lastAnchorLine = collected.anchorLines.isEmpty
        ? -1
        : collected.anchorLines.last;
    final periodStartHist = lastAnchorLine < 0
        ? 0
        : entryLines.lastIndexOf(lastAnchorLine) + 1;
    final count = tapped.windowCount < 0 ? e + 1 : tapped.windowCount;
    var refHist = e - count;
    if (refHist < periodStartHist) refHist = periodStartHist;
    // history[refHist] is the balance after entryLines[refHist - 1], so
    // that entry is the window's visible baseline (the note start when
    // refHist is 0).
    final baselineLine = refHist >= 1 ? entryLines[refHist - 1] : 0;
    return [
      for (final row in collected.entries)
        if (row.lineIndex >= baselineLine && row.lineIndex <= lineIndex) row,
    ];
  }

  /// The ledger rows a `$~ N` measures across: every money row from the
  /// Nth-most-recent `$=` checkpoint (floored at the first checkpoint,
  /// the note start only when the note has no `$=`) through
  /// [lineIndex]. Mirrors [displayValue]'s span case exactly — same
  /// floor, same `ALL` sentinel handling — and unlike
  /// [diffWindowEntries] deliberately spans whole `$=` periods.
  static List<MoneyLedgerEntry> spanWindowEntries(
    MoneyLedgerCollection collected,
    MoneyLineMatch tapped,
    int lineIndex,
  ) {
    final anchorLines = collected.anchorLines;
    // Checkpoint-balance history length, incl. the note-start index 0
    // that [anchorLines] omits.
    final anchorsLen = anchorLines.length + 1;
    final count = tapped.windowCount < 0 ? anchorsLen : tapped.windowCount;
    final floor = anchorsLen > 1 ? 1 : 0;
    var ref = anchorsLen - count;
    if (ref < floor) ref = floor;
    // Its source line: the note start (line 0) when ref floors there,
    // else the `$=` that set the reference balance.
    final baselineLine = ref >= 1 ? anchorLines[ref - 1] : 0;
    return [
      for (final row in collected.entries)
        if (row.lineIndex >= baselineLine && row.lineIndex <= lineIndex) row,
    ];
  }

  /// The ledger rows a bare `$!` status row measures across: every
  /// money row from the active target's declaration (the last `$!`
  /// above the tapped row — [collectEntries] is run with
  /// `toLine: lineIndex`, so that is `targetLines.last`) through
  /// [lineIndex], the declaration itself included so the sheet opens on
  /// the budget being measured. With no declaration above, just the
  /// tapped row — its "no target" value is the whole story. Lives
  /// beside [displayValue] like the other window resolvers: the two
  /// resolve the same baseline and must move together.
  static List<MoneyLedgerEntry> targetWindowEntries(
    MoneyLedgerCollection collected,
    int lineIndex,
  ) {
    final targetLines = collected.targetLines;
    final baselineLine = targetLines.isEmpty ? lineIndex : targetLines.last;
    return [
      for (final row in collected.entries)
        if (row.lineIndex >= baselineLine && row.lineIndex <= lineIndex) row,
    ];
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

  static int _firstNonNegative(int a, int b) => a >= 0 ? a : b;

  /// Whether [c] can begin the money portion of a line after a chrome
  /// prefix: the `$` itself, a heading hash, or an emphasis-run char
  /// (`*`/`_`) that may wrap the marker. Used by the prefix scans'
  /// lookahead — a false positive is harmless (the later `$` check
  /// rejects and the line falls back to its plain rendering).
  static bool _isMoneyLeadChar(int c) =>
      c == _kDollar || c == _kHash || c == _kStar || c == _kUnderscore;

  static bool _isSpace(int c) => c == 0x20 || c == 0x09;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// ASCII-only lowering, so `Lei`/`LEI` match a configured `lei` while
  /// symbols outside ASCII (`€`, `£`, `лв`) compare unchanged.
  static int _lower(int c) => (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c;
}
