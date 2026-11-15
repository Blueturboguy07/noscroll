package app.noscroll.publik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The app opens only publik's bare in-app pages: no site navigation, footer, prices or plan links. */
class PublikLinksTest {
    @Test
    fun claimUrlGetsInAppFlag() {
        assertEquals("https://publikhq.com/claim/ABC123?in_app=1", Publik.inAppClaimUrl("https://publikhq.com/claim/ABC123"))
    }

    @Test
    fun claimUrlKeepsExistingQueryItems() {
        assertEquals(
            "https://publikhq.com/claim?code=ABC123&app=noscroll&in_app=1",
            Publik.inAppClaimUrl("https://publikhq.com/claim?code=ABC123&app=noscroll"),
        )
        // Encoded values stay exactly as publik sent them.
        assertEquals(
            "https://publikhq.com/claim?next=%2Fwallet%3Fa%3D1&t=a%2Bb&in_app=1",
            Publik.inAppClaimUrl("https://publikhq.com/claim?next=%2Fwallet%3Fa%3D1&t=a%2Bb"),
        )
    }

    @Test
    fun claimUrlReplacesAnOldInAppItemAndKeepsTheFragment() {
        assertEquals("https://publikhq.com/claim/X?k=v&in_app=1#top", Publik.inAppClaimUrl("https://publikhq.com/claim/X?in_app=0&k=v#top"))
        assertEquals("https://publikhq.com/claim/X?in_app=1", Publik.inAppClaimUrl("https://publikhq.com/claim/X?in_app"))
    }

    @Test
    fun claimUrlWithATestOrigin() {
        assertEquals("http://10.0.2.2:8787/claim?in_app=1", Publik.inAppClaimUrl("http://10.0.2.2:8787/claim"))
    }

    @Test
    fun claimUrlRejectsValuesThatAreNotWebAddresses() {
        assertNull(Publik.inAppClaimUrl(""))
        assertNull(Publik.inAppClaimUrl("/claim/ABC"))
        assertNull(Publik.inAppClaimUrl("javascript:alert(1)"))
        assertNull(Publik.inAppClaimUrl("https://"))
    }

    @Test
    fun deleteAccountUrlIsTheInAppPage() {
        assertEquals("https://publikhq.com/in-app/delete-account", Publik.deleteAccountUrl)
    }

    @Test
    fun privacyUrlIsTheInAppPage() {
        assertEquals("https://publikhq.com/in-app/privacy", Publik.privacyUrl)
    }
}
