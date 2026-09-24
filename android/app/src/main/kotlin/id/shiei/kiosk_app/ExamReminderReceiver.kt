package id.shiei.kiosk_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class ExamReminderReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "shiei_exam_reminders"
        const val CHANNEL_NAME = "Pengingat Jadwal Ujian"
        const val CHANNEL_DESC = "Notifikasi pengingat jadwal ujian dari Project Shiei"
        const val ACTION_EXAM_REMINDER = "id.shiei.kiosk_app.ACTION_EXAM_REMINDER"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val examId = intent.getIntExtra("exam_id", 0)
        val reminderId = intent.getIntExtra("reminder_id", 0)
        val title = intent.getStringExtra("title") ?: "Pengingat Ujian - Project Shiei"
        val message = intent.getStringExtra("message") ?: "Ujian Anda akan segera dimulai. Silakan persiapkan perangkat Anda."

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create high-importance notification channel on Android 8.0+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESC
                enableVibration(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Check POST_NOTIFICATIONS permission on Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                return
            }
        }

        // Intent to launch MainActivity when student taps the notification
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_reminder", true)
            putExtra("exam_id", examId)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            if (reminderId != 0) reminderId else examId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notificationId = if (reminderId != 0) reminderId else (examId * 10 + 1)
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }
}
