####################################
# Firebase Core
####################################
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

####################################
# Firebase Analytics
####################################
-keep class com.google.android.gms.measurement.** { *; }
-dontwarn com.google.android.gms.measurement.**

####################################
# Firebase Realtime Database
####################################
-keep class com.google.firebase.database.** { *; }
-dontwarn com.google.firebase.database.**

####################################
# Firebase AppCheck (Play Integrity & Debug)
####################################
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.firebase.appcheck.**
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.tasks.**
-keep class com.google.android.play.integrity.** { *; }
-dontwarn com.google.android.play.integrity.**

####################################
# Keep annotations (used for reflection)
####################################
-keepattributes *Annotation*
-keep class androidx.annotation.Keep

####################################
# Keep required classes for reflection
####################################
-keepclassmembers class * {
    @com.google.firebase.database.PropertyName <methods>;
    @com.google.firebase.database.Exclude <methods>;
}

####################################
# General Keep Rules
####################################
-keepclassmembers class * {
    public <init>(...);
}

# Optional: Avoid removing enums used in Firebase config
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
