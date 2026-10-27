package top.singfox.singfox

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream
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
            "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
            "apps" -> Thread {
                val list = try { launchableApps() } catch (e: Throwable) { emptyList() }
                runOnUiThread { result.success(list) }
            }.start()
            "appIcon" -> Thread {
                val bytes = try { appIcon(call.argument<String>("package") ?: "") } catch (e: Throwable) { null }
                runOnUiThread { result.success(bytes) }
            }.start()
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

    /** Hands a downloaded APK to the system installer; `needs_permission` when the user must first allow installs from SingFox. */
    private fun installApk(path: String): String {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")))
            return "needs_permission"
        }
        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", java.io.File(path))
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        )
        return "ok"
    }

    /** Apps with a launcher entry, as `{package, label}`, sorted by label. */
    private fun launchableApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    private fun appIcon(pkg: String): ByteArray? {
        val d = packageManager.getApplicationIcon(pkg)
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
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
