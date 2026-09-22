package com.gdelataillade.alarm.services

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import com.gdelataillade.alarm.models.VolumeFadeStep
import java.util.concurrent.ConcurrentHashMap
import java.util.Timer
import java.util.TimerTask
import io.flutter.Log
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

class AudioService(private val context: Context) {
    companion object {
        private const val TAG = "AudioService"

        /**
         * Whether [filePath] names a `content://`, `android.resource://` or
         * `file://` source (ANTA fork, Patch 2).
         *
         * Such a value is handed to `MediaPlayer.setDataSource(Context, Uri)`
         * as it is, before the asset and path branches — the `!startsWith("/")`
         * rewrite there would otherwise prepend the app's files directory to a
         * URI and hand the player a path that names nothing.
         */
        internal fun isUriSource(filePath: String): Boolean =
            filePath.startsWith("content://") ||
                filePath.startsWith("android.resource://") ||
                filePath.startsWith("file://")
    }

    private val mediaPlayers = ConcurrentHashMap<Int, MediaPlayer>()
    private val timers = ConcurrentHashMap<Int, Timer>()
    private val onAudioCompleteListeners = ConcurrentHashMap<Int, () -> Unit>()

    fun setOnAudioCompleteListener(id: Int, listener: () -> Unit) {
        onAudioCompleteListeners[id] = listener
    }

    fun getPlayingMediaPlayersIds(): List<Int> {
        // isPlaying throws on a released player.
        return mediaPlayers.filter { (_, mediaPlayer) ->
            runCatching { mediaPlayer.isPlaying }.getOrDefault(false)
        }.keys.toList()
    }

