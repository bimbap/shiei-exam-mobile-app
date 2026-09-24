# Proguard / R8 rules for Project SHIEI Exam App (id.shiei.kiosk_app)

# Flutter Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter InAppWebView
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Wakelock Plus & Connectivity
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-keep class dev.fluttercommunity.plus.wakelock.** { *; }
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# Keep Android Application components referenced in AndroidManifest
-keep public class id.shiei.kiosk_app.MainActivity {
    public *;
}
-keep public class id.shiei.kiosk_app.ExamReminderReceiver {
    public *;
}

# Preserve Line Numbers and Source File attributes for crash diagnosis
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod

# Obfuscate internal helper methods & classes
-repackageclasses 'id.shiei.kiosk_app.internal'
-allowaccessmodification

# Google Play Core (Not used in direct APK distribution, suppress R8 missing class warnings)
-dontwarn com.google.android.play.core.**
