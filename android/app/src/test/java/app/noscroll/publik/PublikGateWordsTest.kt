package app.noscroll.publik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** The gate's words are the contract (publikhq.com/sdk/publik.swift.md): the same in every publik module. */
class PublikGateWordsTest {
    @Test
    fun signInScreenHasOneWayOn() {
        Publik.appName = "NoScroll"
        val s = Publik.gateScreen("sign_in")
        assertEquals("Sign in with publik", s.title)
        assertEquals(
            "NoScroll uses your publik account. Tap Sign in with publik and sign in on the publik page. Then come back here. NoScroll opens by itself.",
            s.body,
        )
        assertEquals(listOf("sign_in" to "Sign in with publik"), s.buttons)
    }

    @Test
    fun unreachableScreenOffersRetryOnly() {
        val s = Publik.gateScreen("unreachable")
        assertEquals("Sign in with publik", s.title)
        assertEquals("publik is not reachable. Check your connection.", s.body)
        assertEquals(listOf("retry" to "Retry"), s.buttons)
    }

    @Test
    fun planScreensUseTheContractWords() {
        val none = Publik.Wallet(true, null, "mann", "none", null, 0, "https://publikhq.com/wallet")
        val choose = Publik.gateScreen("choose", none)
        assertEquals("Choose how to pay for AI", choose.title)
        assertEquals("You are signed in as @mann. This app uses AI. Get a publik plan, or use your own key.", choose.body)
        assertEquals(listOf("get_plan" to "Get a plan", "own_key" to "Use my own key"), choose.buttons)

        val connect = Publik.gateScreen("choose", none.copy(planKind = "plan", planLabel = "Plus"))
        assertEquals("Connect your plan", connect.title)
        assertEquals("You are signed in as @mann. Your plan: Plus. Connect it to use AI in this app, or use your own key.", connect.body)
        assertEquals(listOf("connect" to "Connect your plan", "own_key" to "Use my own key"), connect.buttons)

        val balance = Publik.gateScreen("choose", none.copy(handle = null, balanceMicros = 2_500_000))
        assertEquals("You are signed in to publik. Your balance: \$2.50. Connect it to use AI in this app, or use your own key.", balance.body)
    }

    @Test
    fun noScrollCallsNoModel() {
        assertEquals("noscroll", Publik.APP_SLUG)
        assertFalse(Publik.USES_AI)
    }
}
