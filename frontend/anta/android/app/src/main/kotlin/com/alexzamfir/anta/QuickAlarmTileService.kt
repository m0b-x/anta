package com.alexzamfir.anta

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * The Quick Settings tile (OS-5, B9): one tap from the shade to the
 * quick-alarm sheet, the most one-handed entry the app has.
 *
 * An action tile, not a toggle — it is kept [Tile.STATE_ACTIVE] so no ROM
 * draws it dimmed, and the manifest's `TOGGLEABLE_TILE` meta-data says so for
 * accessibility. The launch goes through `startActivityAndCollapse`: the
 * `PendingIntent` overload from API 34, where the `Intent` one is deprecated
 * and refused for a background start, and the `Intent` one below it. A locked
 * phone is asked to unlock first ([unlockAndRun]) — the sheet writes an event,
 * which is not a lock-screen action. The static launcher shortcut
 * (`res/xml/shortcuts.xml`) fires the same [ACTION_QUICK_ALARM] at
 * [MainActivity], which reports either to Dart the way the alarm-clock show
 * intent is reported.
 */
class QuickAlarmTileService : TileService() {
    companion object {
        const val ACTION_QUICK_ALARM = "com.alexzamfir.anta.QUICK_ALARM"
        private const val REQUEST_QUICK_ALARM = 0x5E57

        /** The intent the tile and the shortcut both launch [MainActivity] with. */
        fun quickAlarmIntent(context: android.content.Context): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_QUICK_ALARM)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_ACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { launchQuickAlarm() } else launchQuickAlarm()
    }

    private fun launchQuickAlarm() {
        val intent = quickAlarmIntent(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this,
                        REQUEST_QUICK_ALARM,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (e: Exception) {
            // A ROM that refuses the launch leaves the shade open; there is
            // nothing better to do from a tile than to stay usable.
        }
    }
}
