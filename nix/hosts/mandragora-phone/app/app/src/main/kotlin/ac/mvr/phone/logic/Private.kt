package ac.mvr.phone.logic

fun privateFolder(directory: String, hidden: String?): Boolean {
    val root = hidden?.trimEnd('/')?.ifEmpty { null } ?: return false
    val dir = directory.trimEnd('/')
    return dir == root || dir.startsWith("$root/")
}
