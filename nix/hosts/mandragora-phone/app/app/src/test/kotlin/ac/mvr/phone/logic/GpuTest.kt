package ac.mvr.phone.logic

import ac.mvr.phone.net.GpuInfo
import ac.mvr.phone.net.GpuLock
import ac.mvr.phone.net.GpuParty
import ac.mvr.phone.net.GpuResident
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GpuTest {
    private val mib = 1024L * 1024L

    @Test
    fun vramReadsAsUsedOfTotal() {
        val info = GpuInfo(memUsed = 10585 * mib, memTotal = 16303 * mib, util = 42.7, temp = 55.2)
        assertEquals("10.3 of 15.9 G", vramLabel(info))
        assertEquals(0.649f, vramShare(info), 0.001f)
        assertEquals(0f, vramShare(GpuInfo()))
        assertEquals("42% busy · 55°C", gpuSubtitle(info))
        assertNull(gpuSubtitle(null))
    }

    @Test
    fun theLockLineNamesWhoHoldsIt() {
        val held = GpuLock(holder = GpuParty("phone-ask", 9, since = 1000.0, expected = 300.0))
        assertEquals("held by phone-ask for 40 s · about 4 min left", lockLabel(held, 1040.0))
        assertEquals("held by phone-ask for 6 min", lockLabel(held, 1360.0))
        assertEquals("forzahorizon6.exe uses it outside the lock", lockLabel(GpuLock(unmanaged = GpuParty("forzahorizon6.exe")), 0.0))
        assertEquals("gpu-lock did not answer", lockLabel(GpuLock(error = "x"), 0.0))
        assertEquals("the lock is free", lockLabel(GpuLock(), 0.0))
    }

    @Test
    fun theFreeButtonSumsWhatItWouldUnload() {
        val residents = listOf(GpuResident("ollama", "qwen3:8b", 5L * 1024 * mib), GpuResident("stt", "stt-core · large-v3", 3900 * mib))
        assertEquals("free qwen3:8b + whisper · 8.8 G", freeLabel(residents))
        assertNull(freeLabel(emptyList()))
    }
}
