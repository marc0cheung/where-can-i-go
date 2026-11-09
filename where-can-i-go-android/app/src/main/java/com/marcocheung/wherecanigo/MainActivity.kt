package com.marcocheung.wherecanigo

import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.marcocheung.wherecanigo.ui.AppState
import com.marcocheung.wherecanigo.ui.WhereCanIGoApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acceptTravelCard(intent)
        enableEdgeToEdge()
        setContent {
            WhereCanIGoApp()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptTravelCard(intent)
    }

    @Suppress("DEPRECATION")
    private fun acceptTravelCard(intent: Intent) {
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri != null) {
            AppState.get(applicationContext).incomingTravelCard = uri
        }
    }
}
