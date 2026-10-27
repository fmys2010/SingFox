package top.singfox.singfox

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** State shared between the activity (Flutter channels) and the VPN service. */
object CoreBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile var service: SingFoxVpnService? = null
    @Volatile var running = false
    var sink: EventChannel.EventSink? = null
    /** The Quick Settings tile while it is on screen. */
    @Volatile var tile: SingFoxTileService? = null
    var pendingStart: MethodChannel.Result? = null

    fun started() = main.post {
        running = true
        pendingStart?.success(null)
        pendingStart = null
        sink?.success(mapOf("running" to true))
        tile?.refresh()
    }

    /** The core is down (stopped, failed to start, or the VPN was revoked). */
    fun stopped(error: String) = main.post {
        running = false
        pendingStart?.error("start_failed", error, null)
        pendingStart = null
        sink?.success(mapOf("running" to false, "error" to error))
        tile?.refresh()
    }
}
