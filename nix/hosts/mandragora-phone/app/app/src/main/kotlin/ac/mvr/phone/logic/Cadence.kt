package ac.mvr.phone.logic

const val HEARTBEAT_MS = 15_000L
const val MPD_IDLE_SHOWN_S = 50
const val MPD_IDLE_AWAY_S = 290

fun configWaitMs(ok: Boolean, misses: Int, shown: Boolean): Long = when {
    !ok && misses < 3 -> 1_000L
    !ok -> 5_000L
    shown -> 30_000L
    else -> 10 * 60_000L
}

fun mediaPolls(shown: Boolean, playerUp: Boolean, screenOn: Boolean): Boolean = shown || (playerUp && screenOn)

fun mediaWaitMs(shown: Boolean, polls: Boolean): Long = when {
    shown -> 5_000L
    polls -> 15_000L
    else -> 10 * 60_000L
}

fun mpdIdleSeconds(shown: Boolean): Int = if (shown) MPD_IDLE_SHOWN_S else MPD_IDLE_AWAY_S
