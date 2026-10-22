# Builds de Android e iOS desde GitHub Actions

Workflow: `.github/workflows/build-mobile.yml`. Se corre a mano: **Actions → Builds de Android e
iOS → Run workflow**, y se elige `android`, `ios` o `ambos`.

- **Android:** compila el AAB, comprueba que esté firmado con la llave de carga registrada en Play
  (SHA1 `33:18:…:2D:3A`) y lo sube a la **pista interna** de Play. Sin cuenta de servicio de Play,
  deja el AAB como artefacto de la corrida (3 días) para subirlo a mano.
- **iOS:** archiva y firma con firma automática (equipo `884TXBM28J`) y lo sube a **TestFlight**.
- **Número de build:** 100 + número de corrida, siempre creciente y ya mayor que el último subido a
  mano (38). La versión visible (`1.4.7`) sale de `pubspec.yaml`: súbela ahí antes de una versión
  nueva. Desde que se use el workflow, no volver a compilar a mano con un número menor: Play y
  Apple rechazan números que no crecen.

## Secrets (Settings → Secrets and variables → Actions)

### Android
| Secret | Cómo obtenerlo |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | En la máquina donde está la llave, en PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("garden-app\android\garden-upload-key.jks")) \| Set-Clipboard`. Pega el resultado. |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` de `garden-app/android/key.properties` (o del gestor de contraseñas) |
| `ANDROID_KEY_PASSWORD` | `keyPassword` del mismo archivo (si es igual, puede quedar vacío) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Opcional. Play Console → Configuración → Acceso a la API → crear una cuenta de servicio en Google Cloud, descargar su JSON y darle permiso de "Publicar en pistas de prueba" sobre la app. Pega el JSON completo. |

Los secrets de GitHub no se pueden volver a leer: **no reemplazan** el respaldo de la llave en el
gestor de contraseñas (ver `docs/STAGING_Y_RESPALDOS.md`).

### iOS
| Secret | Cómo obtenerlo |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Usuarios y acceso → Integraciones → Claves de la API → generar una clave con rol **Admin** (la firma automática en la nube crea los certificados con ella) |
| `APP_STORE_CONNECT_ISSUER_ID` | El "Issuer ID" que aparece arriba en esa misma página |
| `APP_STORE_CONNECT_KEY_P8` | El contenido completo del archivo `.p8` descargado (solo se descarga una vez) |

### Opcional
- `SENTRY_DSN`: el mismo que usa la API, para que los errores de la app lleguen a Sentry.

## Si falla
- **"El AAB no está firmado con la llave de carga"**: el keystore del secret no es el registrado en
  Play. Revisa el base64 o la contraseña.
- **iOS "No signing certificate"**: la clave de la API no es Admin, o el equipo no aceptó el último
  acuerdo en developer.apple.com.
- **"Version code already used"**: alguien subió un build a mano con un número mayor. Sube
  `BUILD_NUMBER_OFFSET` en el workflow.
