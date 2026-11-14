package com.majumaink.cinesphere

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val PIP_CHANNEL = "pip_channel"
    private val DEVICE_CHANNEL = "cinesphere/device"
    private val PREVIEW_CHANNEL = "cinesphere/video_preview"
    private val PREVIEW_CHANNEL_COMPAT = "com.gallary.mosa/video_preview"
    private val STATS_CHANNEL = "cinesphere/stats"
    private val STATS_CHANNEL_COMPAT = "com.example.movies/stats"
    private val EXTERNAL_PLAYER_CHANNEL = "cinesphere/external_player"
    private val DOWNLOAD_CHANNEL = "cinesphere/downloads"
    private val MEDIA_MUX_CHANNEL = "cinesphere/media_mux"

    private var isPlaying = true
    private var enableAutoPip = false
    private lateinit var videoPreviewHandler: VideoPreviewHandler

    // Network Stats
    private var lastRxBytes: Long = 0
    private var lastTime: Long = 0

    companion object {
        const val ACTION_PLAY = "ACTION_PLAY"
        const val ACTION_PAUSE = "ACTION_PAUSE"
        const val ACTION_REWIND = "ACTION_REWIND"
        const val ACTION_FORWARD = "ACTION_FORWARD"
    }

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PLAY -> {
                    isPlaying = true
                    flutterEngine?.dartExecutor?.let {
                        MethodChannel(it.binaryMessenger, PIP_CHANNEL).invokeMethod("play", null)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        updatePipActions()
                    }
                }
                ACTION_PAUSE -> {
                    isPlaying = false
                    flutterEngine?.dartExecutor?.let {
                        MethodChannel(it.binaryMessenger, PIP_CHANNEL).invokeMethod("pause", null)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        updatePipActions()
                    }
                }
                ACTION_REWIND -> {
                    flutterEngine?.dartExecutor?.let {
                        MethodChannel(it.binaryMessenger, PIP_CHANNEL).invokeMethod("rewind", null)
                    }
                }
                ACTION_FORWARD -> {
                    flutterEngine?.dartExecutor?.let {
                        MethodChannel(it.binaryMessenger, PIP_CHANNEL).invokeMethod("forward", null)
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Device form channel (TV / Tablet detection)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isTelevision") {
                result.success(hasLeanback())
            } else {
                result.notImplemented()
            }
        }

        // 2. Video Preview Handler Channel
        videoPreviewHandler = VideoPreviewHandler(this)
        val previewHandler: (io.flutter.plugin.common.MethodCall, MethodChannel.Result) -> Unit = { call, result ->
            videoPreviewHandler.handleMethodCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PREVIEW_CHANNEL).setMethodCallHandler(previewHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PREVIEW_CHANNEL_COMPAT).setMethodCallHandler(previewHandler)

        // 3. Picture-in-Picture Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        isPlaying = call.argument<Boolean>("isPlaying") ?: true
                        result.success(enterPipMode())
                    } else {
                        result.success(false)
                    }
                }
                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                "isInPip" -> {
                    val inPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode
                    result.success(inPip)
                }
                "updatePlayState" -> {
                    isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) updatePipActions()
                    result.success(true)
                }
                "setAutoPip" -> {
                    enableAutoPip = call.argument<Boolean>("enable") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) updatePipActions()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 4. Live Bandwidth Stats Channel
        val statsHandler: (io.flutter.plugin.common.MethodCall, MethodChannel.Result) -> Unit = { call, result ->
            when (call.method) {
                "getNetworkSpeed" -> {
                    val currentRxBytes = android.net.TrafficStats.getTotalRxBytes()
                    val currentTime = System.currentTimeMillis()

                    if (lastRxBytes == 0L || lastTime == 0L) {
                        lastRxBytes = currentRxBytes
                        lastTime = currentTime
                        result.success(0L)
                    } else {
                        val timeDiff = currentTime - lastTime
                        if (timeDiff >= 500) {
                            val bytesDiff = currentRxBytes - lastRxBytes
                            val speedBps = (bytesDiff * 1000) / timeDiff
                            lastRxBytes = currentRxBytes
                            lastTime = currentTime
                            result.success(speedBps)
                        } else {
                            result.success(0L)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STATS_CHANNEL).setMethodCallHandler(statsHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STATS_CHANNEL_COMPAT).setMethodCallHandler(statsHandler)

        // 5. External Player Channel (opens video intent with custom headers)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openVideoWithHeaders") {
                val url     = call.argument<String>("url") ?: run { result.error("BAD_ARGS", "url is required", null); return@setMethodCallHandler }
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val title   = call.argument<String>("title") ?: ""
                try {
                    val uri = Uri.parse(url)
                    val mimeType = if (url.contains(".m3u8", ignoreCase = true) || url.contains("/hls", ignoreCase = true)) {
                        "application/x-mpegURL"
                    } else {
                        "video/*"
                    }
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mimeType)
                        if (headers.isNotEmpty()) {
                            // MX Player format: alternating ["Header-Key", "Header-Value", ...]
                            val mxHeaders = mutableListOf<String>()
                            headers.forEach { (k, v) ->
                                mxHeaders.add(k)
                                mxHeaders.add(v)
                            }
                            putExtra("headers", mxHeaders.toTypedArray())

                            // VLC format: newline-delimited header lines
                            val headerLines = headers.entries.joinToString("\r\n") { "${it.key}: ${it.value}" }
                            putExtra("extra_headers", headerLines)
                        }
                        if (title.isNotEmpty()) putExtra("title", title)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        // 6. Background download keep-alive (data-sync foreground service)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    val label = call.argument<String>("label") ?: "Downloading media…"
                    try {
                        DownloadKeepAliveService.start(this, label)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    DownloadKeepAliveService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 7. HLS segment muxing (fold .ts segments into one MP4 file)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_MUX_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "muxTsToMp4") {
                val videoPath = call.argument<String>("videoPath")
                val audioPath = call.argument<String>("audioPath")
                val outputPath = call.argument<String>("outputPath")
                if (videoPath == null || outputPath == null) {
                    result.error("BAD_ARGS", "videoPath and outputPath are required", null)
                    return@setMethodCallHandler
                }
                // Remuxing a feature-length file takes seconds; keep the UI
                // thread free and answer once the muxer is done.
                Thread {
                    val ok = try {
                        TsMuxer.mux(videoPath, audioPath, outputPath)
                    } catch (e: Exception) {
                        false
                    }
                    runOnUiThread { result.success(ok) }
                }.start()
            } else {
                result.notImplemented()
            }
        }

        // 8. Register BroadcastReceiver for PiP remote actions
        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY)
            addAction(ACTION_PAUSE)
            addAction(ACTION_REWIND)
            addAction(ACTION_FORWARD)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // API 31+ enters PiP via setAutoEnterEnabled instead; calling enterPip
        // there as well causes a second, visible transition.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            enableAutoPip && isPlaying
        ) {
            enterPipMode()
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        flutterEngine?.dartExecutor?.let {
            MethodChannel(it.binaryMessenger, PIP_CHANNEL)
                .invokeMethod("pipModeChanged", mapOf("isInPip" to isInPictureInPictureMode))
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun enterPipMode(): Boolean {
        if (isFinishing || isDestroyed) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: Exception) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun updatePipActions() {
        setPictureInPictureParams(buildPipParams())
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(buildPipActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ ignores onUserLeaveHint for gesture navigation, so the
            // system needs to be told it may move the activity into PiP itself.
            builder.setAutoEnterEnabled(enableAutoPip && isPlaying)
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipActions(): List<RemoteAction> {
        val actions = mutableListOf<RemoteAction>()

        val rewindIntent = PendingIntent.getBroadcast(
            this,
            1,
            Intent(ACTION_REWIND).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_pip_rewind),
                "Rewind",
                "Rewind 10 seconds",
                rewindIntent
            )
        )

        if (isPlaying) {
            val pauseIntent = PendingIntent.getBroadcast(
                this,
                2,
                Intent(ACTION_PAUSE).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            actions.add(
                RemoteAction(
                    Icon.createWithResource(this, R.drawable.ic_pip_pause),
                    "Pause",
                    "Pause video",
                    pauseIntent
                )
            )
        } else {
            val playIntent = PendingIntent.getBroadcast(
                this,
                3,
                Intent(ACTION_PLAY).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            actions.add(
                RemoteAction(
                    Icon.createWithResource(this, R.drawable.ic_pip_play),
                    "Play",
                    "Play video",
                    playIntent
                )
            )
        }

        val forwardIntent = PendingIntent.getBroadcast(
            this,
            4,
            Intent(ACTION_FORWARD).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, R.drawable.ic_pip_forward),
                "Forward",
                "Forward 10 seconds",
                forwardIntent
            )
        )

        return actions
    }

    private fun hasLeanback(): Boolean {
        val pm = packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("android.hardware.type.television") ||
            pm.hasSystemFeature("android.software.leanback_only")
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(pipReceiver)
        } catch (_: Exception) {}
        if (::videoPreviewHandler.isInitialized) {
            videoPreviewHandler.dispose()
        }
    }
}
