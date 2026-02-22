package com.mediabot.mediabot

import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "yt_dlp_channel"
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Chaquopy Python runtime
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "download" -> {
                        val url = call.argument<String>("url") ?: run {
                            result.error("INVALID_ARG", "URL is required", null)
                            return@setMethodCallHandler
                        }
                        val mode = call.argument<String>("mode") ?: run {
                            result.error("INVALID_ARG", "Mode is required", null)
                            return@setMethodCallHandler
                        }

                        // Use public Downloads folder
                        val outputDir = Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS
                        ).absolutePath + "/MediaBot"

                        // Create directory if needed
                        val dir = java.io.File(outputDir)
                        if (!dir.exists()) dir.mkdirs()

                        // Run download on background thread
                        scope.launch {
                            try {
                                val py = Python.getInstance()
                                val module = py.getModule("downloader")
                                val response = module.callAttr(
                                    "download_media", url, outputDir, mode
                                ).toString()

                                withContext(Dispatchers.Main) {
                                    result.success(response)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("PYTHON_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "getInfo" -> {
                        val url = call.argument<String>("url") ?: run {
                            result.error("INVALID_ARG", "URL is required", null)
                            return@setMethodCallHandler
                        }

                        scope.launch {
                            try {
                                val py = Python.getInstance()
                                val module = py.getModule("downloader")
                                val response = module.callAttr("get_info", url).toString()

                                withContext(Dispatchers.Main) {
                                    result.success(response)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("PYTHON_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
