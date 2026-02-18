package com.recorderphone

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.recorderphone.ui.screens.TodayScreen
import com.recorderphone.ui.theme.RecorderTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            RecorderTheme {
                TodayScreen()
            }
        }
    }
}

