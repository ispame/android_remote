package com.openclaw.remote.ui.screen

/**
 * QR Scanner Screen - platform-specific implementation required.
 * Android: CameraX + ZXing
 * iOS: AVFoundation
 */
expect @Composable fun QRScannerScreen(
    onQRCodeScanned: (String) -> Unit,
    onClose: () -> Unit
)
