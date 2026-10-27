package top.singfox.singfox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import io.nekohasekai.libbox.*
import java.io.File
import java.net.InetAddress

/**
 * Hosts the sing-box core (libbox) and hands it the VPN tunnel. The UI talks to
 * the core through its Clash API, so this class only starts, stops and gives the
 * core the platform pieces it needs: the TUN fd, socket protection and the
 * default network.
 */
class SingFoxVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    private var server: CommandServer? = null
    private var monitor: ConnectivityManager.NetworkCallback? = null
    private var listener: InterfaceUpdateListener? = null
    @Volatile private var defaultNetwork: Network? = null
    /** Our end of the tunnel; libbox dups it, so the VPN only goes away once this is closed too. */
    private var tun: android.os.ParcelFileDescriptor? = null
    private val cm by lazy { getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager }

    override fun onCreate() {
        super.onCreate()
        CoreBridge.service = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        if (server != null) return START_NOT_STICKY // already running (tile tapped twice)
        Thread {
            try {
                startCore(File(filesDir, "box-config.json").readText())
                CoreBridge.started()
            } catch (e: Throwable) {
                shutdown(e.message ?: e.toString())
            }
        }.start()
        return START_NOT_STICKY
    }

    private fun startCore(config: String) {
        val base = filesDir.absolutePath
        val work = File(filesDir, "work").apply { mkdirs() }
        val options = SetupOptions().apply {
            basePath = base
            workingPath = work.absolutePath
            tempPath = cacheDir.absolutePath
            fixAndroidStack = Build.VERSION.SDK_INT < 35
            logMaxLines = 3000
        }
        Libbox.setup(options)
        val s = Libbox.newCommandServer(this, this)
        server = s
        s.start()
        s.startOrReloadService(config, OverrideOptions())
    }

    /** Stops the core and the VPN; [error] is shown in the app when not empty. */
    @Synchronized
    fun shutdown(error: String) {
        val s = server
        server = null
        try { s?.closeService() } catch (_: Throwable) {}
        try { s?.close() } catch (_: Throwable) {}
        stopMonitor()
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        if (CoreBridge.running || error.isNotEmpty() || CoreBridge.pendingStart != null) CoreBridge.stopped(error)
        CoreBridge.running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        Thread { shutdown("VPN 被系统或其他应用撤销") }.start()
    }

    override fun onDestroy() {
        CoreBridge.service = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "SingFox 连接状态", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("SingFox")
            .setContentText("VPN 已连接")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(1, n)
        }
    }

    // ---------------------------------------------------------------- PlatformInterface

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) throw Exception("没有 VPN 权限")
        val b = Builder().setSession("SingFox").setMtu(options.mtu)
        options.inet4Address.forEach { b.addAddress(it.address(), it.prefix()) }
        options.inet6Address.forEach { b.addAddress(it.address(), it.prefix()) }
        if (options.autoRoute) {
            b.addDnsServer(options.dnsServerAddress.next())
            val r4 = options.inet4RouteAddress
            if (r4.hasNext()) r4.forEach { b.addRoute(it.address(), it.prefix()) }
            else if (options.inet4Address.hasNext()) b.addRoute("0.0.0.0", 0)
            val r6 = options.inet6RouteAddress
            if (r6.hasNext()) r6.forEach { b.addRoute(it.address(), it.prefix()) }
            else if (options.inet6Address.hasNext()) b.addRoute("::", 0)
            if (Build.VERSION.SDK_INT >= 33) {
                options.inet4RouteExcludeAddress.forEach { b.excludeRoute(IpPrefix(InetAddress.getByName(it.address()), it.prefix())) }
                options.inet6RouteExcludeAddress.forEach { b.excludeRoute(IpPrefix(InetAddress.getByName(it.address()), it.prefix())) }
            }
            options.includePackage.forEach { b.addAllowedApplication(it) }
            options.excludePackage.forEach { b.addDisallowedApplication(it) }
        }
        val pfd = b.establish() ?: throw Exception("VPN 接口创建失败，可能被其他 VPN 占用")
        tun = pfd
        return pfd.fd
    }

    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun autoDetectInterfaceControl(fd: Int) {
        if (!protect(fd)) throw Exception("protect($fd) 失败")
    }

    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String?, sourcePort: Int, destinationAddress: String?, destinationPort: Int): ConnectionOwner =
        throw Exception("unsupported")

    override fun startDefaultInterfaceMonitor(l: InterfaceUpdateListener) {
        listener = l
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refresh()
            override fun onLost(network: Network) = refresh()
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = refresh()
            override fun onLinkPropertiesChanged(network: Network, lp: android.net.LinkProperties) = refresh()
        }
        monitor = cb
        cm.registerNetworkCallback(request, cb)
        refresh()
    }

    /** The first usable (internet, not VPN) network becomes the core's underlay. */
    @Synchronized
    private fun refresh() {
        val best = cm.allNetworks.firstOrNull {
            val c = cm.getNetworkCapabilities(it)
            c != null && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) && !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
        defaultNetwork = best
        val name = best?.let { cm.getLinkProperties(it)?.interfaceName }
        val l = listener ?: return
        if (name == null) {
            l.updateDefaultInterface("", -1, false, false)
        } else {
            val index = java.net.NetworkInterface.getByName(name)?.index ?: -1
            l.updateDefaultInterface(name, index, false, false)
            try { setUnderlyingNetworks(arrayOf(best)) } catch (_: Throwable) {}
        }
    }

    private fun stopMonitor() {
        monitor?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Throwable) {} }
        monitor = null
        listener = null
    }

    override fun closeDefaultInterfaceMonitor(l: InterfaceUpdateListener?) = stopMonitor()

    override fun getInterfaces(): NetworkInterfaceIterator {
        val net = defaultNetwork
        val lp = net?.let { cm.getLinkProperties(it) }
        val caps = net?.let { cm.getNetworkCapabilities(it) }
        val list = ArrayList<io.nekohasekai.libbox.NetworkInterface>()
        for (nic in java.net.NetworkInterface.getNetworkInterfaces().toList()) {
            if (!nic.isUp) continue
            list.add(io.nekohasekai.libbox.NetworkInterface().apply {
                name = nic.name
                index = nic.index
                mtu = nic.mtu
                addresses = Strings(nic.interfaceAddresses.map { "${it.address.hostAddress?.substringBefore('%')}/${it.networkPrefixLength}" })
                flags = (if (nic.isUp) 1 else 0) or (if (nic.isLoopback) 4 else 0) or (if (nic.isPointToPoint) 8 else 0) or (if (nic.supportsMulticast()) 16 else 0)
                type = when {
                    nic.name != lp?.interfaceName -> Libbox.InterfaceTypeOther
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> Libbox.InterfaceTypeWIFI
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> Libbox.InterfaceTypeCellular
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                if (nic.name == lp?.interfaceName) {
                    dnsServer = Strings(lp.dnsServers.mapNotNull { it.hostAddress })
                    metered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
                }
            })
        }
        return object : NetworkInterfaceIterator {
            private val it = list.iterator()
            override fun hasNext() = it.hasNext()
            override fun next() = it.next()
        }
    }

    /** Resolves through the underlying network so the lookup does not enter the tunnel. */
    override fun localDNSTransport(): LocalDNSTransport = object : LocalDNSTransport {
        override fun raw() = false
        override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
            try {
                val net = defaultNetwork
                val all = if (net != null) net.getAllByName(domain) else InetAddress.getAllByName(domain)
                val wanted = all.filter {
                    when (network) {
                        "ip4" -> it is java.net.Inet4Address
                        "ip6" -> it is java.net.Inet6Address
                        else -> true
                    }
                }
                if (wanted.isEmpty()) ctx.errorCode(0) else ctx.success(wanted.joinToString("\n") { it.hostAddress ?: "" })
            } catch (e: java.net.UnknownHostException) {
                ctx.errorCode(3) // NXDOMAIN
            }
        }

        override fun exchange(ctx: ExchangeContext, message: ByteArray) = throw Exception("unsupported")
    }

    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}
    override fun cancelNotification(identifier: String?, typeID: Int) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun registerMyInterface(name: String?) {}
    override fun usePlatformShell() = false
    override fun checkPlatformShell() = throw Exception("unsupported")
    override fun openShellSession(user: PlatformUser?, command: String?, environ: StringIterator?, term: String?, rows: Int, cols: Int): ShellSession =
        throw Exception("unsupported")
    override fun lookupUser(username: String?): PlatformUser = throw Exception("unsupported")
    override fun lookupSFTPServer(): String = throw Exception("unsupported")
    override fun readSystemSSHHostKey(): String = throw Exception("unsupported")
    override fun tailscaleHostname() = ""
    override fun usePlatformBridge() = false
    override fun createBridge(options: BridgeOptions?): BridgeSession = throw Exception("unsupported")
    override fun usePlatformAutoRedirect() = false
    override fun createAutoRedirect(options: ByteArray?, handler: AutoRedirectHandler?): AutoRedirectSession = throw Exception("unsupported")

    // ---------------------------------------------------------------- CommandServerHandler

    override fun serviceStop() { Thread { shutdown("") }.start() }
    override fun serviceReload() {}
    override fun getSystemProxyStatus() = SystemProxyStatus()
    override fun setSystemProxyEnabled(enabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String?) {}
    override fun connectSSHAgent(): Int = throw Exception("unsupported")

    companion object {
        private const val CHANNEL = "singfox_vpn"
    }
}

private class Strings(private val items: List<String>) : StringIterator {
    private var i = 0
    override fun hasNext() = i < items.size
    override fun len() = items.size
    override fun next() = items[i++]
}

private inline fun StringIterator.forEach(f: (String) -> Unit) { while (hasNext()) f(next()) }
private inline fun RoutePrefixIterator.forEach(f: (RoutePrefix) -> Unit) { while (hasNext()) f(next()) }
