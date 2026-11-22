package ac.mvr.phone.logic

private val MIRRORED_SUFFIXES = setOf("mp3", "m4a", "flac", "wav", "ogg", "opus", "aac", "wma", "lrc")

data class MirrorFile(val path: String, val size: Long, val mtime: Long)

data class MirrorPlan(
    val fetch: List<MirrorFile>,
    val adopt: List<MirrorFile>,
    val kept: List<MirrorFile>,
    val drop: List<String>,
    val strangers: Int,
)

fun mirroredName(name: String): Boolean =
    !name.startsWith(".") && name.substringAfterLast('.', "").lowercase() in MIRRORED_SUFFIXES

fun mirroredPath(path: String): Boolean {
    val parts = path.split('/')
    return parts.all { it.isNotEmpty() && !it.startsWith(".") } && mirroredName(parts.last())
}

fun mirrorPlan(remote: List<MirrorFile>, local: Map<String, Long>, owned: Map<String, MirrorFile>): MirrorPlan {
    val fetch = ArrayList<MirrorFile>()
    val adopt = ArrayList<MirrorFile>()
    val kept = ArrayList<MirrorFile>()
    val wanted = HashSet<String>()
    for (file in remote.filter { mirroredPath(it.path) }) {
        wanted.add(file.path)
        val here = local[file.path]
        val mine = owned[file.path]
        when {
            here != file.size -> fetch.add(file)
            mine == file -> kept.add(file)
            mine == null -> adopt.add(file)
            else -> fetch.add(file)
        }
    }
    val drop = owned.keys.filter { it !in wanted && it in local }.sorted()
    val strangers = local.keys.count { it !in wanted && it !in owned }
    return MirrorPlan(fetch.sortedByDescending { it.mtime }, adopt, kept, drop, strangers)
}

fun ownedAfter(plan: MirrorPlan, owned: Map<String, MirrorFile>, fetched: Set<String>, dropped: Set<String>): Map<String, MirrorFile> {
    val next = HashMap<String, MirrorFile>()
    (plan.kept + plan.adopt).forEach { next[it.path] = it }
    plan.fetch.forEach { file ->
        when {
            file.path in fetched -> next[file.path] = file
            else -> owned[file.path]?.let { next[file.path] = it }
        }
    }
    plan.drop.filter { it !in dropped }.forEach { path -> owned[path]?.let { next[path] = it } }
    return next
}
