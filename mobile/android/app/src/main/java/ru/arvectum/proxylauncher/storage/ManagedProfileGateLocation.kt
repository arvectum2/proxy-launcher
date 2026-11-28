package ru.arvectum.proxylauncher.storage

import android.content.Context

/** Both processes must resolve the same app-private stable lock directory. */
internal fun managedProfileGate(context: Context): ManagedCrashGate =
    ManagedCrashGate(context.applicationContext.noBackupFilesDir.toPath().resolve("managed-profile-gate"))
