import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/alert_ring_controller.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/alarm_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/widgets/alarm_ground.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/lock_screen_curtain.dart';

/// The alarm page's four actions, each with the handle a device flow reaches
/// it by (`tool/qa/flows/alerts/`). The switch to another database is not
/// among them: it is the Open row's other face, under an id of its own, and
/// the robot has readers of its own for it.
enum AlarmAction {
  stop(SemanticsIds.alarmStop),
  snooze(SemanticsIds.alarmSnooze),
  openEvent(SemanticsIds.alarmOpenEvent),
  keep(SemanticsIds.alarmKeepEvent);

  const AlarmAction(this.id);

  final String id;
}

/// Drives [AlarmPage] for the suites: they say what the user does and read
/// what the page shows, and never name a widget type.
///
/// **The seam the page is redrawn against.** Every fact about how the page is
/// put together lives here — that the eyebrow, the time and the day are its
/// first three texts, that the event is a read title row over an excerpt
/// cell and an action row, that Stop and Snooze are buttons under their ids
/// and Keep a text button in a row of its own — so a slice that redraws the
/// page rewrites this file and leaves the test bodies alone, but for the
/// behaviour its record changes on purpose. Inlining a finder back into a
/// suite gives that up.
///
/// The actions are tapped and read by their `SemanticsIds`, the handles the
/// device flows use, so an id that goes missing fails here before it fails a
/// device pass.
///
/// The robot also owns the app the page is shown in, because that is half of
/// what is under test: the page behaves differently as the only route (it
/// cannot be popped) and over another one, and its lock-screen reporting only
/// exists under the app's route observer.
class AlarmPageRobot {
  const AlarmPageRobot(this.tester);

  final WidgetTester tester;

  /// What a dressed surface keeps clear at its top and its bottom: a status
  /// bar and a gesture bar, as a phone has. Without them the page's safe
  /// area and the dock's bottom clearance would be laid out against a
  /// screen no phone has.
  static const double systemBar = 24;

  static const String _underneath = 'a private note';

  static const String _calendar = 'the calendar';

  static const String _dialog = 'a dialog of the page';

  Finder get _page => find.byType(AlarmPage);

  Finder _in(Finder matching) => find.descendant(of: _page, matching: matching);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  /// The Open row, whichever of its two faces it wears.
  Finder get _openRow => _in(find.byType(FormActionRow));

  /// Keep, found by what it is rather than by its id: before the page knows
  /// whose event this is the button is laid out and not yet drawn, and an id
  /// lives in a semantics tree it is not part of.
  Finder get _keepButton => _in(find.byType(FormHeaderTextButton));

  Finder get _titleRow => _in(find.byType(FormReadTitleRow));

  Finder get _excerpt => _in(
    find.descendant(
      of: find.byType(FormIndentedRow),
      matching: find.byType(Text),
    ),
  );

  Finder get _time => _in(
    find.descendant(of: find.byType(FittedBox), matching: find.byType(Text)),
  );

  Finder get _dialogBox => find.byType(AlertDialog);

  NavigatorState get _navigator =>
      tester.state<NavigatorState>(find.byType(Navigator));

  /// The app's strings in the locale it is drawn in, so a caption is found
  /// in German as well. Read off the navigator rather than the page: the
  /// dialog the page raises can outlive it.
  AppLocalizations get _l10n =>
      AppLocalizations.of(tester.element(find.byType(Navigator)))!;

  /// Whether [finder] matches, with the strength of the `findsOneWidget` /
  /// `findsNothing` pair it stands for: a second match fails the test
  /// whichever answer the caller expected.
  bool _shown(Finder finder) {
    final matches = finder.evaluate().length;
    if (matches > 1) {
      fail('Expected at most one match, found $matches: $finder');
    }
    return matches == 1;
  }

  /// [text], held to what `find.text` with `findsOneWidget` asked of it: the
  /// same words anywhere else on the screen fail the test. An empty line is
  /// let through — a blank title beside a blank time is two of them.
  String _once(String text) {
    if (text.isEmpty) return text;
    final matches = find.text(text).evaluate().length;
    if (matches != 1) {
      fail('Expected "$text" once on the screen, found it $matches times');
    }
    return text;
  }

  /// One of the page's own lines by its place: the eyebrow, the time and the
  /// day are the first three texts of the page, in that order, whatever the
  /// state adds below them.
  String _line(int index) => _once(
    tester.widgetList<Text>(_in(find.byType(Text))).elementAt(index).data!,
  );

