package com.personalsender.app

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireMulticastLock()
                        result.success(multicastLock?.isHeld == true)
                    }
                    "release" -> {
                        releaseMulticastLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("personalsender-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.personalsender.app/multicast"
    }
}
