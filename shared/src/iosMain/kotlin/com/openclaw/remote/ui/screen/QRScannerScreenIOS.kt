package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.interop.UIKitView
import platform.AVFoundation.*
import platform.CoreGraphics.*
import platform.UIKit.*

@Composable
actual fun QRScannerScreen(
    onQRCodeScanned: (String) -> Unit,
    onClose: () -> Unit
) {
    var hasPermission by remember { mutableStateOf(false) }
    var isCheckingPermission by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        when AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {
            AVAuthorizationStatusAuthorized -> hasPermission = true
            AVAuthorizationStatusNotDetermined -> {
                hasPermission = AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo)
            }
            else -> hasPermission = false
        }
        isCheckingPermission = false
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        if (isCheckingPermission) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = Color.White
            )
        } else if (hasPermission) {
            QRScannerView(
                onQRCodeScanned = onQRCodeScanned,
                modifier = Modifier.fillMaxSize()
            )

            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "关闭",
                    tint = Color.White
                )
            }

            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .size(250.dp)
                        .background(Color.Transparent)
                )
            }

            Text(
                text = "将 QR 码放入框内",
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 100.dp)
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "相机权限被拒绝，请在设置中开启",
                    color = Color.White
                )
                Spacer(modifier = Modifier.height(16.dp))
                Button(onClick = onClose) {
                    Text("返回")
                }
            }
        }
    }
}

@Composable
private fun QRScannerView(
    onQRCodeScanned: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var lastScannedValue by remember { mutableStateOf<String?>(null) }

    UIKitView(
        factory = { context ->
            val view = UIView()
            view.backgroundColor = UIColor.blackColor

            let { _ ->
                val captureSession = AVCaptureSession()
                val videoPreviewLayer = AVCaptureVideoPreviewLayer.alloc().initWithSession(captureSession)
                videoPreviewLayer.frame = CGRectMake(0, 0, UIScreen.main.bounds.width, UIScreen.main.bounds.height)
                videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
                view.layer.addSublayer(videoPreviewLayer)

                val device = AVCaptureDevice.defaultForMediaType(AVMediaTypeVideo)
                if (device != null) {
                    val input = AVCaptureDeviceInput.deviceInputWithDevice(device, error = null)
                    if (input != null && captureSession.canAddInput(input)) {
                        captureSession.addInput(input)

                        val metadataOutput = AVCaptureMetadataOutput()
                        if (captureSession.canAddOutput(metadataOutput)) {
                            captureSession.addOutput(metadataOutput)
                            metadataOutput.setMetadataObjectsDelegate(object : AVCaptureMetadataOutputObjectsDelegate {
                                override fun captureOutput(
                                    output: AVCaptureOutput,
                                    didOutputMetadataObjects: List<*>,
                                    fromConnection: AVCaptureConnection
                                ) {
                                    for (metadata in didOutputMetadataObjects) {
                                        if (metadata is AVMetadataMachineReadableCodeObject) {
                                            val result = metadata.stringValue
                                            if (result != null && result != lastScannedValue) {
                                                lastScannedValue = result
                                                onQRCodeScanned(result)
                                            }
                                        }
                                    }
                                }
                            }, queue = DispatchQueue.mainQueue)
                            metadataOutput.metadataObjectTypes = listOf(AVMetadataObjectTypeQRCode)
                        }
                    }
                }

                DispatchQueue.global(DispatchQueue.global_qos_class).async {
                    captureSession.startRunning()
                }
            }

            view
        },
        modifier = modifier
    )
}
