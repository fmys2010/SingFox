package top.singfox.singfox

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.io.File

/**
 * The Quick Settings tile: connects with the config of the last connection and
 * disconnects. Without that config or the VPN permission it opens the app.
 */
class SingFoxTileService : TileService() {
    override fun onStartListening() {
        CoreBridge.tile = this
        refresh()
    }

    override fun onStopListening() {
        if (CoreBridge.tile === this) CoreBridge.tile = null
    }

    override fun onClick() {
        if (CoreBridge.running) {
            Thread { CoreBridge.service?.shutdown("") }.start()
            setState(Tile.STATE_INACTIVE, "正在断开…")
            return
        }
        val config = File(filesDir, "box-config.json")
        if (VpnService.prepare(this) != null || !config.exists()) {
            openApp()
            return
        }
        setState(Tile.STATE_ACTIVE, "正在连接…")
        val intent = Intent(this, SingFoxVpnService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION") startActivityAndCollapse(intent)
        }
    }

    fun refresh() {
        if (CoreBridge.running) setState(Tile.STATE_ACTIVE, "已连接") else setState(Tile.STATE_INACTIVE, "未连接")
    }

    private fun setState(state: Int, subtitle: String) {
        val tile = qsTile ?: return
        tile.state = state
        tile.label = "SingFox"
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = subtitle
        tile.updateTile()
    }
}
