package ru.arvectum.proxylauncher.model

import java.util.Base64
import javax.crypto.KeyGenerator
import org.junit.Assert.*
import org.junit.Test

class SavedSubscriptionTest {
    private val url = "https://supplier.example.com/list?token=synthetic-private-token"
    private fun key() = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    private fun meta() = SavedSubscriptionCatalog.metadata(url,1)
    private fun invalid(block: () -> Unit) {
        try { block(); fail("Expected rejection") } catch (_: Exception) {}
    }

    @Test fun encryptedRoundTripAndMetadataOnly() {
        val k=key(); val m=meta()
        val e=SavedSubscriptionCatalog.seal(m,url,k)
        val stored=SavedSubscriptionCatalog.encode(listOf(e))
        assertFalse(String(Base64.getDecoder().decode(stored),Charsets.ISO_8859_1).contains("synthetic-private-token"))
        assertEquals("supplier.example.com",m.host)
        assertEquals(m,SavedSubscriptionCatalog.decode(stored).single().metadata)
        assertEquals(url,SavedSubscriptionCatalog.open(SavedSubscriptionCatalog.decode(stored).single(),k))
        assertNotEquals(e.encrypted,SavedSubscriptionCatalog.seal(m,url,k).encrypted)
        assertFalse(e.toString().contains("synthetic-private-token"))
    }

    @Test fun wrongKeyTamperingAndIdentitySwapRejected() {
        val k=key(); val m=meta(); val e=SavedSubscriptionCatalog.seal(m,url,k)
        invalid { SavedSubscriptionCatalog.open(e,key()) }
        val bytes=Base64.getDecoder().decode(e.encrypted); bytes[bytes.lastIndex]=(bytes.last().toInt() xor 1).toByte()
        invalid { SavedSubscriptionCatalog.open(SavedSubscriptionEntry(m,Base64.getEncoder().encodeToString(bytes)),k) }
        invalid { SavedSubscriptionCatalog.open(SavedSubscriptionEntry(meta(),e.encrypted),k) }
        invalid { SavedSubscriptionCatalog.open(SavedSubscriptionEntry(m.copy(host="different.example.com"),e.encrypted),k) }
        invalid { SavedSubscriptionCatalog.open(SavedSubscriptionEntry(m.copy(createdAt=2),e.encrypted),k) }
    }

    @Test fun catalogLimitsAndMalformedData() {
        val k=key()
        val entries=List(12){SavedSubscriptionCatalog.seal(meta(),url,k)}
        assertEquals(12,SavedSubscriptionCatalog.decode(SavedSubscriptionCatalog.encode(entries)).size)
        invalid { SavedSubscriptionCatalog.encode(entries+SavedSubscriptionCatalog.seal(meta(),url,k)) }
        invalid { SavedSubscriptionCatalog.encode(listOf(entries[0],entries[0])) }
        invalid { SavedSubscriptionCatalog.decode("A".repeat(100000)) }
        invalid { SavedSubscriptionCatalog.decode("not-base64!") }
        val bytes=Base64.getDecoder().decode(SavedSubscriptionCatalog.encode(entries))
        invalid { SavedSubscriptionCatalog.decode(Base64.getEncoder().encodeToString(bytes+byteArrayOf(0))) }
        assertTrue(SavedSubscriptionCatalog.decode(SavedSubscriptionCatalog.encode(emptyList())).isEmpty())
    }

    @Test fun additiveReviewAndConflictingRows() {
        val m=meta()
        val old=ProxyProfile("old","Old","a.invalid",80,ProxyType.HTTP,"u")
        val items=listOf(ProxyImport.parse("http://u:changed@a.invalid:80")!!,ProxyImport.parse("b.invalid:80")!!)
        val review=SavedSubscriptionReview.prepare(m,items,listOf(old)){0L}!!
        assertEquals(2,review.received)
        assertEquals(1,review.preview.skipped)
        assertEquals("b.invalid",review.confirm(m,listOf(old),true)!!.single().host)
        assertNull(review.confirm(m,listOf(old),true))
        val conflict=items+ProxyImport.parse("http://u:another@a.invalid:80")!!
        assertNull(SavedSubscriptionReview.prepare(m,conflict,listOf(old)){0L})
    }

    @Test fun expiredCanceledStaleAndBackgroundReviews() {
        val m=meta()
        val items=listOf(ProxyImport.parse("b.invalid:80")!!)
        var now=1L
        fun prepare()=SavedSubscriptionReview.prepare(m,items,emptyList()){now}!!
        val expired=prepare();now+=SavedSubscriptionReview.TTL_MS
        assertNull(expired.confirm(m,emptyList(),true))
        val canceled=prepare();canceled.cancel();assertNull(canceled.confirm(m,emptyList(),true))
        assertNull(prepare().confirm(null,emptyList(),true))
        assertNull(prepare().confirm(m,emptyList(),false))
        assertNull(prepare().confirm(m,listOf(ProxyProfile("new","New","c.invalid",80,ProxyType.HTTP)),true))
    }
}
