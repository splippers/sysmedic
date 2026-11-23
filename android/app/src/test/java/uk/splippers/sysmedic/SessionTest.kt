package uk.splippers.sysmedic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class SessionTest {
    private fun txt(vararg p: Pair<String, String>) = p.associate { it.first to it.second.toByteArray() }

    private val good = txt("txtvers" to "1", "edition" to "caddy", "version" to "2026.10.02", "state" to "ready", "scheme" to "https")

    @Test fun parsesAnAnnouncement() {
        val s = Session.from("SysMedic-1a2b3c", "/10.42.0.1", 8443, good)!!
        assertEquals("https://10.42.0.1:8443", s.url)
        assertEquals("Caddy", s.editionLabel)
        assertEquals("Ready, no scan yet", s.stateLabel)
    }

    @Test fun ignoresOtherFormats() {
        assertNull(Session.from("x", "10.0.0.1", 8443, txt("txtvers" to "2", "edition" to "caddy")))
        assertNull(Session.from("x", "10.0.0.1", 8443, txt("edition" to "caddy")))
    }

    @Test fun rejectsBadAddressAndPort() {
        assertNull(Session.from("x", null, 8443, good))
        assertNull(Session.from("x", "  ", 8443, good))
        assertNull(Session.from("x", "10.0.0.1", 0, good))
        assertNull(Session.from("x", "10.0.0.1", 70000, good))
    }

    @Test fun hostileTextCannotShapeTheScreen() {
        val evil = txt("txtvers" to "1", "edition" to "<b>caddy</b>\nclick", "version" to "1".repeat(500), "state" to "ready\u0000")
        val s = Session.from("a\nb<script>", "10.0.0.1", 8443, evil)!!
        assertEquals("SysMedic", s.editionLabel)
        assertEquals(40, s.version.length)
        assertEquals("abscript", s.name)
        assertNotNull(s.state)
    }

    @Test fun knownEditionsGetTheirLabels() {
        fun e(x: String) = Session.from("n", "10.0.0.1", 8443, txt("txtvers" to "1", "edition" to x))!!.editionLabel
        assertEquals("Stick", e("stick")); assertEquals("Lite", e("lite")); assertEquals("Lite", e("stick-lite"))
    }
}
