package id.shiei.kiosk_app

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File
import java.net.Socket
import java.net.InetSocketAddress
import java.security.MessageDigest
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.ContentValues
import android.os.Environment
import android.provider.MediaStore
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "id.shiei/lockdown"
    private var isVolumeLockActive = false
    private var audioManager: AudioManager? = null
    private var volumeObserver: ContentObserver? = null
    private var telephonyManager: TelephonyManager? = null
    private var isPhoneCallActive = false
    private var isKioskSystemBarsBlocked = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Allow screenshots across general screens (Home, Settings, History).
        // FLAG_SECURE is strictly toggled on when actively taking an exam.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Edge-to-edge transparent system bars (matching modern Android & Google Files)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT

        // Hide overlay windows (floating apps, chat heads, screen translators)
        applyOverlayProtection(true)

        // Initialize phone call listener so incoming phone calls do not trigger anti-cheat ejection
        initTelephonyListener()

        @Suppress("DEPRECATION")
        window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
            if (isKioskSystemBarsBlocked && (visibility and android.view.View.SYSTEM_UI_FLAG_FULLSCREEN) == 0) {
                enforceKioskSystemBars()
                collapseStatusBar()
            }
        }
    }

    private fun applyOverlayProtection(enable: Boolean) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                window.setHideOverlayWindows(enable)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val flag = 0x00080000
                if (enable) {
                    window.addFlags(flag)
                } else {
                    window.clearFlags(flag)
                }
            }
        } catch (e: Exception) {
            // Ignore on unsupported devices
        }
    }

    private fun initTelephonyListener() {
        try {
            telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyManager?.registerTelephonyCallback(
                    mainExecutor,
                    object : android.telephony.TelephonyCallback(), android.telephony.TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) {
                            isPhoneCallActive = (state == TelephonyManager.CALL_STATE_RINGING || state == TelephonyManager.CALL_STATE_OFFHOOK)
                        }
                    }
                )
            } else {
                @Suppress("DEPRECATION")
                telephonyManager?.listen(object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        super.onCallStateChanged(state, phoneNumber)
                        isPhoneCallActive = (state == TelephonyManager.CALL_STATE_RINGING || state == TelephonyManager.CALL_STATE_OFFHOOK)
                    }
                }, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (e: Exception) {
            isPhoneCallActive = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exitApp" -> {
                    finishAffinity()
                    android.os.Process.killProcess(android.os.Process.myPid())
                    System.exit(0)
                    result.success(true)
                }

                "setFlagSecure" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    if (enable) {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }

                "getNetworkType" -> {
                    result.success(getNetworkType())
                }

                "setOverlayProtection" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    applyOverlayProtection(enable)
                    result.success(true)
                }

                "isPhoneCallActive" -> {
                    val isVoip = audioManager?.let {
                        it.mode == AudioManager.MODE_IN_CALL || it.mode == AudioManager.MODE_IN_COMMUNICATION
                    } ?: false
                    result.success(isPhoneCallActive || isVoip)
                }

                "forceMaxVolume" -> {
                    forceVolumeToMaximum()
                    result.success(true)
                }

                "startVolumeLock" -> {
                    isVolumeLockActive = true
                    forceVolumeToMaximum()
                    registerVolumeObserver()
                    result.success(true)
                }

                "stopVolumeLock" -> {
                    isVolumeLockActive = false
                    unregisterVolumeObserver()
                    result.success(true)
                }

                "isMultiWindow" -> {
                    val inMulti = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        isInMultiWindowMode
                    } else {
                        false
                    }
                    result.success(inMulti)
                }

                "setKioskSystemBarsBlocked" -> {
                    val block = call.argument<Boolean>("blocked") ?: true
                    isKioskSystemBarsBlocked = block
                    if (block) {
                        enforceKioskSystemBars()
                        collapseStatusBar()
                    } else {
                        restoreNormalSystemBars()
                    }
                    result.success(true)
                }

                "lockOrientationPortrait" -> {
                    val lock = call.argument<Boolean>("lock") ?: true
                    requestedOrientation = if (lock) {
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    } else {
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                    result.success(true)
                }

                "startLockTask" -> {
                    try {
                        startLockTask()
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        nm?.cancelAll()
                        enforceKioskSystemBars()
                        collapseStatusBar()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "isLockTaskActive" -> {
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        val isLocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            am?.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
                        } else {
                            am?.isInLockTaskMode == true
                        }
                        result.success(isLocked)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "isBluetoothEnabled" -> {
                    result.success(isBluetoothEnabled())
                }

                "getBatteryLevel" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                        val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                        result.success(level)
                    } catch (e: Exception) {
                        result.success(-1)
                    }
                }

                "isDeviceCharging" -> {
                    result.success(isDeviceCharging())
                }

                "isExternalDisplayConnected" -> {
                    result.success(isExternalDisplayConnected())
                }

                "getScreenBrightness" -> {
                    result.success(getScreenBrightness())
                }

                "setWindowBrightness" -> {
                    val brightness = call.argument<Int>("brightness") ?: 50
                    setWindowBrightness(brightness)
                    result.success(true)
                }

                "getDeviceName" -> {
                    result.success(getDeviceName())
                }

                "getDeviceId" -> {
                    result.success(getHardwareDeviceId())
                }

                "openBrowserUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrBlank()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }

                "getAppCacheDir" -> {
                    val dir = externalCacheDir ?: cacheDir
                    result.success(dir.absolutePath)
                }

                "saveFileToDownloads" -> {
                    val filename = call.argument<String>("filename") ?: "template.xlsx"
                    val rawBytes = call.argument<Any>("bytes")
                    val bytes: ByteArray? = when (rawBytes) {
                        is ByteArray -> rawBytes
                        is List<*> -> {
                            val arr = ByteArray(rawBytes.size)
                            for (i in rawBytes.indices) {
                                val item = rawBytes[i]
                                arr[i] = when (item) {
                                    is Number -> item.toByte()
                                    else -> 0
                                }
                            }
                            arr
                        }
                        else -> null
                    }
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_DATA", "File bytes are empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        var saved = false
                        var savedPath = ""

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { stream ->
                                    stream.write(bytes)
                                    stream.flush()
                                }
                                saved = true
                                savedPath = uri.toString()
                            }
                        } else {
                            @Suppress("DEPRECATION")
                            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            if (!downloadDir.exists()) {
                                downloadDir.mkdirs()
                            }
                            val destFile = File(downloadDir, filename)
                            destFile.writeBytes(bytes)
                            saved = true
                            savedPath = destFile.absolutePath
                        }

                        if (saved) {
                            result.success(savedPath)
                        } else {
                            result.error("SAVE_FAILED", "Failed to insert into MediaStore", null)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }

                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }

                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }

                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (!filePath.isNullOrBlank()) {
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                                return@setMethodCallHandler
                            }

                            // Check unknown app install permission on Android 8+
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                val permIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(permIntent)
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            } else {
                                Uri.fromFile(file)
                            }

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }

                            // Explicitly grant read permission to package installer handlers
                            try {
                                val resolveList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                                for (resolveInfo in resolveList) {
                                    val targetPkg = resolveInfo.activityInfo.packageName
                                    grantUriPermission(targetPkg, apkUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            } catch (_: Exception) {}

                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("SHIEI_INSTALL", "Error installing APK: ${e.message}", e)
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "File path is empty", null)
                    }
                }

                "scheduleExamReminder" -> {
                    val examId = call.argument<Int>("examId") ?: 0
                    val reminderId = call.argument<Int>("reminderId") ?: examId
                    val title = call.argument<String>("title") ?: "Pengingat Ujian - Project Shiei"
                    val message = call.argument<String>("message") ?: "Ujian akan segera dimulai."
                    val triggerTimeMillis = (call.argument<Number>("triggerTimeMillis"))?.toLong() ?: 0L

                    val success = scheduleExamAlarm(examId, reminderId, title, message, triggerTimeMillis)
                    result.success(success)
                }

                "cancelExamReminder" -> {
                    val reminderId = call.argument<Int>("reminderId") ?: 0
                    cancelExamAlarm(reminderId)
                    result.success(true)
                }

                "cancelAllExamReminders" -> {
                    val reminderIds = call.argument<List<Int>>("reminderIds") ?: emptyList()
                    for (id in reminderIds) {
                        cancelExamAlarm(id)
                    }
                    result.success(true)
                }

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            androidx.core.app.ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
                        }
                    }
                    result.success(true)
                }

                "isNotificationPermissionGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                            this, android.Manifest.permission.POST_NOTIFICATIONS
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    } else {
                        result.success(true)
                    }
                }

                "checkStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        result.success(true)
                    } else {
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                            this, android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                }

                "requestStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        result.success(true)
                    } else {
                        if (androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            androidx.core.app.ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 102)
                        }
                        result.success(true)
                    }
                }

                "isDeviceRooted" -> {
                    Thread {
                        val res = isDeviceRooted()
                        runOnUiThread { result.success(res) }
                    }.start()
                }

                "isFridaDetected" -> {
                    Thread {
                        val res = isFridaDetected()
                        runOnUiThread { result.success(res) }
                    }.start()
                }

                "isUsbDebuggingEnabled" -> {
                    result.success(isUsbDebuggingEnabled())
                }

                "getUsbDebuggingStatus" -> {
                    result.success(getUsbDebuggingStatus())
                }

                "openDeveloperSettings" -> {
                    result.success(openDeveloperSettings())
                }

                "verifyAppSignature" -> {
                    Thread {
                        val res = getAppSignatureHash()
                        runOnUiThread { result.success(res) }
                    }.start()
                }

                "checkSecurityIntegrity" -> {
                    Thread {
                        val res = checkSecurityIntegrity()
                        runOnUiThread { result.success(res) }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleExamAlarm(
        examId: Int,
        reminderId: Int,
        title: String,
        message: String,
        triggerTimeMillis: Long
    ): Boolean {
        if (triggerTimeMillis <= System.currentTimeMillis()) return false
        return try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
            val intent = Intent(this, ExamReminderReceiver::class.java).apply {
                action = ExamReminderReceiver.ACTION_EXAM_REMINDER
                putExtra("exam_id", examId)
                putExtra("reminder_id", reminderId)
                putExtra("title", title)
                putExtra("message", message)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                reminderId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            }
            true
        } catch (e: Exception) {
            android.util.Log.e("SHIEI_REMINDER", "Failed to schedule alarm: ${e.message}", e)
            false
        }
    }

    private fun cancelExamAlarm(reminderId: Int) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(this, ExamReminderReceiver::class.java).apply {
                action = ExamReminderReceiver.ACTION_EXAM_REMINDER
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                reminderId,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        } catch (_: Exception) {}
    }

    private fun isBluetoothEnabled(): Boolean {
        return try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bm?.adapter ?: BluetoothAdapter.getDefaultAdapter()
            adapter?.isEnabled == true
        } catch (e: Exception) {
            false
        }
    }

    private fun isDeviceCharging(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                if (bm?.isCharging == true) return true
            }
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = registerReceiver(null, ifilter)
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        } catch (e: Exception) {
            false
        }
    }

    private fun isExternalDisplayConnected(): Boolean {
        return try {
            val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
            val displays = dm?.displays ?: emptyArray()
            if (displays.size > 1) {
                return true
            }
            val presentationDisplays = dm?.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION) ?: emptyArray()
            presentationDisplays.isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }

    private fun getScreenBrightness(): Int {
        return try {
            val brightness = Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                128
            )
            (brightness * 100) / 255
        } catch (e: Exception) {
            50
        }
    }

    private fun setWindowBrightness(percent: Int) {
        try {
            val clamped = (percent.coerceIn(40, 100)) / 100f
            val lp = window.attributes
            lp.screenBrightness = clamped
            window.attributes = lp
        } catch (e: Exception) {
            // Ignore on unsupported devices
        }
    }

    private fun getDeviceName(): String {
        return try {
            // 1. Check Settings.Global.DEVICE_NAME (Android 7.1+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val globalName = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                if (!globalName.isNullOrBlank()) return globalName
            }

            // 2. Check Settings.System device_name
            val sysName = Settings.System.getString(contentResolver, "device_name")
            if (!sysName.isNullOrBlank()) return sysName

            // 3. Fallback to Capitalized Brand + Model
            val brand = Build.BRAND.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
            val model = Build.MODEL ?: ""
            if (model.startsWith(brand, ignoreCase = true)) {
                model
            } else {
                "$brand $model".trim()
            }
        } catch (e: Exception) {
            val brand = Build.BRAND ?: "Android"
            val model = Build.MODEL ?: "Device"
            "$brand $model"
        }
    }

    private fun getHardwareDeviceId(): String {
        return try {
            Build.MODEL ?: Build.DEVICE ?: "UNKNOWN"
        } catch (e: Exception) {
            "UNKNOWN"
        }
    }

    /**
     * Set stream volume to 100% max hardware capacity.
     */
    private fun forceVolumeToMaximum() {
        audioManager?.let { am ->
            val maxAlarm = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarm, 0)

            val maxMusic = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0)
        }
    }

    /**
     * Register observer on audio settings so any decrease in volume immediately bounces back to max.
     */
    private fun registerVolumeObserver() {
        if (volumeObserver == null) {
            volumeObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    super.onChange(selfChange)
                    if (isVolumeLockActive) {
                        forceVolumeToMaximum()
                    }
                }
            }
            contentResolver.registerContentObserver(
                Settings.System.CONTENT_URI,
                true,
                volumeObserver!!
            )
        }
    }

    private fun unregisterVolumeObserver() {
        volumeObserver?.let {
            contentResolver.unregisterContentObserver(it)
            volumeObserver = null
        }
    }

    /**
     * Intercept physical hardware volume keys.
     * When volume lock is active, pressing volume down immediately forces maximum volume.
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (isVolumeLockActive && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_MUTE)) {
            forceVolumeToMaximum()
            return true // Consume event so volume doesn't decrease
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun getNetworkType(): String {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "none"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = cm.activeNetwork ?: return "none"
                val caps = cm.getNetworkCapabilities(network) ?: return "none"
                return when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    else -> "connected"
                }
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo ?: return "none"
                if (!info.isConnected) return "none"
                return when (info.type) {
                    ConnectivityManager.TYPE_WIFI -> "wifi"
                    ConnectivityManager.TYPE_MOBILE -> "cellular"
                    else -> "connected"
                }
            }
        } catch (e: Exception) {
            return "none"
        }
    }

    private fun collapseStatusBar() {
        try {
            @Suppress("DEPRECATION")
            val closeDialogs = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            sendBroadcast(closeDialogs)
        } catch (_: Exception) {}
    }

    private fun enforceKioskSystemBars() {
        runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    window.setDecorFitsSystemWindows(false)
                    window.insetsController?.let { controller ->
                        controller.hide(android.view.WindowInsets.Type.systemBars())
                        controller.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_DEFAULT
                    }
                } else {
                    @Suppress("DEPRECATION")
                    window.decorView.systemUiVisibility = (
                        android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                        or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    )
                }
            } catch (_: Exception) {}
        }
    }

    private fun restoreNormalSystemBars() {
        runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    window.setDecorFitsSystemWindows(true)
                    window.insetsController?.let { controller ->
                        controller.show(android.view.WindowInsets.Type.systemBars())
                        controller.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_DEFAULT
                    }
                } else {
                    @Suppress("DEPRECATION")
                    window.decorView.systemUiVisibility = (
                        android.view.View.SYSTEM_UI_FLAG_VISIBLE
                    )
                }
            } catch (_: Exception) {}
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus && isKioskSystemBarsBlocked) {
            collapseStatusBar()
            enforceKioskSystemBars()
        }
    }

    override fun dispatchTouchEvent(ev: android.view.MotionEvent?): Boolean {
        if (isKioskSystemBarsBlocked && ev != null) {
            val screenHeight = resources.displayMetrics.heightPixels
            // Intercept swipe down from top edge (status bar) or up from bottom edge (gesture nav bar)
            if (ev.rawY < 60 || ev.rawY > screenHeight - 70) {
                collapseStatusBar()
                enforceKioskSystemBars()
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun isDeviceRooted(): Boolean {
        // 1. Check build tags for test-keys
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            return true
        }

        // 2. Check standard SU and Magisk binary paths
        val suPaths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su",
            "/sbin/.magisk",
            "/data/adb/magisk"
        )
        for (path in suPaths) {
            try {
                if (File(path).exists()) return true
            } catch (_: Exception) {}
        }

        // 3. Check which su execution (command check)
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            val reader = process.inputStream.bufferedReader()
            val output = reader.readLine()
            process.destroy()
            !output.isNullOrBlank()
        } catch (_: Exception) {
            false
        }
    }

    private fun isFridaDetected(): Boolean {
        // 1. Check /proc/net/tcp & tcp6 for Frida default port 27042 (hex 69A2)
        try {
            val tcpFiles = arrayOf("/proc/net/tcp", "/proc/net/tcp6")
            for (tcpPath in tcpFiles) {
                val f = File(tcpPath)
                if (f.canRead()) {
                    val found = f.useLines { lines ->
                        lines.any { it.contains(":69A2", ignoreCase = true) }
                    }
                    if (found) return true
                }
            }
        } catch (_: Exception) {}

        // 2. Check /proc/self/maps for loaded Frida gadget or agent libraries
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.canRead()) {
                val found = mapsFile.useLines { lines ->
                    lines.any { line ->
                        line.contains("frida", ignoreCase = true) ||
                        line.contains("gadget", ignoreCase = true) ||
                        line.contains("gum-js-loop", ignoreCase = true)
                    }
                }
                if (found) return true
            }
        } catch (_: Exception) {}

        // 3. Fallback: Quick background socket check to prevent NetworkOnMainThreadException
        var isPortOpen = false
        try {
            val t = Thread {
                try {
                    val socket = Socket()
                    socket.connect(InetSocketAddress("127.0.0.1", 27042), 100)
                    socket.close()
                    isPortOpen = true
                } catch (_: Exception) {}
            }
            t.start()
            t.join(120)
        } catch (_: Exception) {}

        return isPortOpen
    }

    private fun isUsbDebuggingEnabled(): Boolean {
        return try {
            val adb = Settings.Global.getInt(contentResolver, Settings.Global.ADB_ENABLED, 0)
            adb == 1
        } catch (_: Exception) {
            false
        }
    }

    private fun isUsbConnectedToHost(): Boolean {
        return try {
            // Check 1: Sticky battery intent for USB plugged state (PC / Laptop port)
            val batteryFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = registerReceiver(null, batteryFilter)
            val chargePlug = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
            val isUsbPlugged = chargePlug == BatteryManager.BATTERY_PLUGGED_USB

            // Check 2: Sticky USB_STATE intent for hardware host data link
            val usbFilter = IntentFilter("android.hardware.usb.action.USB_STATE")
            val usbStatus = registerReceiver(null, usbFilter)
            val isUsbConnected = usbStatus?.getBooleanExtra("connected", false) ?: false
            val isUsbConfigured = usbStatus?.getBooleanExtra("configured", false) ?: false

            isUsbPlugged || (isUsbConnected && isUsbConfigured)
        } catch (_: Exception) {
            false
        }
    }

    private fun getUsbDebuggingStatus(): Map<String, Any> {
        val isAdb = isUsbDebuggingEnabled()
        val isHostConnected = isUsbConnectedToHost()
        val isAdbActiveWithHost = isAdb && isHostConnected

        return mapOf(
            "isAdbEnabled" to isAdb,
            "isUsbConnected" to isHostConnected,
            "isAdbActiveWithHost" to isAdbActiveWithHost
        )
    }

    private fun openDeveloperSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun getAppSignatureHash(): String {
        return try {
            val certBytes: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                )
                val signingInfo = packageInfo.signingInfo
                if (signingInfo != null) {
                    if (signingInfo.hasMultipleSigners()) {
                        signingInfo.apkContentsSigners.firstOrNull()?.toByteArray()
                    } else {
                        signingInfo.signingCertificateHistory.firstOrNull()?.toByteArray()
                    }
                } else null
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                packageInfo.signatures?.firstOrNull()?.toByteArray()
            }

            if (certBytes != null) {
                val md = MessageDigest.getInstance("SHA-256")
                val digest = md.digest(certBytes)
                digest.joinToString("") { "%02X".format(it) }
            } else {
                ""
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun isAppDebuggable(): Boolean {
        return (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun checkSecurityIntegrity(): Map<String, Any> {
        val isDebug = isAppDebuggable()
        val isRoot = isDeviceRooted()
        val isFrida = isFridaDetected()
        val isAdb = isUsbDebuggingEnabled()
        val isUsbConnected = isUsbConnectedToHost()
        val isAdbActiveWithHost = isAdb && isUsbConnected
        val sigHash = getAppSignatureHash()

        // In debug mode, allow developer signing. In release mode, signature must exist and not be empty.
        val isSignatureValid = if (isDebug) {
            true
        } else {
            sigHash.isNotEmpty()
        }

        return mapOf(
            "isRooted" to isRoot,
            "isFrida" to isFrida,
            "isUsbDebugging" to isAdb,
            "isUsbConnected" to isUsbConnected,
            "isAdbActiveWithHost" to isAdbActiveWithHost,
            "isSignatureValid" to isSignatureValid,
            "signatureHash" to sigHash,
            "isDebug" to isDebug
        )
    }

    override fun onDestroy() {
        unregisterVolumeObserver()
        super.onDestroy()
    }
}
