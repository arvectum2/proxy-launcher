package ru.arvectum.proxylauncher.model

import org.junit.Assert.*
import org.junit.Test

class ExpiringQrShareTest {
    @Test fun expiresAtBoundaryAndRejectsUnknownToken() {
        var now = 10L
        val share = ExpiringQrShare { now }
        val token = share.issue(byteArrayOf(1,2,3))!!
        assertNull(share.read("wrong"))
        now += ExpiringQrShare.TTL_MS - 1
        assertEquals(3, share.size(token))
        now++
        assertNull(share.read(token))
        assertNull(share.size(token))
    }

    @Test fun replacementAndScopedCleanup() {
        val share = ExpiringQrShare { 0 }
        val first = share.issue(byteArrayOf(1))!!
        val second = share.issue(byteArrayOf(2))!!
        assertNotEquals(first, second)
        assertNull(share.read(first))
        share.clear(first)
        assertArrayEquals(byteArrayOf(2), share.read(second))
        share.clear(second)
        assertNull(share.read(second))
    }

    @Test fun readsAreBoundedAndRecheckedAfterExpiry() {
        var now = 0L
        val share = ExpiringQrShare { now }
        val token = share.issue(byteArrayOf(1,2,3,4))!!
        val out = ByteArray(3)
        assertEquals(2, share.readInto(token, 2, 3, out))
        assertArrayEquals(byteArrayOf(3,4,0), out)
        assertEquals(0, share.readInto(token, Long.MAX_VALUE, 1, out))
        assertNull(share.readInto(token, -1, 1, out))
        assertNull(share.readInto(token, 0, 4, out))
        now = ExpiringQrShare.TTL_MS
        assertNull(share.readInto(token, 0, 1, out))
    }

    @Test fun boundedDefensiveCopiesAndNoPersistentState() {
        val share = ExpiringQrShare { 0 }
        assertNull(share.issue(byteArrayOf()))
        assertNull(share.issue(ByteArray(ExpiringQrShare.MAX_BYTES + 1)))
        val input = byteArrayOf(1,2)
        val token = share.issue(input)!!
        input.fill(0)
        share.read(token)!!.fill(0)
        assertArrayEquals(byteArrayOf(1,2), share.read(token))
        assertNull(ExpiringQrShare { 0 }.read(token))
    }
}
