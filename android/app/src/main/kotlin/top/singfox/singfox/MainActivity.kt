package top.singfox.singfox

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox

class MainActivity : FlutterActivity() {
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "top.singfox/core").setMethodCallHandler(::onCall)
        EventChannel(messenger, "top.singfox/core_state").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                CoreBridge.sink = events
            }

            override fun onCancel(arguments: Any?) {
                CoreBridge.sink = null
            }
        })
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                pendingConfig = call.argument<String>("config")
                pendingResult = result
                val prepare = VpnService.prepare(this)
                if (prepare == null) launch() else startActivityForResult(prepare, REQUEST_VPN)
            }
            "stop" -> Thread {
                CoreBridge.service?.shutdown("")
                runOnUiThread { result.success(null) }
            }.start()
            "version" -> result.success(try { Libbox.version() } catch (e: Throwable) { "" })
            "isRunning" -> result.success(CoreBridge.running)
            else -> result.notImplemented()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN) {
            if (resultCode == Activity.RESULT_OK) {
                launch()
            } else {
                pendingResult?.error("vpn_denied", "未授予 VPN 权限", null)
                pendingResult = null
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun launch() {
        val config = pendingConfig
        val result = pendingResult
        pendingConfig = null
        pendingResult = null
        if (config == null || result == null) return
        CoreBridge.pendingStart = result
        java.io.File(filesDir, "box-config.json").writeText(config)
        val intent = Intent(this, SingFoxVpnService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    companion object {
        private const val REQUEST_VPN = 1001
    }
}
