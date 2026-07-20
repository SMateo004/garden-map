# Reglas de ProGuard/R8 para GARDEN.
#
# NOTA: al momento de escribir esto, `minifyEnabled`/`isMinifyEnabled` NO está
# activado en build.gradle.kts (release build type no lo define, por lo que
# el default de AGP es false) — R8 no corre shrinking/ofuscación sobre el
# build de release actual. Este archivo queda preparado por si se activa la
# minificación en el futuro (build más chico), para que no rompa
# flutter_local_notifications ni otros plugins que dependen de reflexión/
# serialización con signatures genéricas.

# flutter_local_notifications (paquete com.dexterous.flutterlocalnotifications):
# usa Gson internamente para (de)serializar notificaciones programadas
# (ScheduledNotificationDetails, etc.). R8 por defecto elimina la información
# de "generic signature" de los campos si no se le dice explícitamente que la
# conserve, lo que hace que Gson falle al reconstruir listas/objetos
# genéricos en tiempo de ejecución (crash reportado como "Null Cast" o
# excepción de deserialización en dispositivos con build minificado).
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Gson (dependencia transitiva de flutter_local_notifications) necesita esto
# para no romper la deserialización de tipos genéricos.
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class sun.misc.Unsafe { *; }
-dontwarn com.google.gson.**
