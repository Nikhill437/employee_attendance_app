# InspireFace's native library (libInspireFace.so) calls back into these
# Java classes via JNI, looking up fields/methods by exact name (e.g.
# FaceFeature.data, Session.handle). R8 has no way to see that dependency
# through static analysis, so without this it silently renames/strips those
# classes in release builds — the JNI lookups then fail at runtime and crash
# the app (this is exactly what happened before this rule was added: the
# release APK's dex was missing FaceFeature, FaceBasicToken, and other
# classes that the debug build, which skips R8, kept intact).
-keep class com.insightface.sdk.inspireface.** { *; }
