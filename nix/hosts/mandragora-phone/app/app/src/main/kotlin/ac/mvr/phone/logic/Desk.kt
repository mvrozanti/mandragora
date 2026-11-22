package ac.mvr.phone.logic

import ac.mvr.phone.net.CodeSession
import ac.mvr.phone.net.CodeStatus
import ac.mvr.phone.net.DesktopMedia

fun active(session: CodeSession, status: CodeStatus?): Boolean =
    session.live != null || status?.type == "busy" || status?.message == "waiting"

fun inBackground(session: CodeSession?): String? =
    session?.live?.background?.filter { it.isNotBlank() }?.takeIf { it.isNotEmpty() }?.joinToString(", ")

fun withBackground(session: CodeSession, tasks: List<String>): CodeSession =
    if (session.live == null) session else session.copy(live = session.live.copy(background = tasks)).also { it.backend = session.backend }

fun resumes(action: String, player: String, players: List<DesktopMedia>): Boolean =
    action == "play" || (action == "play-pause" && players.none { it.player == player && it.playing })

data class LockScreen(val showDesk: Boolean, val bind: String?, val beside: DesktopMedia?)

fun lockScreen(musicOn: Boolean, players: List<DesktopMedia>, showingDesk: Boolean, bound: String?): LockScreen {
    val deskOn = players.firstOrNull { it.playing }
    val showDesk = when {
        musicOn -> false
        deskOn != null -> true
        else -> showingDesk && players.any { it.player == bound }
    }
    return LockScreen(
        showDesk = showDesk,
        bind = if (!musicOn) deskOn?.player else null,
        beside = if (musicOn) deskOn else null,
    )
}
