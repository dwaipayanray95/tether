# Preserve generic signatures to prevent Gson TypeToken errors during shrinking
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Keep Gson specific classes
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep Flutter Local Notifications plugin classes
-keep class com.dexterous.flutterlocalnotifications.** { *; }
