# Flutter ProGuard Rules for Memory & Size Optimization
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Mobile Scanner & Google ML Kit
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Suppress harmless warnings during optimization
-dontwarn io.flutter.**
-dontwarn dev.steenbakker.mobile_scanner.**
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
