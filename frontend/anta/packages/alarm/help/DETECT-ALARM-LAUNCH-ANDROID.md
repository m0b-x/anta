# Telling an alarm launch from a manual one on Android

By default, when no activity handles
`com.gdelataillade.alarm.action.RING`, the plugin opens your launcher activity.
That intent uses the same `ACTION_MAIN` / `CATEGORY_LAUNCHER` identity as tapping
the app icon and carries no alarm extras. From inside the activity, the two
launches therefore look the same.

`Alarm.ringing` tells you which alarms are ringing, but not what caused your
activity to open. An app that wants to step back out of the way once the alarm is
stopped, rather than sit on top of whatever the user was doing, needs the
difference — and its existing `MainActivity` can get it by handling the plugin's
`RING` action.

## The RING activity doesn't have to be a dedicated one

[Presenting the alarm on your own screen](https://github.com/gdelataillade/alarm/blob/main/README.md#presenting-the-alarm-on-your-own-screen)
describes using a dedicated activity for alarms. You can instead declare the
`RING` filter on your existing `MainActivity` and continue presenting your
normal Flutter UI.

Declare `RING` on exactly one activity. If multiple activities handle it, the
plugin logs a warning and uses the first match.

Add the second intent filter alongside the existing launcher filter:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    ...>
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>

    <intent-filter>
        <action android:name="com.gdelataillade.alarm.action.RING" />
        <category android:name="android.intent.category.DEFAULT" />
    </intent-filter>
</activity>
```

A launcher tap now arrives with `ACTION_MAIN`, while an alarm launch arrives
with `ACTION_RING` and carries the
[alarm extras](https://github.com/gdelataillade/alarm/blob/main/README.md#presenting-the-alarm-on-your-own-screen).

## Read the alarm intent

Handle both activity creation and relaunch:

```kotlin
import android.content.Intent
import android.os.Bundle
import com.gdelataillade.alarm.alarm.AlarmService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingAlarmId: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        // Activity.getIntent() otherwise continues returning the intent that
        // originally created the activity.
        setIntent(intent)

        handleAlarmIntent(intent)
    }

    private fun handleAlarmIntent(intent: Intent) {
        if (intent.action != AlarmService.ACTION_RING) return

        val alarmId = intent.getIntExtra(AlarmService.EXTRA_ALARM_ID, -1)
        if (alarmId == -1) return

        // Store this until Dart is ready to consume it.
        pendingAlarmId = alarmId
    }
}
```

A cold start is delivered through `onCreate`. With `singleTop`, an existing
`MainActivity` receives `onNewIntent` when it is already at the top of its task.
If it is not at the top, Android can create another activity instance and call
`onCreate` instead.

## What ACTION_RING means

The same `PendingIntent` is used for the full-screen notification and for
tapping the alarm notification. `ACTION_RING` therefore means that the activity
was launched through the alarm notification path; it does not necessarily mean
Android displayed a full-screen activity.

Treat the action as a navigation and lifecycle signal, not as an authentication
boundary. `MainActivity` is exported because a launcher activity has to be, so
any app can send it this action. A dedicated alarm activity can be
`android:exported="false"` instead — the plugin reaches it through a
`PendingIntent`, which launches with your own app's identity — and is then not
reachable from outside at all.

## Passing the launch to Dart

Don't assume Dart is ready to receive a `MethodChannel` message during
`onCreate`. With a newly created Flutter engine, the activity and engine exist
before the Dart entrypoint starts and installs its channel handlers.

So don't push the value to Dart; let Dart pull it. In the same activity:

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.example.app/alarm_launch"
    ).setMethodCallHandler { call, result ->
        when (call.method) {
            // Reading the field here, rather than capturing it above, is what
            // makes this safe: configureFlutterEngine runs inside
            // super.onCreate, before onCreate gets to call handleAlarmIntent.
            "consumeAlarmLaunch" -> {
                result.success(pendingAlarmId)
                pendingAlarmId = null
            }
            else -> result.notImplemented()
        }
    }
}
```

Dart calls `consumeAlarmLaunch` once its own handlers are installed, and clearing
the pending value is what consuming it does.

That covers a cold start. For an `ACTION_RING` intent that arrives later, while
the app is already running, either send a live event on the same channel — Dart
is known to be ready by then — or hold the value until Dart consumes it on the
next resume. A getter that only runs once at startup is not enough on its own.

## Don't let startup navigation replace the alarm screen

Consuming the launch and navigating to your alarm screen is not the end of it.
An alarm cold start runs the same `main()` as a launcher tap, so whatever your
app normally does on startup — a splash screen, an auth gate, an onboarding
check — still runs, and its navigation can land after yours and replace the
alarm screen. The alarm keeps ringing with nothing on screen to say so, which
looks exactly like an alarm that never fired.

So make the launch an input to the first routing decision, rather than a
navigation performed on top of one already made: consume the pending alarm id
before the splash decides where to go, and let its result choose the initial
route. `Alarm.ringing` is a useful cross-check — while it is non-empty, the
alarm screen is what the user needs to see, whatever your normal startup would
have picked.

## Task and back-stack behavior

Using `MainActivity` keeps alarm launches in your app's normal task. Calling
`finish()` then follows that task's existing back stack. In a single-activity app
this often returns to the previously visible task, but it is not guaranteed to
return to whatever the alarm interrupted.

If that isolation is important, use a dedicated alarm activity with its own
`taskAffinity` and `excludeFromRecents`, as described in
[Presenting the alarm on your own screen](https://github.com/gdelataillade/alarm/blob/main/README.md#presenting-the-alarm-on-your-own-screen).
Finishing that activity reliably removes the alarm surface without disturbing
your app's normal task.

Declaring no `RING` activity preserves the default behavior: the launcher
activity opens with no alarm extras.
