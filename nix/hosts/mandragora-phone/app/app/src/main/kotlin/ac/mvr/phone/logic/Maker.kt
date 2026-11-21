package ac.mvr.phone.logic

enum class Maker { CLAUDE, DEEPSEEK, QWEN, OPENAI, OLLAMA, OPENCODE }

private val BY_MODEL = listOf(
    "deepseek" to Maker.DEEPSEEK,
    "qwen" to Maker.QWEN,
    "gpt" to Maker.OPENAI,
    "claude" to Maker.CLAUDE,
    "fable" to Maker.CLAUDE,
    "opus" to Maker.CLAUDE,
    "sonnet" to Maker.CLAUDE,
    "haiku" to Maker.CLAUDE,
)

private val BY_PROVIDER = mapOf(
    "claude" to Maker.CLAUDE,
    "anthropic" to Maker.CLAUDE,
    "deepseek" to Maker.DEEPSEEK,
    "openai" to Maker.OPENAI,
    "local" to Maker.OLLAMA,
    "ollama" to Maker.OLLAMA,
)

fun makerOf(backend: String, providerID: String?, modelID: String?): Maker? {
    val model = modelID.orEmpty().lowercase()
    return BY_MODEL.firstOrNull { model.contains(it.first) }?.second
        ?: providerID?.lowercase()?.let { BY_PROVIDER[it] }
        ?: Maker.OPENCODE.takeIf { backend == "opencode" }
}
