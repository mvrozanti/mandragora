package ac.mvr.phone.logic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivateTest {

    private val folder = "/home/m/.local/share/slot/chat"

    @Test
    fun thePluginFolderAndWhatIsInsideItAreHidden() {
        assertTrue(privateFolder(folder, folder))
        assertTrue(privateFolder("$folder/", folder))
        assertTrue(privateFolder("$folder/notes", "$folder/"))
    }

    @Test
    fun neighboursAndUnsetFoldersStayVisible() {
        assertFalse(privateFolder("/home/m/.local/share/slot/chatter", folder))
        assertFalse(privateFolder("/home/m/Projects/x", folder))
        assertFalse(privateFolder(folder, null))
        assertFalse(privateFolder("/", ""))
    }
}
