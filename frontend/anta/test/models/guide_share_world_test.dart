import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/folder.dart';
import 'package:anta/models/guide_share_world.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/models/share_settings.dart';

/// The sync guide's demo world (`docs/guide-hub-roadmap.md` §11.3): what
/// she shares reaches the other phone only when the beat delivers it, an
/// un-share takes it away the same way, and the other phone's day is read
/// off her events, never kept as a copy of its own.
void main() {
  final day = DateTime.utc(2026, 11, 26);

  CalendarEvent event(String id, String title) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'other',
    startDate: day,
    time: const EventTime(startMinute: 9 * 60),
  );

  late GuideShareWorld world;

  setUp(() {
    world = GuideShareWorld(
      day: day,
      events: [event('a', 'Dentist'), event('b', 'Yoga')],
    );
  });

  test('a share reaches the other phone only after the beat', () {
    expect(world.theirs, isEmpty);
    expect(world.inFlight, isFalse);

    world.share('a', true);

    expect(world.isShared('a'), isTrue);
    expect(world.sharesAny, isTrue);
    expect(world.inFlight, isTrue);
    expect(world.theirs, isEmpty);

    world.deliver();

    expect(world.inFlight, isFalse);
    expect(world.theirs.map((e) => e.id), ['a']);
  });

  test('an un-share removes the event from the other phone at delivery', () {
    world
      ..share('a', true)
      ..deliver()
      ..share('a', false);

    expect(world.withdrawn, isTrue);
    expect(world.inFlight, isTrue);
    expect(world.theirs.map((e) => e.id), ['a']);

    world.deliver();

    expect(world.theirs, isEmpty);
    expect(world.inFlight, isFalse);
  });

  test('a share taken back within the beat lands as nothing', () {
    world
      ..share('a', true)
      ..share('a', false);

    expect(world.inFlight, isFalse);
    world.deliver();
    expect(world.theirs, isEmpty);
    expect(world.withdrawn, isTrue);
  });

  test('nothing is withdrawn before something was shared', () {
    expect(world.withdrawn, isFalse);
    world.share('b', true);
    expect(world.withdrawn, isFalse);
  });

  test('what the other phone shows is derived from her events', () {
    world
      ..share('b', true)
      ..share('a', true)
      ..deliver();

    final theirs = world.theirs;
    // In her order, whatever the order she shared in.
    expect(theirs.map((e) => e.id), ['a', 'b']);
    expect(theirs.map((e) => e.title), ['Dentist', 'Yoga']);
    expect(theirs.every((e) => e.fromPartner), isTrue);
    expect(theirs.any((e) => e.markedShared), isFalse);
    // Her own events stay hers.
    expect(world.events.any((e) => e.fromPartner), isFalse);
    // Read afresh each time, never a list kept beside hers.
    expect(identical(world.theirs, theirs), isFalse);
  });

  test('the other phone opens and closes one of the events it shows', () {
    world
      ..share('a', true)
      ..deliver()
      ..openTheirs('a');
    expect(world.theirOpen, 'a');
    world.closeTheirs();
    expect(world.theirOpen, isNull);
  });

  group('taken back, as the other phone sees it', () {
    test('a share undone within one beat takes nothing back', () {
      world
        ..share('a', true)
        ..share('a', false)
        ..deliver();
      // Her marks say withdrawn; Sam never had it.
      expect(world.withdrawn, isTrue);
      expect(world.takenBack, isFalse);
    });

    test('an event that arrived and left is taken back at delivery', () {
      world
        ..share('a', true)
        ..deliver()
        ..share('a', false);
      expect(world.takenBack, isFalse, reason: 'still on its way');
      world.deliver();
      expect(world.takenBack, isTrue);
    });

    test('one event left is told from another', () {
      world
        ..share('a', true)
        ..share('b', true)
        ..deliver()
        ..share('b', false);
      expect(world.hasLeft('b'), isFalse, reason: 'still on its way');
      world.deliver();
      expect(world.hasLeft('b'), isTrue);
      expect(world.hasLeft('a'), isFalse, reason: 'still there');
      expect(world.takenBack, isTrue);
    });
  });

  group('categories', () {
    const gym = CalendarCategory(
      id: 'gym',
      name: 'Gym',
      colorValue: 0xFF1E88E5,
      iconKey: 'fitness_center',
      sortOrder: 0,
      isBuiltIn: true,
    );

    setUp(() {
      world = GuideShareWorld(
        day: day,
        categories: [gym],
        events: [
          CalendarEvent(
            id: 'run',
            title: 'Run',
            categoryId: 'gym',
            startDate: day,
            time: const EventTime(startMinute: 7 * 60),
          ),
          event('a', 'Dentist'),
        ],
      );
    });

    CalendarEvent added() => CalendarEvent(
      id: 'yoga',
      title: 'Yoga',
      categoryId: 'gym',
      startDate: day,
      time: const EventTime(startMinute: 18 * 60),
    );

    test('a shared category reaches the other phone only after the beat', () {
      world.shareCategory('gym', true);
      expect(world.isCategoryShared('gym'), isTrue);
      expect(world.inFlight, isTrue);
      expect(world.theirs, isEmpty);
      world.deliver();
      // Its events, and none of another category.
      expect(world.theirs.map((e) => e.id), ['run']);
    });

    test('un-sharing it takes its events off at delivery', () {
      world
        ..shareCategory('gym', true)
        ..deliver()
        ..shareCategory('gym', false);
      expect(world.theirs.map((e) => e.id), ['run']);
      world.deliver();
      expect(world.theirs, isEmpty);
      expect(world.takenBack, isTrue);
    });

    test('an event added to a shared category follows by itself, a beat '
        'later', () {
      world
        ..shareCategory('gym', true)
        ..deliver()
        ..addEvent(added());
      expect(world.addedAny, isTrue);
      expect(world.isAdded('yoga'), isTrue);
      expect(world.eventCountOf('gym'), 2);
      expect(world.inFlight, isTrue);
      expect(world.theirs.map((e) => e.id), ['run']);
      world.deliver();
      expect(world.theirs.map((e) => e.id), ['run', 'yoga']);
      expect(world.theirs.every((e) => e.fromPartner), isTrue);
    });

    test('an event added before the share arrives with it', () {
      world
        ..addEvent(added())
        ..shareCategory('gym', true)
        ..deliver();
      expect(world.theirs.map((e) => e.id), ['run', 'yoga']);
    });
  });

  group('folders', () {
    final created = DateTime(2026, 11, 26);

    NoteMetadata note(String id, String folderId) => NoteMetadata(
      id: id,
      folderId: folderId,
      title: id,
      preview: '',
      contentLength: 0,
      chunkCount: 0,
      isCompressed: false,
      createdAt: created,
      updatedAt: created,
    );

    setUp(() {
      world = GuideShareWorld(
        day: day,
        events: const [],
        folders: [
          Folder(id: 'trips', name: 'Trips', createdAt: created),
          Folder(id: 'recipes', name: 'Recipes', createdAt: created),
        ],
        notes: [note('lisbon', 'trips'), note('pancakes', 'recipes')],
      );
    });

    test('a shared folder reaches the other phone only after the beat, '
        'as the partner\'s', () {
      world.shareFolder('trips', true);
      expect(world.isFolderShared('trips'), isTrue);
      expect(world.inFlight, isTrue);
      expect(world.theirFolders, isEmpty);
      world.deliver();
      final theirs = world.theirFolders;
      expect(theirs.map((f) => f.id), ['trips']);
      expect(theirs.single.fromPartner, isTrue);
      expect(theirs.single.share.isShared, isFalse);
      expect(world.theirNotesIn('trips').map((n) => n.id), ['lisbon']);
      expect(world.theirNotesIn('trips').single.fromPartner, isTrue);
      // Hers stay hers.
      expect(world.notes.any((n) => n.fromPartner), isFalse);
    });

    test('un-sharing it closes it on the other phone at delivery', () {
      world
        ..shareFolder('trips', true)
        ..deliver()
        ..openTheirFolder('trips')
        ..shareFolder('trips', false);
      expect(world.theirFolderOpen, 'trips', reason: 'still on its way');
      world.deliver();
      expect(world.theirFolders, isEmpty);
      expect(world.theirFolderOpen, isNull);
    });

    test(
      'a copy is the other phone\'s at once and changes nothing of hers',
      () {
        world
          ..shareFolder('trips', true)
          ..deliver()
          ..copyTheirs('lisbon');
        expect(world.copyCount, 1);
        expect(world.inFlight, isFalse);
        expect(world.notesIn('trips').map((n) => n.id), ['lisbon']);
      },
    );

    test('a share undone within one beat never reaches the other phone', () {
      world
        ..shareFolder('trips', true)
        ..shareFolder('trips', false);
      expect(world.inFlight, isFalse);
      world.deliver();
      expect(world.theirFolders, isEmpty);
    });
  });

  group('stopping', () {
    final created = DateTime(2026, 11, 26);

    setUp(() {
      world = GuideShareWorld(
        day: day,
        categories: const [
          CalendarCategory(
            id: 'other',
            name: 'Other',
            colorValue: 0xFF757575,
            iconKey: 'event',
            sortOrder: 0,
            isBuiltIn: true,
          ),
        ],
        events: [event('a', 'Dentist'), event('b', 'Yoga')],
        folders: [Folder(id: 'trips', name: 'Trips', createdAt: created)],
      );
      world
        ..share('a', true)
        ..shareCategory('other', true)
        ..shareFolder('trips', true)
        ..deliver();
    });

    test('stop-all empties the other phone at delivery and keeps the pair', () {
      expect(world.sharesAnything, isTrue);
      world.stopAll();
      expect(world.sharesAnything, isFalse);
      expect(world.theirs, isNotEmpty, reason: 'still on its way');
      world.deliver();
      expect(world.theirs, isEmpty);
      expect(world.theirFolders, isEmpty);
      expect(world.paired, isTrue);
      expect(world.theirPaired, isTrue);
    });

    test('unpair ends the pair on both phones, the other at delivery', () {
      world.unpair();
      expect(world.paired, isFalse);
      expect(world.sharesAnything, isFalse);
      expect(world.theirPaired, isTrue, reason: 'still on its way');
      expect(world.inFlight, isTrue);
      world.deliver();
      expect(world.theirPaired, isFalse);
      expect(world.theirs, isEmpty);
      expect(world.theirFolders, isEmpty);
    });

    test('a stop taken back within one beat takes nothing back', () {
      world
        ..share('a', false)
        ..share('a', true)
        ..deliver();
      expect(world.takenBack, isFalse);
      expect(world.theirs.map((e) => e.id), ['a', 'b']);
    });
  });

  group('pairing (the pair card)', () {
    final madeAt = DateTime.utc(2026, 11, 26, 9);
    final expiresAt = madeAt.add(const Duration(minutes: 10));

    setUp(() {
      world = GuideShareWorld(day: day, events: const [], paired: false);
    });

    test('opens with nobody paired and nothing in flight', () {
      expect(world.paired, isFalse);
      expect(world.theirPaired, isFalse);
      expect(world.code, isNull);
      expect(world.inFlight, isFalse);
    });

    test('a code made is held with its life, and travels nowhere', () {
      world.makeCode('K7M2Q9XP', madeAt, expiresAt);
      expect(world.code, 'K7M2Q9XP');
      expect(world.codeMadeAt, madeAt);
      expect(world.codeExpiresAt, expiresAt);
      expect(world.inFlight, isFalse);
      world.deliver();
      expect(world.paired, isFalse);
      expect(world.theirPaired, isFalse);
    });

    test('the right code entered on the other phone pairs both after the '
        'beat', () {
      world.makeCode('K7M2Q9XP', madeAt, expiresAt);
      expect(world.redeem('K7M2Q9XP'), isTrue);
      expect(world.redeeming, isTrue);
      expect(world.inFlight, isTrue);
      expect(world.paired, isFalse, reason: 'still on its way');
      expect(world.theirPaired, isFalse, reason: 'still on its way');
      world.deliver();
      expect(world.paired, isTrue);
      expect(world.theirPaired, isTrue);
      expect(world.redeeming, isFalse);
      expect(world.inFlight, isFalse);
    });

    test('a wrong code pairs nobody', () {
      world.makeCode('K7M2Q9XP', madeAt, expiresAt);
      expect(world.redeem('K7M2Q9XQ'), isFalse);
      expect(world.inFlight, isFalse);
      world.deliver();
      expect(world.paired, isFalse);
      expect(world.theirPaired, isFalse);
    });

    test('no code is taken before one is made, and none twice', () {
      expect(world.redeem('K7M2Q9XP'), isFalse);
      world.makeCode('K7M2Q9XP', madeAt, expiresAt);
      expect(world.redeem('K7M2Q9XP'), isTrue);
      expect(world.redeem('K7M2Q9XP'), isFalse);
      world.deliver();
      expect(world.redeem('K7M2Q9XP'), isFalse);
    });

    test('a delivery with nothing entered pairs nobody', () {
      world.makeCode('K7M2Q9XP', madeAt, expiresAt);
      world
        ..deliver()
        ..deliver();
      expect(world.paired, isFalse);
      expect(world.theirPaired, isFalse);
    });
  });

  group('her phone alone: the looks and the alerts', () {
    late GuideShareWorld world;

    setUp(() {
      world = GuideShareWorld(
        day: day,
        events: [event('a', 'Dentist')],
        partnerEvents: [
          CalendarEvent(
            id: 'flight',
            title: 'Flight',
            categoryId: 'travel',
            startDate: day,
            time: const EventTime(startMinute: 14 * 60 + 30),
          ),
        ],
        look: const ShareLook(markMine: false),
        ownAlerts: {'flight'},
        alarmedCategories: {'travel'},
      );
    });

    test('what Sam shares stands on her phone as the partner\'s, and '
        'travels nowhere', () {
      expect(world.partnerEvents.single.fromPartner, isTrue);
      expect(world.inFlight, isFalse);
      expect(world.theirs, isEmpty);
    });

    test('the looks are held and read back, the seed never counted as '
        'picked', () {
      expect(world.look, const ShareLook(markMine: false));
      expect(world.pickedEventLook(ShareEventLook.outlined), isFalse);

      world
        ..setEventLook(ShareEventLook.avatar)
        ..setNoteLook(ShareNoteLook.plain)
        ..setMarkMine(true);
      expect(
        world.look,
        const ShareLook(
          eventLook: ShareEventLook.avatar,
          noteLook: ShareNoteLook.plain,
        ),
      );
      expect(world.pickedEventLook(ShareEventLook.avatar), isTrue);
      expect(world.pickedEventLook(ShareEventLook.plain), isFalse);

      world.setEventLook(ShareEventLook.plain);
      expect(world.look.eventLook, ShareEventLook.plain);
      expect(world.pickedEventLook(ShareEventLook.avatar), isTrue);
      expect(world.inFlight, isFalse, reason: 'a look is this phone\'s own');
    });

    test('the alert choice is held, the seed never counted as chosen', () {
      expect(world.shareAlerts, ShareAlerts.own);
      expect(world.pickedAlerts(ShareAlerts.own), isFalse);
      world
        ..setShareAlerts(ShareAlerts.category)
        ..setShareAlerts(ShareAlerts.off);
      expect(world.shareAlerts, ShareAlerts.off);
      expect(world.pickedAlerts(ShareAlerts.category), isTrue);
      expect(world.pickedAlerts(ShareAlerts.off), isTrue);
      expect(world.pickedAlerts(ShareAlerts.own), isFalse);
    });

    test('what rings follows ShareAlerts.inheritsOn for each choice', () {
      final flight = world.partnerEvents.single;
      final expected = {
        ShareAlerts.off: (own: false, categoryAlarm: false),
        ShareAlerts.own: (own: true, categoryAlarm: false),
        ShareAlerts.category: (own: true, categoryAlarm: true),
      };
      for (final MapEntry(key: choice, value: rings) in expected.entries) {
        world.setShareAlerts(choice);
        expect(world.ringsFor(flight), rings, reason: choice.name);
        // The app's own rule says the same of the category's alerts.
        expect(
          world.ringsFor(flight).categoryAlarm,
          choice.inheritsOn(flight) ?? false,
          reason: choice.name,
        );
      }
    });

    test('nothing of hers rings that she did not ask for', () {
      final bare = GuideShareWorld(
        day: day,
        events: const [],
        partnerEvents: [event('b', 'Yoga')],
        shareAlerts: ShareAlerts.category,
      );
      expect(bare.ringsFor(bare.partnerEvents.single), (
        own: false,
        categoryAlarm: false,
      ));
    });
  });
}
