package ac.mvr.phone

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ManifestQueriesTest {
    private val manifest = File("src/main/AndroidManifest.xml").readText()

    @Test
    fun everyAppTheIdentityExpectsIsVisibleWithoutQueryingAllPackages() {
        val identity = Json.parseToJsonElement(File("../../identity.json").readText()).jsonObject
        val expected = identity.getValue("apps").jsonArray.map { it.jsonObject.getValue("package").jsonPrimitive.content }
        val queries = Regex("""<queries>(.*?)</queries>""", RegexOption.DOT_MATCHES_ALL).find(manifest)?.groupValues?.get(1).orEmpty()
        val visible = Regex("""<package\s+android:name="([^"]+)"""").findAll(queries).map { it.groupValues[1] }.toSet()
        assertTrue("identity.json apps missing from <queries>: ${expected - visible}", visible.containsAll(expected))
    }

    @Test
    fun theAppDoesNotAskToSeeEveryInstalledPackage() {
        assertFalse(manifest.contains("QUERY_ALL_PACKAGES"))
    }
}