    fun playAudio(
        id: Int,
        filePath: String?,
        loopAudio: Boolean,
        fadeDuration: Duration?,
        fadeSteps: List<VolumeFadeStep>,
        preferConnectedAudioDevice: Boolean
    ) {
        releaseMediaPlayer(id) // Stop and release any existing MediaPlayer and Timer for this ID

        val mediaPlayer = MediaPlayer()
        try {
            if (filePath == null) {
                // Use the device's default alarm sound
                val defaultAlarmUri = defaultAlarmUri()
                mediaPlayer.setDataSource(context, defaultAlarmUri)
                Log.d(TAG, "Using device default alarm sound: $defaultAlarmUri")
            } else if (isUriSource(filePath)) {
                try {
                    mediaPlayer.setDataSource(context, Uri.parse(filePath))
                    Log.d(TAG, "Using URI sound: $filePath")
                } catch (e: Exception) {
                    Log.w(TAG, "Cannot open $filePath; using the device default alarm sound", e)
                    mediaPlayer.reset()
                    mediaPlayer.setDataSource(context, defaultAlarmUri())
                }
            } else {
                val baseAppFlutterPath = context.filesDir.parent?.plus("/app_flutter/")
                val adjustedFilePath = when {
                    filePath.startsWith("assets/") -> "flutter_assets/$filePath"
                    !filePath.startsWith("/") -> baseAppFlutterPath + filePath
                    else -> filePath
                }

                if (adjustedFilePath.startsWith("flutter_assets/")) {
                    // It's an asset file. Close the descriptor once the data
                    // source is set to avoid leaking a file descriptor per ring.
                    context.assets.openFd(adjustedFilePath).use { descriptor ->
                        mediaPlayer.setDataSource(
                            descriptor.fileDescriptor,
                            descriptor.startOffset,
                            descriptor.length
                        )
                    }
                } else {
                    // Handle local files and adjusted paths
                    mediaPlayer.setDataSource(adjustedFilePath)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val usage = if (preferConnectedAudioDevice)
                    AudioAttributes.USAGE_MEDIA
                else
                    AudioAttributes.USAGE_ALARM
                mediaPlayer.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            } else {
                @Suppress("DEPRECATION")
                val stream = if (preferConnectedAudioDevice)
                    AudioManager.STREAM_MUSIC
                else
                    AudioManager.STREAM_ALARM
                @Suppress("DEPRECATION")
                mediaPlayer.setAudioStreamType(stream)
            }

            mediaPlayer.prepare()
            mediaPlayer.isLooping = loopAudio
            mediaPlayer.start()

            mediaPlayer.setOnCompletionListener {
                if (!loopAudio) {
                    onAudioCompleteListeners[id]?.invoke()
                }
            }

            mediaPlayers[id] = mediaPlayer

            if (fadeSteps.isNotEmpty()) {
                val timer = Timer(true)
                timers[id] = timer
                startStaircaseFadeIn(mediaPlayer, fadeSteps, timer)
            } else if (fadeDuration != null) {
                val timer = Timer(true)
                timers[id] = timer
                startFadeIn(mediaPlayer, fadeDuration, timer)
            }
        } catch (e: Exception) {
            // Never leak the MediaPlayer when setup fails.
            mediaPlayers.remove(id)
            runCatching { mediaPlayer.release() }
            Log.e(TAG, "Error playing audio for alarm $id", e)
        }
    }

    fun stopAudio(id: Int) {
        onAudioCompleteListeners.remove(id)
        releaseMediaPlayer(id)
    }

    /**
     * The device's default alarm sound, or the nearest default it has.
     *
     * Shared by the null path and by a URI the device cannot open (ANTA fork,
     * Patch 2): a sound picked on another phone names a media id this
     * phone's provider never heard of, and an alarm that plays nothing is far
     * worse than one that plays the wrong sound.
     */
    private fun defaultAlarmUri(): Uri =
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: throw IllegalStateException("No default alarm sound available on this device")

    // Releases the MediaPlayer and Timer for this ID without touching the
    // completion listener, so playAudio can clean up a previous player after
    // the listener for the new ring has already been registered.
    private fun releaseMediaPlayer(id: Int) {
        timers[id]?.cancel()
        timers.remove(id)

        mediaPlayers[id]?.apply {
            if (isPlaying) {
                stop()
            }
            reset()
            release()
        }
        mediaPlayers.remove(id)
    }

    private fun startFadeIn(mediaPlayer: MediaPlayer, duration: Duration, timer: Timer) {
        val maxVolume = 1.0f
        val fadeDuration = duration.inWholeMilliseconds
        val fadeInterval = 100L
        // Clamp to at least one step so fades shorter than the interval
        // don't divide by zero.
        val numberOfSteps = (fadeDuration / fadeInterval).coerceAtLeast(1L)
        val deltaVolume = maxVolume / numberOfSteps
        var volume = 0.0f

        timer.schedule(object : TimerTask() {
            override fun run() {
                if (!mediaPlayer.isPlaying) {
                    cancel()
                    return
                }

                mediaPlayer.setVolume(volume, volume)
                volume += deltaVolume

                if (volume >= maxVolume) {
                    mediaPlayer.setVolume(maxVolume, maxVolume)
                    cancel()
                }
            }
        }, 0, fadeInterval)
    }

    private fun startStaircaseFadeIn(
        mediaPlayer: MediaPlayer,
        steps: List<VolumeFadeStep>,
        timer: Timer
    ) {
        val fadeIntervalMillis = 100L
        var currentStep = 0

        timer.schedule(object : TimerTask() {
            override fun run() {
                if (!mediaPlayer.isPlaying) {
                    cancel()
                    return
                }

                val currentTime = (currentStep * fadeIntervalMillis).milliseconds
                val nextIndex = steps.indexOfFirst { it.time >= currentTime }

                if (nextIndex < 0) {
                    cancel()
                    return
                }

                val nextVolume = steps[nextIndex].volume
                var currentVolume = nextVolume

                if (nextIndex > 0) {
                    val prevTime = steps[nextIndex - 1].time
                    val nextTime = steps[nextIndex].time
                    val nextRatio = (currentTime - prevTime) / (nextTime - prevTime)

                    val prevVolume = steps[nextIndex - 1].volume
                    currentVolume = nextVolume * nextRatio + prevVolume * (1 - nextRatio)
                }

                mediaPlayer.setVolume(currentVolume.toFloat(), currentVolume.toFloat())
                currentStep++
            }
        }, 0, fadeIntervalMillis)
    }

    fun cleanUp() {
        onAudioCompleteListeners.clear()

        timers.values.forEach(Timer::cancel)
        timers.clear()

        mediaPlayers.values.forEach { mediaPlayer ->
            if (mediaPlayer.isPlaying) {
                mediaPlayer.stop()
            }
            mediaPlayer.reset()
            mediaPlayer.release()
        }
        mediaPlayers.clear()
    }
}
