package com.rou39.omniverse

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * フォロー/フォロワー取得やつながり調査を、アプリを裏に回しても続けるためのサービス。
 *
 * 何もしないと、裏に回ったアプリは Android に凍結され、画面を消すと CPU も眠る。
 * 取得は数時間から数日かかるので、走っているあいだだけ通知を出して
 * 「前面で動いている」扱いにし、CPU を起こしておく。
 *
 * 取得そのものは Dart 側で動く。ここは場所を確保して通知を出すだけ。
 */
class JobForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "background_jobs"
        private const val NOTIFICATION_ID = 4201
        private const val ACTION_UPDATE = "update"
        private const val ACTION_CANCEL = "cancel"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_DONE = "done"
        private const val EXTRA_TOTAL = "total"

        /** 起こしておく上限。走っている間は更新のたびに延ばす */
        private const val WAKE_LOCK_MS = 30 * 60 * 1000L

        /** 通知の「中断」が押されたら呼ぶ。MainActivity が Dart へ伝える */
        var onCancelRequested: (() -> Unit)? = null

        @Volatile
        var isRunning = false
            private set

        /** 更新のたびに CPU を起こしておく期限を延ばすため、動いている実体を持つ */
        private var instance: JobForegroundService? = null

        private fun intent(context: Context, action: String, title: String, text: String,
                           done: Int, total: Int) =
            Intent(context, JobForegroundService::class.java).apply {
                this.action = action
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_DONE, done)
                putExtra(EXTRA_TOTAL, total)
            }

        /**
         * 通知を出して前面サービスにする。アプリが前に出ているときしか始められない
         * （Android 12 以降の決まり）。始められなければ false。
         */
        fun start(context: Context, title: String, text: String, done: Int, total: Int): Boolean {
            return try {
                val i = intent(context, ACTION_UPDATE, title, text, done, total)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(i)
                } else {
                    context.startService(i)
                }
                true
            } catch (e: Exception) {
                android.util.Log.w("JobForegroundService", "start failed: $e")
                false
            }
        }

        /** 通知の文言を差し替える。裏からでも呼べるよう通知だけを書き換える */
        fun update(context: Context, title: String, text: String, done: Int, total: Int) {
            if (!isRunning) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, build(context, title, text, done, total))
            instance?.holdWakeLock()
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, JobForegroundService::class.java))
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            // 進み具合を見せるだけなので、音も振動も出さない
            val channel = NotificationChannel(
                CHANNEL_ID, "実行中の取得", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "フォロー/フォロワー取得やつながり調査が走っている間に出ます"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        private fun build(context: Context, title: String, text: String,
                          done: Int, total: Int): Notification {
            ensureChannel(context)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val openIntent = PendingIntent.getActivity(context, 0, open, flags)
            val cancelIntent = PendingIntent.getService(
                context, 1,
                Intent(context, JobForegroundService::class.java).setAction(ACTION_CANCEL),
                flags
            )
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            builder
                .setSmallIcon(R.drawable.ic_stat_job)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
            @Suppress("DEPRECATION")
            builder.addAction(Notification.Action.Builder(0, "中断", cancelIntent).build())
            if (total > 0) builder.setProgress(total, done.coerceIn(0, total), false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // 始めた直後に出し、10 秒待たせない
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return builder.build()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            onCancelRequested?.invoke()
            return START_NOT_STICKY
        }
        val notification = build(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "取得中",
            intent?.getStringExtra(EXTRA_TEXT) ?: "",
            intent?.getIntExtra(EXTRA_DONE, 0) ?: 0,
            intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0,
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // 裏から始めようとした等。前面にできないなら居座らない
            android.util.Log.w("JobForegroundService", "startForeground failed: $e")
            stopSelf()
            return START_NOT_STICKY
        }
        isRunning = true
        instance = this
        holdWakeLock()
        // 落とされても勝手に立ち上げ直さない。Dart 側が居なければ意味が無い
        return START_NOT_STICKY
    }

    /** 画面を消しても CPU を眠らせない。走っている間だけ */
    private fun holdWakeLock() {
        val lock = wakeLock ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "omniverse:fetch-job")
            .also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
        lock.acquire(WAKE_LOCK_MS)
    }

    /** 最近のアプリから消されたら、取得も止まるので通知も消す */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
