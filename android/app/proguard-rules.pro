# GetTube R8 keep rules (release builds).
#
# WHY: shared_preferences_android 2.5.0 switched to Pigeon's native interop
# (JNI). R8 renames kotlin.coroutines.Continuation (and friends), rewriting
# the JNI method descriptors, so the Dart side looks up a method that no
# longer exists -> NoSuchMethodError -> crash/blank screen at startup.
# See flutter/flutter#194649.
#
# We pin shared_preferences_android below 2.5.0 in pubspec.yaml (primary fix),
# and keep these rules as belt-and-suspenders for any other Pigeon/JNI plugin.

-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }

# Flutter plugin Android code is looked up via JNI/native interop by name.
-keep class io.flutter.plugins.** { *; }

# Standard: never rename native (JNI) methods.
-keepclasseswithmembernames class * { native <methods>; }
