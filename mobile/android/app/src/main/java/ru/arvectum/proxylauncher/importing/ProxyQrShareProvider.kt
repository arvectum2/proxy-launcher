package ru.arvectum.proxylauncher.importing

import android.content.ClipData
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.system.ErrnoException
import android.system.OsConstants
import android.os.SystemClock
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import ru.arvectum.proxylauncher.model.ExpiringQrShare

/** One in-memory QR PNG, accessible only to Android's temporary URI-grant recipients. */
class ProxyQrShareProvider : ContentProvider() {
    companion object {
        private val store = ExpiringQrShare(SystemClock::elapsedRealtime)
        private val main = Handler(Looper.getMainLooper())
        private var current: Uri? = null
        private val reads by lazy {
            Handler(HandlerThread("apl-qr-share").apply { start() }.looper)
        }

        private fun authority(context: Context) = context.packageName + ".qrshare"

        // Called from the UI thread only, after the second explicit disclosure confirmation.
        fun prepare(context: Context, bitmap: Bitmap): Intent? {
            if (bitmap.width !in 1..1024 || bitmap.height !in 1..1024) return null
            val bytes = ByteArrayOutputStream().use { stream ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) return null
                stream.toByteArray()
            }
            val token = try {
                if (bytes.size > ExpiringQrShare.MAX_BYTES) return null
                current?.let { revoke(context, it) }
                store.issue(bytes) ?: return null
            } finally { bytes.fill(0) }
            val uri = Uri.Builder().scheme("content").authority(authority(context))
                .appendPath(token).build()
            current = uri
            val app = context.applicationContext
            main.postDelayed({ revoke(app, uri) }, ExpiringQrShare.TTL_MS)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData("QR", arrayOf("image/png"), ClipData.Item(uri))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            return Intent.createChooser(send, null).apply {
                clipData = send.clipData
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }

        fun revokeCurrent(context: Context) {
            current?.let { revoke(context, it) }
        }

        private fun revoke(context: Context, uri: Uri) {
            uri.lastPathSegment?.let(store::clear)
            runCatching { context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            if (current == uri) current = null
        }
    }

    override fun onCreate() = true

    private fun token(uri: Uri): String {
        val app = context ?: throw FileNotFoundException()
        val parts = uri.pathSegments
        if (uri.scheme != "content" || uri.authority != authority(app) ||
            uri.query != null || uri.fragment != null || parts.size != 1) throw FileNotFoundException()
        return parts.single()
    }

    override fun getType(uri: Uri): String? =
        if (runCatching { store.size(token(uri)) }.getOrNull() != null) "image/png" else null

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val length = runCatching { store.size(token(uri)) }.getOrNull() ?: return null
        val columns = projection?.toList()?.toTypedArray() ?:
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(columns.map {
                when (it) {
                    OpenableColumns.DISPLAY_NAME -> "proxy-qr.png"
                    OpenableColumns.SIZE -> length
                    else -> null
                }
            })
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        val payloadToken = token(uri)
        if (store.size(payloadToken) == null) throw FileNotFoundException()
        val storage = context?.getSystemService(StorageManager::class.java)
            ?: throw FileNotFoundException()
        return storage.openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY,
            object : ProxyFileDescriptorCallback() {
                override fun onGetSize(): Long = store.size(payloadToken)?.toLong()
                    ?: throw ErrnoException("QR unavailable", OsConstants.ENOENT)

                override fun onRead(offset: Long, size: Int, data: ByteArray): Int =
                    store.readInto(payloadToken, offset, size, data)
                        ?: throw ErrnoException("QR unavailable", OsConstants.ENOENT)

                override fun onRelease() = Unit
            }, reads)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
}
