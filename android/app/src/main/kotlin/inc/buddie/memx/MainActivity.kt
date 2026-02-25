package inc.buddie.memx

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val HEADSET_CHANNEL = "inc.buddie.memx/headset"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEADSET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getHeadsetStatus" -> result.success(getHeadsetStatus())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun getConnectedProfileDevices(
        bluetoothManager: BluetoothManager
    ): List<BluetoothDevice> {
        val devicesByAddress = LinkedHashMap<String, BluetoothDevice>()

        fun addProfile(profile: Int) {
            try {
                bluetoothManager.getConnectedDevices(profile).forEach { device ->
                    devicesByAddress[device.address] = device
                }
            } catch (_: Throwable) {
            }
        }

        addProfile(BluetoothProfile.HEADSET)
        addProfile(BluetoothProfile.A2DP)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            addProfile(BluetoothProfile.HEARING_AID)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            addProfile(BluetoothProfile.LE_AUDIO)
        }

        return devicesByAddress.values.toList()
    }

    private fun isAudioRoutedToBluetooth(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            return devices.any { info ->
                when (info.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> true
                    AudioDeviceInfo.TYPE_HEARING_AID -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    AudioDeviceInfo.TYPE_BLE_HEADSET -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                    else -> false
                }
            }
        }

        @Suppress("DEPRECATION")
        return audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn
    }

    private fun safeDeviceName(device: BluetoothDevice): String {
        return try {
            if (hasBluetoothConnectPermission()) {
                val raw = device.name
                if (!raw.isNullOrBlank()) raw else device.address
            } else {
                device.address
            }
        } catch (_: Throwable) {
            device.address
        }
    }

    private fun getHeadsetStatus(): Map<String, Any?> {
        val bluetoothManager =
            getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                ?: return mapOf(
                    "connected" to false,
                    "name" to null,
                    "devices" to emptyList<String>(),
                    "bluetoothEnabled" to false,
                    "routedToBluetooth" to false,
                    "reason" to "bluetooth_manager_unavailable",
                )

        val adapter: BluetoothAdapter = bluetoothManager.adapter
            ?: return mapOf(
                "connected" to false,
                "name" to null,
                "devices" to emptyList<String>(),
                "bluetoothEnabled" to false,
                "routedToBluetooth" to false,
                "reason" to "bluetooth_not_supported",
            )

        val bluetoothEnabled = adapter.isEnabled
        if (!bluetoothEnabled) {
            return mapOf(
                "connected" to false,
                "name" to null,
                "devices" to emptyList<String>(),
                "bluetoothEnabled" to false,
                "routedToBluetooth" to false,
                "reason" to "bluetooth_disabled",
            )
        }

        if (!hasBluetoothConnectPermission()) {
            val routed = isAudioRoutedToBluetooth()
            return mapOf(
                "connected" to routed,
                "name" to null,
                "devices" to emptyList<String>(),
                "bluetoothEnabled" to true,
                "routedToBluetooth" to routed,
                "reason" to "bluetooth_connect_permission_missing",
            )
        }

        val profileDevices = getConnectedProfileDevices(bluetoothManager)
        val routed = isAudioRoutedToBluetooth()
        val deviceNames = profileDevices.map { safeDeviceName(it) }.distinct()
        val connected = profileDevices.isNotEmpty() || routed

        return mapOf(
            "connected" to connected,
            "name" to deviceNames.firstOrNull(),
            "devices" to deviceNames,
            "bluetoothEnabled" to true,
            "routedToBluetooth" to routed,
            "reason" to "ok",
        )
    }
}
