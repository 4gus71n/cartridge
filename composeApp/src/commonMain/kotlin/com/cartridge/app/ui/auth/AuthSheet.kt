package com.cartridge.app.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.state.AppState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthSheet(state: AppState) {
    if (!state.authVisible) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var signupMode by remember { mutableStateOf(true) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = { state.hideAuth() },
        sheetState = sheetState,
        containerColor = Color(0xFF141419),
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = if (signupMode) "Create your account" else "Welcome back",
                color = Color.White,
                fontWeight = FontWeight.ExtraBold,
                fontSize = 22.sp,
            )
            Text(
                text = "Your likes, saves and collections — synced to every device.",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 13.sp,
            )

            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )

            state.authError?.let { error ->
                Text(text = error, color = Color(0xFFF87171), fontSize = 13.sp)
            }

            Button(
                onClick = { state.authenticate(signupMode, email, password) },
                enabled = !state.authLoading && email.contains("@") && password.length >= 6,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.authLoading) {
                    CircularProgressIndicator(
                        color = Color.White,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(18.dp),
                    )
                } else {
                    Text(if (signupMode) "Sign up" else "Log in")
                }
            }

            TextButton(onClick = { signupMode = !signupMode; }) {
                Text(
                    text = if (signupMode) "I already have an account" else "Create a new account",
                    color = Color(0xFF7CB8FF),
                )
            }
        }
    }
}
