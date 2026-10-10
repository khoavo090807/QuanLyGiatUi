package com.example.app_quanly_giaiui

import android.media.AudioManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationSoundChannel =
        "com.example.app_quanly_giaiui/notification_sound"
    private var activeNotificationRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationSoundChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                try {
                    if (!playDefaultNotificationRingtone()) {
                        playFallbackNotificationTone()
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("NOTIFICATION_SOUND_FAILED", error.message, null)
                }
            }
    }

    private fun playDefaultNotificationRingtone(): Boolean {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return false
        val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
            ?: return false

        activeNotificationRingtone?.stop()
        ringtone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        activeNotificationRingtone = ringtone
        ringtone.play()

        Handler(Looper.getMainLooper()).postDelayed({
            if (activeNotificationRingtone === ringtone) {
                ringtone.stop()
                activeNotificationRingtone = null
            }
        }, 3000)
        return true
    }

    private fun playFallbackNotificationTone() {
        val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
        tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 250)
        Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 350)
    }
}
