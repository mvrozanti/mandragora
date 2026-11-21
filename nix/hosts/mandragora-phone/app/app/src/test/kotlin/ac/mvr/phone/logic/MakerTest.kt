package ac.mvr.phone.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MakerTest {

    @Test
    fun theModelNamesItsMaker() {
        assertEquals(Maker.CLAUDE, makerOf("claude", "claude", "claude-opus-5-5"))
        assertEquals(Maker.CLAUDE, makerOf("claude", "claude", "fable"))
        assertEquals(Maker.DEEPSEEK, makerOf("claude", "deepseek", "deepseek-v4-pro"))
        assertEquals(Maker.QWEN, makerOf("claude", "local", "cc-qwen3.6"))
        assertEquals(Maker.OPENAI, makerOf("claude", "local", "cc-gptoss"))
        assertEquals(Maker.QWEN, makerOf("opencode", "ollama", "Qwen3-Coder:30b"))
    }

    @Test
    fun anUnnamedModelFallsBackToItsProviderThenItsBackend() {
        assertEquals(Maker.CLAUDE, makerOf("claude", "claude", "default"))
        assertEquals(Maker.OLLAMA, makerOf("claude", "local", "llama3"))
        assertEquals(Maker.DEEPSEEK, makerOf("claude", "deepseek", null))
        assertEquals(Maker.OPENCODE, makerOf("opencode", "opencode", "big-pickle"))
        assertEquals(Maker.OPENCODE, makerOf("opencode", null, null))
    }

    @Test
    fun nothingKnownDrawsNothing() {
        assertNull(makerOf("claude", null, null))
        assertNull(makerOf("", "mystery", "model-x"))
    }
}
