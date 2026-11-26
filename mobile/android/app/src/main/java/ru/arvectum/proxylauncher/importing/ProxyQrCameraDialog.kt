package ru.arvectum.proxylauncher.importing

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.WindowManager
import android.widget.FrameLayout
import java.util.concurrent.atomic.AtomicBoolean
import ru.arvectum.proxylauncher.R
import ru.arvectum.proxylauncher.model.ImportedProxy
import ru.arvectum.proxylauncher.model.ProxyQrCameraFrame

/** Main-thread camera ownership, one worker for bounded frame decoding. */
class ProxyQrCameraDialog(
    private val activity: Activity,
    private val onClosed: (ProxyQrCameraDialog) -> Unit,
    private val onResult: (List<ImportedProxy>) -> Unit,
    private val onFailure: () -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val delivered = AtomicBoolean(false)
    @Volatile private var closed = false
    private var opening = false
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var previewSurface: Surface? = null
    private var worker: HandlerThread? = null
    private var lastDecode = 0L
    private var sensorOrientation = 0
    private var previewSize: Size? = null
    private val texture = TextureView(activity)
    private val dialog = AlertDialog.Builder(activity)
        .setTitle(R.string.apl_qr_camera_scan)
        .setView(FrameLayout(activity).apply {
            setBackgroundColor(Color.BLACK)
            addView(texture, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (activity.resources.displayMetrics.heightPixels * 0.45f).toInt().coerceAtLeast(1)))
        })
        .setNegativeButton(R.string.apl_cancel_8fbe9, null)
        .create()
    private val timeout = Runnable { fail() }

    fun show() {
        if (closed) return
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        dialog.setOnDismissListener { close() }
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) = open(surface)
            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = transformPreview()
            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                close()
                return true
            }
            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
        try {
            main.postDelayed(timeout, 10000)
            dialog.show()
            dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            if (texture.isAvailable) texture.surfaceTexture?.let(::open)
        } catch (_: Exception) { fail() }
    }

    @SuppressLint("MissingPermission")
    private fun open(surface: SurfaceTexture) {
        if (closed || opening) return
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            fail()
            return
        }
        opening = true
        try {
            val manager = activity.getSystemService(CameraManager::class.java)
            val id = manager.cameraIdList.firstOrNull {
                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            } ?: return fail()
            val info = manager.getCameraCharacteristics(id)
            sensorOrientation = info.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val map = info.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return fail()
            val previewSizes = map.getOutputSizes(SurfaceTexture::class.java)?.toSet().orEmpty()
            val size = map.getOutputSizes(ImageFormat.YUV_420_888).orEmpty()
                .filter { ProxyQrCameraFrame.supportedSize(it.width, it.height) && it in previewSizes }
                .maxByOrNull { it.width.toLong() * it.height } ?: return fail()
            previewSize = size
            surface.setDefaultBufferSize(size.width, size.height)
            transformPreview()
            val preview = Surface(surface).also { previewSurface = it }
            val thread = HandlerThread("apl-qr-frames").apply { start() }.also { worker = it }
            val frames = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
                .also { reader = it }
            frames.setOnImageAvailableListener({ source -> readFrame(source) }, Handler(thread.looper))
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (closed) { device.close(); return }
                    camera = device
                    configure(device, preview, frames, info)
                }
                override fun onDisconnected(device: CameraDevice) { device.close(); fail() }
                override fun onError(device: CameraDevice, error: Int) { device.close(); fail() }
            }, main)
        } catch (_: Exception) { fail() }
    }

    @Suppress("DEPRECATION")
    private fun configure(device: CameraDevice, preview: Surface, frames: ImageReader, info: CameraCharacteristics) {
        if (closed) return
        try {
            device.createCaptureSession(listOf(preview, frames.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    if (closed) { configured.close(); return }
                    session = configured
                    try {
                        val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(preview)
                            addTarget(frames.surface)
                            val modes = info.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
                            if (CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE in modes)
                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        }.build()
                        configured.setRepeatingRequest(request, null, main)
                        main.removeCallbacks(timeout)
                    } catch (_: Exception) { fail() }
                }
                override fun onConfigureFailed(configured: CameraCaptureSession) { configured.close(); fail() }
            }, main)
        } catch (_: Exception) { fail() }
    }

    private fun readFrame(source: ImageReader) {
        try {
            source.acquireLatestImage()?.use { image ->
                if (closed || delivered.get()) return
                val now = SystemClock.elapsedRealtime()
                if (now - lastDecode < 300) return
                lastDecode = now
                val plane = image.planes.firstOrNull() ?: return
                val items = ProxyQrCameraFrame.decode(image.width, image.height,
                    plane.buffer, plane.rowStride, plane.pixelStride) ?: return
                if (delivered.compareAndSet(false, true)) main.post {
                    if (!closed && dialog.isShowing) {
                        close()
                        onResult(items)
                    }
                }
            }
        } catch (_: Exception) {
            // A frame can race with shutdown. Never log frame contents or credentials.
        }
    }

    @Suppress("DEPRECATION")
    private fun transformPreview() {
        val size = previewSize ?: return
        val w = texture.width.toFloat()
        val h = texture.height.toFloat()
        if (w <= 0 || h <= 0) return
        val displayDegrees = when (activity.windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        val rotation = (sensorOrientation - displayDegrees + 360) % 360
        val swap = rotation == 90 || rotation == 270
        val scale = minOf(w / (if (swap) size.height else size.width),
            h / (if (swap) size.width else size.height))
        val radians = Math.toRadians(rotation.toDouble())
        val c = kotlin.math.cos(radians).toFloat()
        val s = kotlin.math.sin(radians).toFloat()
        fun point(x: Float, y: Float): FloatArray {
            val px = (x - w / 2) * size.width / w * scale
            val py = (y - h / 2) * size.height / h * scale
            return floatArrayOf(w / 2 + c * px - s * py, h / 2 + s * px + c * py)
        }
        val dest = point(0f, 0f) + point(w, 0f) + point(0f, h)
        texture.setTransform(Matrix().apply {
            setPolyToPoly(floatArrayOf(0f, 0f, w, 0f, 0f, h), 0, dest, 0, 3)
        })
    }

    private fun fail() {
        if (closed) return
        close()
        onFailure()
    }

    /** Idempotent main-thread cleanup. Late camera/session callbacks close their own objects. */
    fun close() {
        if (closed) return
        closed = true
        main.removeCallbacks(timeout)
        val frames = reader
        reader = null
        runCatching { frames?.setOnImageAvailableListener(null, null) }
        runCatching { session?.stopRepeating() }
        runCatching { session?.close() }
        session = null
        runCatching { camera?.close() }
        camera = null
        runCatching { previewSurface?.release() }
        previewSurface = null
        val thread = worker
        worker = null
        // Close the reader on the frame worker, after an in-flight image is released.
        if (thread != null) {
            val queued = Handler(thread.looper).post { runCatching { frames?.close() } }
            if (!queued) runCatching { frames?.close() }
            thread.quitSafely()
        } else runCatching { frames?.close() }
        texture.surfaceTextureListener = null
        if (dialog.isShowing) dialog.dismiss()
        onClosed(this)
    }
}
