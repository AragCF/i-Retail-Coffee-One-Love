package com.skytech.smartskyposclient

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import com.skytech.smartskyposlib.ISmartSkyPos

/**
 * Recovered from SmartSkyPOS 1.9.19-RC.1.11057 on Kozen P12.
 * This helper only binds/unbinds. It does not initiate any financial operation.
 */
class SmartSkyPosConnector(
    private val context: Context,
    private val onConnected: (ISmartSkyPos) -> Unit,
    private val onDisconnected: () -> Unit = {}
) {
    private var bound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            bound = true
            onConnected(ISmartSkyPos.Stub.asInterface(service))
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            bound = false
            onDisconnected()
        }
    }

    fun bind(): Boolean {
        val intent = Intent(ACTION).apply {
            component = ComponentName(PACKAGE, SERVICE)
        }
        return context.bindService(intent, connection, Context.BIND_AUTO_CREATE).also { bound = it }
    }

    fun unbind() {
        if (bound) {
            context.unbindService(connection)
            bound = false
        }
    }

    companion object {
        const val ACTION = "com.skytech.smartskypos.ISmartSkyPos"
        const val PACKAGE = "com.skytech.smartskypos"
        const val SERVICE = "com.crestwavetech.smartskyposservice.SmartSkyPosService"
        const val BINDER_DESCRIPTOR = "com.skytech.smartskyposlib.ISmartSkyPos"
    }
}
