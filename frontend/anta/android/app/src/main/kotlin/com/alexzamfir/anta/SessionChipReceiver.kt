package com.alexzamfir.anta

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * *Done* on the session chip. A broadcast rather than an activity launch:
 * ending a session should take the chip down, not bring the app to the front.
 */
class SessionChipReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == SessionChip.ACTION_DONE) SessionChip.clear(context)
    }
}
