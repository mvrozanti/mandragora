package ac.mvr.phone.logic

fun uptimeLabel(seconds: Double): String {
    val minutes = (seconds / 60).toLong()
    val hours = minutes / 60
    val days = hours / 24
    return when {
        days > 0 -> "up $days d ${hours % 24} h"
        hours > 0 -> "up $hours h ${minutes % 60} min"
        else -> "up $minutes min"
    }
}
