package uk.splippers.sysmedic

/** One SysMedic visit found on the network. Built only from what the drive announces (no code, no customer data). */
data class Session(
    val name: String,
    val host: String,
    val port: Int,
    val edition: String,
    val version: String,
    val state: String,
) {
    /** Where the phone dashboard lives. The access code or QR token is still needed to get in. */
    val url: String get() = "https://$host:$port"

    val editionLabel: String
        get() = when (edition) {
            "caddy" -> "Caddy"
            "stick" -> "Stick"
            "lite", "stick-lite" -> "Lite"
            else -> "SysMedic"
        }

    val stateLabel: String
        get() = when (state) {
            "ready" -> "Ready, no scan yet"
            "scanned" -> "Scanned"
            else -> state.ifEmpty { "Unknown" }
        }

    companion object {
        /** TXT records arrive as bytes; keep only plain, short text so a hostile announcement cannot shape the screen. */
        fun clean(raw: String?, max: Int = 40): String =
            (raw ?: "").filter { it.isLetterOrDigit() || it in " .-_" }.take(max)

        fun from(name: String?, host: String?, port: Int, txt: Map<String, ByteArray>): Session? {
            val cleanHost = host?.removePrefix("/")?.takeIf { it.isNotBlank() } ?: return null
            if (port !in 1..65535) return null
            fun t(key: String) = clean(txt[key]?.toString(Charsets.UTF_8))
            if (txt["txtvers"]?.toString(Charsets.UTF_8) != "1") return null      // not ours, or a newer format
            return Session(clean(name).ifEmpty { "SysMedic" }, cleanHost, port, t("edition"), t("version"), t("state"))
        }
    }
}
