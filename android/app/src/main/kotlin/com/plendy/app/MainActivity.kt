package com.plendy.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.plendy.app/play_integrity"
    private val SCREENSHOT_CHANNEL = "com.plendy.app/screenshot"
    private var integrityTokenProvider: StandardIntegrityTokenProvider? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Create notification channel for FCM messages
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "messages"
            val channelName = "Messages"
            val channelDescription = "Notifications for new messages"
            val importance = NotificationManager.IMPORTANCE_HIGH
            
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableLights(true)
                enableVibration(true)
            }
            
            val notificationManager: NotificationManager =
                getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Play Integrity channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestIntegrityToken" -> {
                    val requestHash = call.argument<String>("requestHash")
                    if (requestHash != null) {
                        requestClassicIntegrityToken(requestHash, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "requestHash is required", null)
                    }
                }
                "prepareStandardIntegrityToken" -> {
                    prepareStandardIntegrityToken(result)
                }
                "requestStandardIntegrityToken" -> {
                    val requestHash = call.argument<String>("requestHash")
                    if (requestHash != null) {
                        requestStandardIntegrityToken(requestHash, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "requestHash is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Screenshot channel - captures the entire window including WebViews
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureScreen" -> {
                    captureScreen(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun captureScreen(result: MethodChannel.Result) {
        try {
            val window = this.window
            val decorView = window.decorView
            
            // Create bitmap with the size of the window
            val width = decorView.width
            val height = decorView.height
            
            if (width <= 0 || height <= 0) {
                result.error("CAPTURE_ERROR", "Invalid window dimensions", null)
                return
            }
            
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use PixelCopy for Android O and above - captures SurfaceViews/WebViews
                PixelCopy.request(window, bitmap, { copyResult ->
                    if (copyResult == PixelCopy.SUCCESS) {
                        // Convert bitmap to PNG bytes
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        val byteArray = stream.toByteArray()
                        bitmap.recycle()
                        result.success(byteArray)
                    } else {
                        bitmap.recycle()
                        result.error("CAPTURE_ERROR", "PixelCopy failed with code: $copyResult", null)
                    }
                }, Handler(Looper.getMainLooper()))
            } else {
                // Fallback for older Android versions
                decorView.isDrawingCacheEnabled = true
                decorView.buildDrawingCache()
                val cache = decorView.drawingCache
                if (cache != null) {
                    val stream = ByteArrayOutputStream()
                    cache.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    val byteArray = stream.toByteArray()
                    decorView.destroyDrawingCache()
                    result.success(byteArray)
                } else {
                    decorView.destroyDrawingCache()
                    result.error("CAPTURE_ERROR", "Drawing cache is null", null)
                }
            }
        } catch (e: Exception) {
            result.error("CAPTURE_ERROR", e.message, e.toString())
        }
    }
    
    private fun requestClassicIntegrityToken(requestHash: String, result: MethodChannel.Result) {
        val integrityManager = IntegrityManagerFactory.create(applicationContext)
        
        val integrityTokenRequest = IntegrityTokenRequest.builder()
            .setNonce(requestHash)
            .build()
        
        integrityManager.requestIntegrityToken(integrityTokenRequest)
            .addOnSuccessListener { response ->
                val token = response.token()
                result.success(mapOf(
                    "token" to token,
                    "type" to "classic"
                ))
            }
            .addOnFailureListener { e ->
                result.error("INTEGRITY_ERROR", e.message, e.toString())
            }
    }
    
    private fun prepareStandardIntegrityToken(result: MethodChannel.Result) {
        val standardIntegrityManager = IntegrityManagerFactory.createStandard(applicationContext)
        
        val prepareRequest = StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
            .build()
        
        standardIntegrityManager.prepareIntegrityToken(prepareRequest)
            .addOnSuccessListener { tokenProvider ->
                integrityTokenProvider = tokenProvider
                result.success(mapOf(
                    "success" to true,
                    "message" to "Standard integrity token provider prepared"
                ))
            }
            .addOnFailureListener { e ->
                result.error("PREPARE_ERROR", e.message, e.toString())
            }
    }
    
    private fun requestStandardIntegrityToken(requestHash: String, result: MethodChannel.Result) {
        if (integrityTokenProvider == null) {
            result.error("NOT_PREPARED", "Standard integrity token provider not prepared. Call prepareStandardIntegrityToken first.", null)
            return
        }
        
        val standardTokenRequest = StandardIntegrityTokenRequest.builder()
            .setRequestHash(requestHash)
            .build()
        
        integrityTokenProvider!!.request(standardTokenRequest)
            .addOnSuccessListener { response ->
                val token = response.token()
                result.success(mapOf(
                    "token" to token,
                    "type" to "standard"
                ))
            }
            .addOnFailureListener { e ->
                result.error("INTEGRITY_ERROR", e.message, e.toString())
            }
    }
}