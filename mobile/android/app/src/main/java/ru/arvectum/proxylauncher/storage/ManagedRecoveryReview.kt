package ru.arvectum.proxylauncher.storage

import javax.crypto.SecretKey

/** One-shot acknowledgement of a fully recognized durable state, never a data rewrite. */
internal class ManagedRecoveryReview private constructor(
    private val marker: ByteArray,
    val state: ManagedRecoveryEvidence.State,
    private val started: Long,
    private val elapsed: () -> Long,
) {
    private var consumed=false
    override fun toString()="ManagedRecoveryReview(state=$state)"

    @Synchronized
    fun cancel() { consumed=true }

    @Synchronized
    fun confirm(gate: ManagedCrashGate,key: ()->SecretKey,readDurable: ()->Map<String,Any>,
                allowed: ()->Boolean): Boolean {
        if(consumed) return false
        consumed=true
        if(!runCatching { allowed() && elapsed()-started in 0 until TTL_MS }.getOrDefault(false)) return false
        return gate.acknowledgePending(marker) { current ->
            allowed() && elapsed()-started in 0 until TTL_MS &&
                ManagedRecoveryEvidence.open(current,key()).classify(readDurable())==state &&
                allowed() && elapsed()-started in 0 until TTL_MS
        }
    }

    companion object {
        const val TTL_MS=300_000L

        fun prepare(gate:ManagedCrashGate,key:()->SecretKey,readDurable:()->Map<String,Any>,
                    elapsed:()->Long,allowed:()->Boolean):ManagedRecoveryReview? {
            if(!runCatching(allowed).getOrDefault(false)) return null
            var review:ManagedRecoveryReview?=null
            val classified=gate.inspectPending { payload ->
                if(!allowed()) return@inspectPending ManagedRecoveryEvidence.State.UNKNOWN
                val state=ManagedRecoveryEvidence.open(payload,key()).classify(readDurable())
                val now=elapsed()
                if(state!=ManagedRecoveryEvidence.State.UNKNOWN && now>=0 && allowed())
                    review=ManagedRecoveryReview(payload.copyOf(),state,now,elapsed)
                state
            }
            return review?.takeIf { it.state==classified }
        }
    }
}
