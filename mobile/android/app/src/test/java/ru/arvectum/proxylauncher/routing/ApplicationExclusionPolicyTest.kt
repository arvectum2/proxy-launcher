package ru.arvectum.proxylauncher.routing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ApplicationExclusionPolicyTest {
    @Test
    fun normalizesDeduplicatesAndSortsPackages() {
        assertEquals(
            listOf("com.example.alpha", "org.example.beta"),
            ApplicationExclusionPolicy.normalizeAll(
                listOf(" org.example.beta ", "com.example.alpha", "org.example.beta"),
            ),
        )
    }

    @Test
    fun malformedPackageIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            ApplicationExclusionPolicy.normalizeAll(listOf("not a package"))
        }
    }

    @Test
    fun entryLimitIsBounded() {
        val entries = (0..ApplicationExclusionPolicy.MAX_ENTRIES)
            .map { "com.example.app$it" }
        assertThrows(IllegalArgumentException::class.java) {
            ApplicationExclusionPolicy.normalizeAll(entries)
        }
    }
}