  /// A caption of the remove row as the user sees it. The row lays both of
  /// its captions out, unseen, to size the slot, and lays the whole row out
  /// unseen until the page knows whose event this is — so being in the tree
  /// is not being on the screen, and only a line a finger could land on
  /// counts.
  bool _captionShown(String text) => _shown(find.text(text).hitTestable());

  Future<void> _tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  // ── The app the page is shown in ─────────────────────────────────────

  Future<void> _pump({
    required Widget home,
    bool observed = false,
    bool appNavigator = false,
    bool curtain = false,
    ThemeData? theme,
    Locale? locale,
    double? textScale,
    Size? surface,
    bool? use24Hour,
    double keyboard = 0,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
      // As Android reports them: the padding is what is left of the system's
      // own inset once the keyboard has taken its share.
      tester.view.viewPadding = const FakeViewPadding(
        top: systemBar,
        bottom: systemBar,
      );
      tester.view.padding = FakeViewPadding(
        top: systemBar,
        bottom: keyboard > systemBar ? 0 : systemBar,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    }
    final dressed = textScale != null || use24Hour != null;
    await tester.pumpWidget(
      MaterialApp(
        // A new app on every pump, never the last one re-dressed: the
        // renderer reports an overflow once per render object, so a loop
        // over locales and text scales that kept the tree would hear about
        // the first state that overflows and none after it.
        key: UniqueKey(),
        navigatorKey: appNavigator ? AppNavigator.navigatorKey : null,
        navigatorObservers: [
          if (observed || appNavigator) AppNavigator.routeObserver,
        ],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: theme,
        builder: !dressed && !curtain
            ? null
            : (context, child) {
                var app = child!;
                if (curtain) app = LockScreenCurtain(child: app);
                if (!dressed) return app;
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: textScale == null
                        ? null
                        : TextScaler.linear(textScale),
                    alwaysUse24HourFormat: use24Hour,
                  ),
                  child: app,
                );
              },
        home: home,
      ),
    );
  }

  /// Pumps the page as the app's only route. Nothing can pop it there, so
  /// Stop and Snooze run and leave it standing — the bare harness the page's
  /// "renders from the payload alone" rule is tested in.
  ///
  /// [controller] replaces the one the page would build. [theme], [locale],
  /// [textScale], [use24Hour] and [surface] dress the device for the layout
  /// cases; left alone, the app is the default one on the 800 × 600 test
  /// surface, on a phone that is on the 12-hour clock. A [surface] comes with
  /// [systemBar] kept clear at its top and bottom, and [keyboard] puts an
  /// inset of that height on it — a keyboard the page beneath left up.
  Future<void> pumpPage(
    AlertPayload payload, {
    AlertRingController? controller,
    ThemeData? theme,
    Locale? locale,
    double? textScale,
    Size? surface,
    bool? use24Hour,
    double keyboard = 0,
  }) async {
    await _pump(
      home: AlarmPage(payload: payload, controller: controller),
      theme: theme,
      locale: locale,
      textScale: textScale,
      surface: surface,
      use24Hour: use24Hour,
      keyboard: keyboard,
    );
    await tester.pump();
  }

  /// Pumps an app with one page of its own, for [ring] to ring over.
  ///
  /// [observed] registers `AppNavigator.routeObserver`, which is what the
  /// page's lock-screen reporting rides on. [appNavigator] also hands the app
  /// `AppNavigator.navigatorKey`, so a navigation the page asks `AppNavigator`
  /// for lands on this navigator. [curtain] mounts `LockScreenCurtain` above
  /// the navigator, where `main.dart` has it.
  Future<void> pumpApp({
    bool observed = false,
    bool appNavigator = false,
    bool curtain = false,
    ThemeData? theme,
    Locale? locale,
    double? textScale,
    Size? surface,
  }) {
    return _pump(
      home: const Scaffold(body: Center(child: Text(_underneath))),
      observed: observed,
      appNavigator: appNavigator,
      curtain: curtain,
      theme: theme,
      locale: locale,
      textScale: textScale,
      surface: surface,
    );
  }

  /// Puts a stand-in for the calendar page on top, stamped the way
  /// `AppNavigator` stamps the real one — which is how it recognises a
  /// calendar already on the stack and opens an occurrence on it instead of
  /// pushing a second. Needs [pumpApp] with `appNavigator`.
  Future<void> openCalendar() async {
    unawaited(
      _navigator.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            name: NavDestinationKind.calendar.name,
            arguments: const NavDestination(NavDestinationKind.calendar),
          ),
          builder: (_) => const Scaffold(body: Center(child: Text(_calendar))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pushes the page over whatever is on top, as a ring does, and returns its
  /// route. [instant] pushes it with no transition, the way `main.dart` does;
  /// without it the page arrives on a page transition like any other route.
  Future<Route<void>> ring(
    AlertPayload payload, {
    AlertRingController? controller,
    bool instant = false,
  }) async {
    final page = AlarmPage(payload: payload, controller: controller);
    final Route<void> route = instant
        ? PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => page,
            transitionDuration: Duration.zero,
          )
        : MaterialPageRoute<void>(builder: (_) => page);
    unawaited(_navigator.push(route));
    await tester.pumpAndSettle();
    return route;
  }

  /// Pushes some other page over whatever is on top.
  Future<void> pushPageOver() async {
    unawaited(
      _navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('another page')),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pops whatever is on top.
  Future<void> popTop() async {
    _navigator.pop();
    await tester.pumpAndSettle();
  }

  /// Takes [route] off the stack without popping it, the way a collapse of
  /// the stack does: the page under it gets no pop to react to.
  Future<void> removeOutright(Route<void> route) async {
    _navigator.removeRoute(route);
    await tester.pumpAndSettle();
  }

  /// Raises a dialog from the page's own context, as the page raises the one
  /// its database switch ends in.
  Future<void> raiseDialog() async {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text(_dialog)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── What the user does ───────────────────────────────────────────────

  Future<void> tap(AlarmAction action) => _tap(_byId(action.id));

  Future<void> stop() => tap(AlarmAction.stop);

  Future<void> snooze() => tap(AlarmAction.snooze);

  Future<void> openEvent() => tap(AlarmAction.openEvent);

  Future<void> keep() => tap(AlarmAction.keep);

  /// A tap on the row that switches to the alarm's own database.
  Future<void> openDatabase() => _tap(_byId(SemanticsIds.alarmOpenDatabase));

  /// A tap that waits for nothing but the frame after it: for a second tap
  /// that has to land while the first one's answer is still out.
  Future<void> tapOpenRowOnce() async {
    await tester.tap(_openRow);
    await tester.pump();
  }

  /// Drags the page's scrolling body by [dy]: down, when positive, which is
  /// what brings back content that has left through the top.
  Future<void> dragBody(double dy) async {
    await tester.drag(_byId(SemanticsIds.alarmBody), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  // ── What the page shows ──────────────────────────────────────────────

  /// Whether an alarm page is what is on screen.
  bool get isUp => _shown(_page);

  /// How many alarm pages are on the navigator, the ones under the top one
  /// included.
  int get pagesOnStack =>
      find.byType(AlarmPage, skipOffstage: false).evaluate().length;

  /// The page's own context: what it was handed down — the locale, the theme,
  /// the text scale, the size — is read from here.
  BuildContext get context => tester.element(_page);

  /// The small line over the time that says what this screen is.
  String get eyebrow => _line(0);

  /// The big time.
  String get time => _line(1);

  /// The line under the time naming the day the ring was due.
  String get dayLine => _line(2);

  /// The line naming what is ringing.
  String get title => _once(tester.widget<FormReadTitleRow>(_titleRow).title);

  /// The event's own time under its title, or null on a page that draws
  /// none.
  String? get eventTime {
    final caption = tester.widget<FormReadTitleRow>(_titleRow).caption;
    return caption == null ? null : _once(caption);
  }

  /// The first line of the event's description, or null on a page that
  /// draws none.
  String? get excerpt {
    if (!_shown(_excerpt)) return null;
    return _once(tester.widget<Text>(_excerpt).data!);
  }

  /// How many lines the description may take before it is cut, and whether
  /// the one on screen was.
  int? get excerptMaxLines => tester.widget<Text>(_excerpt).maxLines;

  bool get excerptCut =>
      tester.renderObject<RenderParagraph>(_excerpt).didExceedMaxLines;

  /// The colour and the glyph of the avatar beside the title.
  Color get avatarColor =>
      tester.widget<EventAvatar>(_in(find.byType(EventAvatar))).color;

  IconData get avatarIcon =>
      tester.widget<EventAvatar>(_in(find.byType(EventAvatar))).icon;

  /// Whether [text] is a line of its own anywhere on the screen. For what
  /// must *not* be there; what must be has a reader of its own.
  bool says(String text) => find.text(text).evaluate().isNotEmpty;

  /// Whether the page says the event goes once the alarm is stopped.
  bool get removeAfterCaptionShown =>
      _captionShown(_l10n.alarmRemoveAfterCaption);

  /// Whether the page says the event stays.
  bool get keptCaptionShown => _captionShown(_l10n.alarmKeptEvent);

  /// What the row that switches to the alarm's own database reads, or null
  /// on a page whose Open row opens the event.
  String? get databaseLabel {
    final row = _byId(SemanticsIds.alarmOpenDatabase);
    if (!_shown(row)) return null;
    return _once(
      tester
          .widget<Text>(find.descendant(of: row, matching: find.byType(Text)))
          .data!,
    );
  }

  /// Whether the database switch answers a tap.
  bool get databaseEnabled =>
      tester.widget<FormActionRow>(_openRow).onTap != null;

  /// Whether [action] is on the page, under the id a device flow finds it by.
  bool isOffered(AlarmAction action) => _shown(_byId(action.id));

  /// Whether [action] answers a tap, or stands switched off in its place.
  bool isEnabled(AlarmAction action) {
    if (action == AlarmAction.openEvent) {
      return tester
              .widget<FormActionRow>(
                find.ancestor(
                  of: _byId(action.id),
                  matching: find.byType(FormActionRow),
                ),
              )
              .onTap !=
          null;
    }
    return tester
        .widget<ButtonStyleButton>(
          find.descendant(
            of: _byId(action.id),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        )
        .enabled;
  }

  /// What [action] reads, or null when it is not offered.
  String? labelOf(AlarmAction action) {
    if (!isOffered(action)) return null;
    return _once(
      tester
          .widget<Text>(
            find.descendant(of: _byId(action.id), matching: find.byType(Text)),
          )
          .data!,
    );
  }

  /// What a screen reader calls [action]: its label, unless the control
  /// names itself more fully than it reads. Read off the node's data, which
  /// is the node with everything merged into it — the id sits on a node
  /// above the button's own.
  String nameOf(AlarmAction action) =>
      tester.getSemantics(_byId(action.id)).getSemanticsData().label;

  /// Whether the system back gesture would close the page.
  bool get backPops => tester
      .widget<PopScope<dynamic>>(
        _in(find.byWidgetPredicate((widget) => widget is PopScope<dynamic>)),
      )
      .canPop;

  /// Whether anything on the screen could raise a keyboard.
  bool get hasTextField => find.byType(EditableText).evaluate().isNotEmpty;

  /// Whether the dialog the database switch ends in is up — the one whose
  /// only button closes the app.
  bool get restartDialogShown =>
      _shown(find.widgetWithText(AlertDialog, _l10n.exitApp));

  /// What that dialog is headed and what it says under it.
  String get restartDialogTitle =>
      _dialogText((dialog) => dialog.title! as Text);

  String get restartDialogBody =>
      _dialogText((dialog) => dialog.content! as Text);

  String _dialogText(Text Function(AlertDialog dialog) part) =>
      _once(part(tester.widget<AlertDialog>(_dialogBox)).data!);

  /// Whether the dialog [raiseDialog] raised is up.
  bool get dialogShown => _shown(find.text(_dialog));

  /// Whether the app's own page is what is on screen.
  bool get underneathShown => _shown(find.text(_underneath));

  /// Whether the app's own page can be touched.
  bool get underneathReachable => _shown(find.text(_underneath).hitTestable());

  /// Whether the calendar's stand-in is what is on screen.
  bool get calendarShown => _shown(find.text(_calendar));

  // ── Where things are ─────────────────────────────────────────────────

  /// The whole screen.
  Rect get screen =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  /// Where [action] is drawn.
  Rect rectOf(AlarmAction action) => tester.getRect(_byId(action.id));

  /// Where Keep is laid out, drawn or not yet.
  Rect get keepRect => tester.getRect(_keepButton);

  /// Where the Open row is, whichever face it wears.
  Rect get openRowRect => tester.getRect(_openRow);

  /// The part of the page that scrolls.
  Rect get bodyRect => tester.getRect(_byId(SemanticsIds.alarmBody));

  /// Where the eyebrow and the time are, and the card that names the event.
  Rect get eyebrowRect => tester.getRect(_in(find.byType(FormSectionLabel)));

  Rect get timeRect => tester.getRect(_time);

  Rect get cardRect => tester.getRect(_in(find.byType(FormRowGroup)).first);

  /// Where the eyebrow's and the day's own text starts.
  double get eyebrowTextLeft => tester
      .getTopLeft(
        find.descendant(
          of: _in(find.byType(FormSectionLabel)),
          matching: find.byType(Text),
        ),
      )
      .dx;

  double get dayLeft => tester.getTopLeft(_in(find.byType(Text)).at(2)).dx;

  /// The line the time is drawn on, as tall as it is held open.
  double get timeLineHeight => tester
      .getSize(find.ancestor(of: _time, matching: find.byType(FittedBox)))
      .height;

  /// The text scale [action]'s label is drawn at.
  double textScaleOf(AlarmAction action) {
    final label = tester.element(
      find.descendant(of: _byId(action.id), matching: find.byType(Text)),
    );
    return MediaQuery.textScalerOf(label).scale(100) / 100;
  }

  // ── The ground and the bars ──────────────────────────────────────────

  /// The ground the page stands on.
  Finder get _pageGround => _in(find.byType(AlarmGround));

  /// The lock-screen cover: the one ground that is not a page's.
  Finder get _coverGround => find.byElementPredicate(
    (element) =>
        element.widget is AlarmGround &&
        element.findAncestorWidgetOfExactType<AlarmPage>() == null,
  );

  /// The colour behind the page: what its scaffold paints, over the ground
  /// it stands on — so the ground itself, for as long as the scaffold paints
  /// nothing. Read through the scaffold, not off the ground alone: an opaque
  /// scaffold hides the ground and puts the page back on the scaffold's own
  /// tone, and the ground's box would go on saying otherwise.
  Color get groundColor {
    final scaffold = tester.widget<Scaffold>(_in(find.byType(Scaffold)));
    return Color.alphaBlend(
      scaffold.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      _colorOf(_pageGround),
    );
  }

  /// What the page says the two system bars wear over it.
  SystemUiOverlayStyle get bars => _barsOf(_pageGround);

  /// Whether the lock-screen cover is drawn, and the same two readings off
  /// it.
  bool get coverShown => _shown(_coverGround);

  Color get coverColor => _colorOf(_coverGround);

  SystemUiOverlayStyle get coverBars => _barsOf(_coverGround);

  /// The first box a ground paints is its own; whatever stands on it paints
  /// after.
  Color _colorOf(Finder ground) => tester
      .widget<ColoredBox>(
        find.descendant(of: ground, matching: find.byType(ColoredBox)).first,
      )
      .color;

  SystemUiOverlayStyle _barsOf(Finder ground) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .descendant(
              of: ground,
              matching: find.byWidgetPredicate(
                (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
              ),
            )
            .first,
      )
      .value;

  // ── What a screen reader is told ─────────────────────────────────────

  /// The node that names this screen, read off the eyebrow.
  SemanticsNode get eyebrowNode => tester.getSemantics(
    find.ancestor(
      of: _in(find.byType(FormSectionLabel)),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
    ),
  );

  /// What a screen reader announces the screen as when it opens, or null
  /// when it would open to silence.
  ///
  /// Found the way Android finds it: a screen is announced only from a node
  /// that scopes a route, by the first labelled node under that scope that
  /// says it names one. The eyebrow naming the route is half of it; the
  /// other half is a scope above the eyebrow, which a page pushed on a bare
  /// route has only if it sets one itself.
  String? get announcedAs {
    SemanticsNode? scope = eyebrowNode;
    while (scope != null &&
        !scope.getSemanticsData().flagsCollection.scopesRoute) {
      scope = scope.parent;
    }
    return scope == null ? null : _routeNameUnder(scope);
  }

  String? _routeNameUnder(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.namesRoute && data.label.isNotEmpty) {
      return data.label;
    }
    String? name;
    node.visitChildren((child) {
      name = _routeNameUnder(child);
      return name == null;
    });
    return name;
  }

  /// The node of the row naming the event.
  SemanticsNode get titleNode => tester.getSemantics(_titleRow);

  /// The node of the Open row, whichever face it wears.
  SemanticsNode get openRowNode => tester.getSemantics(_openRow);

  /// The node of [action], under its id.
  SemanticsNode nodeOf(AlarmAction action) =>
      tester.getSemantics(_byId(action.id));

  /// Everything a screen reader would read on this screen, in order.
  List<String> get spoken => tester.semantics
      .simulatedAccessibilityTraversal()
      .map((node) => node.getSemanticsData().label)
      .where((label) => label.isNotEmpty)
      .toList();
}
