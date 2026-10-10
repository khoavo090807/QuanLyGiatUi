package com.example.app_quanly_giaiui

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationSoundChannel =
        "com.example.app_quanly_giaiui/notification_sound"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationSoundChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                try {
                    val isMessage = call.argument<String>("type") == "new_message"
                    playNotificationTone(isMessage)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("NOTIFICATION_SOUND_FAILED", error.message, null)
                }
            }
    }

    private fun playNotificationTone(isMessage: Boolean) {
        val durationMs = if (isMessage) 400 else 180
        val volume = if (isMessage) 100 else 80
        val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, volume)
        val started = tone.startTone(ToneGenerator.TONE_PROP_BEEP2, durationMs)
        if (!started) {
            tone.release()
            throw IllegalStateException("Android could not start the notification tone")
        }
        Handler(Looper.getMainLooper()).postDelayed(
            { tone.release() },
            (durationMs + 100).toLong(),
        )
    }
}
