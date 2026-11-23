package uk.splippers.sysmedic

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import java.util.ArrayDeque

/** Lists SysMedic visits announced on this network (_sysmedic._tcp). Tap one to open its phone dashboard. */
class MainActivity : Activity() {
    private val sessions = LinkedHashMap<String, Session>()
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var nsd: NsdManager? = null
    private var multicast: WifiManager.MulticastLock? = null
    private lateinit var empty: TextView
    private lateinit var adapter: Adapter

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val dp = resources.displayMetrics.density
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF021E26.toInt()) }
        val title = TextView(this).apply {
            text = "SysMedic"; textSize = 26f; setTextColor(0xFF39FF88.toInt())
            setPadding((20 * dp).toInt(), (36 * dp).toInt(), (20 * dp).toInt(), (4 * dp).toInt())
        }
        val sub = TextView(this).apply {
            text = "Visits on this network"; textSize = 14f; setTextColor(0xFF8FB8B0.toInt())
            setPadding((20 * dp).toInt(), 0, (20 * dp).toInt(), (12 * dp).toInt())
        }
        empty = TextView(this).apply {
            textSize = 15f; setTextColor(0xFFC8E0DA.toInt()); gravity = Gravity.CENTER
            setPadding((28 * dp).toInt(), (48 * dp).toInt(), (28 * dp).toInt(), 0)
        }
        adapter = Adapter()
        val list = ListView(this).apply {
            this.adapter = this@MainActivity.adapter; divider = null
            setOnItemClickListener { _, _, i, _ -> open(this@MainActivity.adapter.getItem(i)) }
        }
        root.addView(title); root.addView(sub); root.addView(empty); root.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        refresh()
    }

    override fun onResume() { super.onResume(); startDiscovery() }
    override fun onPause() { super.onPause(); stopDiscovery() }

    private fun open(s: Session) =
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(s.url)))       // the browser asks for the access code / QR token

    private fun refresh() {
        adapter.notifyDataSetChanged()
        empty.visibility = if (sessions.isEmpty()) View.VISIBLE else View.GONE
        empty.text = "No SysMedic visits found.\n\nJoin the SysMedic hotspot (or the same network as the drive), " +
            "then run  sysmedic-announce  on it."
    }

    private val listener = object : NsdManager.DiscoveryListener {
        override fun onServiceFound(info: NsdServiceInfo) = runOnUiThread { pending.add(info); next() }
        override fun onServiceLost(info: NsdServiceInfo) = runOnUiThread { sessions.remove(info.serviceName); refresh() }
        override fun onDiscoveryStarted(type: String) {}
        override fun onDiscoveryStopped(type: String) {}
        override fun onStartDiscoveryFailed(type: String, code: Int) {}
        override fun onStopDiscoveryFailed(type: String, code: Int) {}
    }

    /** Android resolves one service at a time; queue them. */
    private fun next() {
        if (resolving) return
        val info = pending.poll() ?: return
        resolving = true
        @Suppress("DEPRECATION")
        nsd?.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(i: NsdServiceInfo, code: Int) = done()
            override fun onServiceResolved(i: NsdServiceInfo) {
                val s = Session.from(i.serviceName, i.host?.hostAddress, i.port, i.attributes)
                runOnUiThread { if (s != null) sessions[i.serviceName] = s; refresh(); done() }
            }
            private fun done() = runOnUiThread { resolving = false; next() }
        })
    }

    private fun startDiscovery() {
        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        multicast = wifi.createMulticastLock("sysmedic").apply { setReferenceCounted(false); acquire() }
        nsd = getSystemService(NSD_SERVICE) as NsdManager
        try { nsd?.discoverServices("_sysmedic._tcp", NsdManager.PROTOCOL_DNS_SD, listener) } catch (_: IllegalArgumentException) {}
    }

    private fun stopDiscovery() {
        try { nsd?.stopServiceDiscovery(listener) } catch (_: IllegalArgumentException) {}
        multicast?.takeIf { it.isHeld }?.release()
        pending.clear(); resolving = false
    }

    private inner class Adapter : BaseAdapter() {
        override fun getCount() = sessions.size
        override fun getItem(i: Int) = sessions.values.toList()[i]
        override fun getItemId(i: Int) = i.toLong()
        override fun getView(i: Int, convert: View?, parent: ViewGroup): View {
            val s = getItem(i)
            val dp = resources.displayMetrics.density
            val row = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
                setPadding((16 * dp).toInt(), (10 * dp).toInt(), (16 * dp).toInt(), (10 * dp).toInt())
            }
            val badge = when (s.editionLabel) { "Caddy" -> R.drawable.badge_caddy; "Stick" -> R.drawable.badge_stick; "Lite" -> R.drawable.badge_lite; else -> R.mipmap.ic_launcher }
            row.addView(ImageView(this@MainActivity).apply { setImageResource(badge) }, LinearLayout.LayoutParams((64 * dp).toInt(), (64 * dp).toInt()))
            val col = LinearLayout(this@MainActivity).apply { orientation = LinearLayout.VERTICAL; setPadding((14 * dp).toInt(), 0, 0, 0) }
            col.addView(TextView(this@MainActivity).apply { text = s.name; textSize = 17f; setTextColor(0xFFFFFFFF.toInt()) })
            col.addView(TextView(this@MainActivity).apply { text = "${s.editionLabel} · ${s.stateLabel}"; textSize = 14f; setTextColor(0xFF39FF88.toInt()) })
            col.addView(TextView(this@MainActivity).apply { text = "${s.host} · v${s.version}"; textSize = 12f; setTextColor(0xFF8FB8B0.toInt()) })
            row.addView(col)
            return row
        }
    }
}
