package app.noscroll.publik

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Launch-argument hooks are for DEBUG builds only, and sign-out deletes the key file before the revoke call. */
class PublikHooksTest {
    private val extras = mapOf(
        "PUBLIK_SELF_TEST" to "1",
        "PUBLIK_API_BASE_URL" to "http://10.0.2.2:3000/api/v1",
        "PUBLIK_EMPTY" to "",
        "PUBLIK_NULL" to null,
        "OTHER_EXTRA" to "x",
    )

    @Test
    fun releaseBuildIgnoresLaunchArguments() {
        assertTrue(Publik.hookArguments(extras, debug = false).isEmpty())
    }

    @Test
    fun debugBuildKeepsOnlyPublikExtrasWithAValue() {
        assertEquals(
            mapOf("PUBLIK_SELF_TEST" to "1", "PUBLIK_API_BASE_URL" to "http://10.0.2.2:3000/api/v1"),
            Publik.hookArguments(extras, debug = true),
        )
    }

    @Test
    fun forgetKeyDeletesTheFileAndReturnsTheKey() {
        val fakeKey = "pk_" + "fake-for-unit-test" // not a real key
        val file = tempFile("""{"key":"$fakeKey","install_id":"i1"}""")
        assertEquals(fakeKey, Publik.forgetKey(file))
        assertFalse(file.exists())
    }

    @Test
    fun forgetKeyWithNoKeyStillDeletesTheFile() {
        val file = tempFile("{}")
        assertNull(Publik.forgetKey(file))
        assertFalse(file.exists())
    }

    @Test
    fun forgetKeyWithNoFileReturnsNull() {
        val dir = Files.createTempDirectory("publik-hooks").toFile()
        assertNull(Publik.forgetKey(File(dir, "missing.json")))
        dir.deleteRecursively()
    }

    private fun tempFile(text: String): File =
        File.createTempFile("publik-credential", ".json").apply { writeText(text); deleteOnExit() }
}
