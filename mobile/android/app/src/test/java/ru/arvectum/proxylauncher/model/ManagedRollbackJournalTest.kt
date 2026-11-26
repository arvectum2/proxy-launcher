package ru.arvectum.proxylauncher.model

import java.util.Base64
import javax.crypto.KeyGenerator
import org.junit.Assert.*
import org.junit.Test

class ManagedRollbackJournalTest {
    private val source=SavedSubscriptionCatalog.metadata("https://supplier.example.com/list",1)
    private val selection=ManagedSelection(null,null,null,null,null,false)
    private fun key()=KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private fun row(id:String,host:String,owner:String?=source.id,cipher:String?=null)=
        ManagedProfileRow(ProxyProfile(id,host,host,80,ProxyType.HTTP,
            cipher?.let{"user"},cipher?.let{"android-keystore:$id"}),owner,cipher)
    private fun invalid(block:()->Unit) {
        try { block(); fail("Expected rejection") } catch (_:Exception) {}
    }

    @Test fun encryptedRoundtripRestoresOnlyTouchedRows() {
        val manual=row("manual","manual.invalid",null)
        val before=ManagedProfileState(listOf(manual,row("update","a.invalid",cipher="old-cipher"),
            row("remove","b.invalid")),selection)
        val after=ManagedProfileState(listOf(manual,row("update","a.invalid",cipher="new-cipher"),
            row("added","c.invalid")),selection)
        val transaction=ManagedRefreshTransaction(source,before,after,setOf("update","remove","added"))
        val k=key()
        val journal=ManagedRollbackJournal.from(transaction)
        val sealed=journal.seal(k)
        assertFalse(String(Base64.getDecoder().decode(sealed),Charsets.ISO_8859_1).contains("old-cipher"))
        assertNotEquals(sealed,journal.seal(k))
        assertEquals(before,ManagedRollbackJournal.open(sealed,k).restore(source,after,true))
        assertFalse(journal.toString().contains("old-cipher"))
    }

    @Test fun rejectsTamperingWrongKeyAndStaleState() {
        val before=ManagedProfileState(listOf(row("update","a.invalid",cipher="old")),selection)
        val after=ManagedProfileState(listOf(row("update","a.invalid",cipher="new")),selection)
        val k=key()
        val sealed=ManagedRollbackJournal.from(ManagedRefreshTransaction(source,before,after,setOf("update"))).seal(k)
        invalid { ManagedRollbackJournal.open(sealed,key()) }
        val raw=Base64.getDecoder().decode(sealed);raw[raw.lastIndex]=(raw.last().toInt() xor 1).toByte()
        invalid { ManagedRollbackJournal.open(Base64.getEncoder().encodeToString(raw),k) }
        val j=ManagedRollbackJournal.open(sealed,k)
        assertNull(j.restore(source,before,true))
        assertNull(j.restore(null,after,true))
        assertNull(j.restore(source,after,false))
        assertNull(j.restore(source,ManagedProfileState(after.rows,selection.copy(auto=true)),true))
        assertNull(j.restore(source,ManagedProfileState(after.rows+row("manual","manual.invalid",null),selection),true))
    }

    @Test fun rejectsForgedChangeSetForeignRowsAndProtectedRows() {
        val old=ManagedProfileState(listOf(row("old","a.invalid",null)),selection)
        val changed=ManagedProfileState(listOf(row("old","b.invalid",null)),selection)
        invalid { ManagedRollbackJournal.from(ManagedRefreshTransaction(source,old,changed,setOf("old"))) }
        val before=ManagedProfileState(listOf(row("owned","a.invalid")),selection)
        val after=ManagedProfileState(listOf(row("owned","b.invalid")),selection)
        invalid { ManagedRollbackJournal.from(ManagedRefreshTransaction(source,before,after,emptySet())) }
        val p=selection.copy(primary="owned")
        invalid { ManagedRollbackJournal.from(ManagedRefreshTransaction(source,ManagedProfileState(before.rows,p),
            ManagedProfileState(after.rows,p),setOf("owned"))) }
        invalid { ManagedRollbackJournal.open("A".repeat(3_000_000),key()) }
    }
}
