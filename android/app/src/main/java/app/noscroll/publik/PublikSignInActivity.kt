package app.noscroll.publik

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/**
 * Optional gate mode: "Sign in with publik" on the Status screen opens this screen. It runs the same
 * gate as required mode and closes at sign-in. Back closes it without sign-in; the app still works.
 */
class PublikSignInActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val gate = PublikGateView(this)
        setContentView(gate.view)
        lifecycleScope.launch {
            Publik.ensureSignedIn(this@PublikSignInActivity, gate)
            finish()
        }
    }
}
