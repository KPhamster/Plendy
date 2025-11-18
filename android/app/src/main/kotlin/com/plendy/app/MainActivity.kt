package com.plendy.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.plendy.app/play_integrity"
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