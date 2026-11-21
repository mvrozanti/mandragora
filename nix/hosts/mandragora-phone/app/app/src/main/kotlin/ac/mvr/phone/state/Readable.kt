package ac.mvr.phone.state

import java.io.IOException

private val SAID_ERROR = Regex("\"error\":\\s*\"([^\"]+)\"")

suspend fun <T> readable(call: suspend () -> T): T = try {
    call()
} catch (err: IOException) {
    val message = SAID_ERROR.find(err.message ?: "")?.groupValues?.get(1) ?: throw err
    throw IllegalStateException(message, err)
}
