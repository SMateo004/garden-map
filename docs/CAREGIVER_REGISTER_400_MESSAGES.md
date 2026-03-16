# Registro cuidador – Mensajes de validación (400) y cómo probar

## Respuesta 400 del backend

Cuando la validación falla, el backend responde:

```json
{
  "success": false,
  "message": "Datos inválidos",
  "error": { "code": "VALIDATION_ERROR", "message": "Datos inválidos" },
  "errors": [
    { "field": "profile.zone", "message": "Elige una zona" },
    { "field": "profile.bio", "message": "La descripción debe tener al menos 50 caracteres" }
  ]
}
```

## Mensajes exactos por campo (MVP)

| Campo / requisito | Mensaje que verá el usuario si falta o es inválido |
|-------------------|-----------------------------------------------------|
| **Fotos del espacio** (4–6) | "Debes subir al menos 4 fotos del espacio (máximo 6)" o "Máximo 6 fotos del espacio" |
| **Servicios** (al menos uno) | "Elige al menos un servicio (Hospedaje o Paseo)" |
| **Zona** | "Elige una zona" o "Zona no válida; elige una de la lista" |
| **Descripción (bio)** | "La descripción debe tener al menos 50 caracteres" o "La descripción no puede superar 500 caracteres" |
| **CI anverso** | "Debes subir la foto del CI anverso" o "URL de CI anverso inválida" |
| **CI reverso** | "Debes subir la foto del CI reverso" o "URL de CI reverso inválida" |
| **Email / contraseña / nombre / teléfono** | Los definidos en `registerCaregiverUserSchema` (ej. "Email inválido", "Mínimo 8 caracteres", "Nombre requerido", "Teléfono debe ser +591...") |

## Comportamiento en el frontend

- Si el backend devuelve **400** con `errors`:
  - Se muestra **un toast por cada error** con el `message` correspondiente.
  - Se **navega al paso del wizard** donde está el primer campo con error (según `stepForField`).
- Si falta **CI** o **fotos del espacio** antes de enviar, el wizard ya muestra toasts propios (ej. "Sube la foto del CI anverso y del reverso", "Sube al menos 4 fotos").

## Cómo probar

### 1. Envío incompleto (debe mostrar mensajes claros)

1. Ir al registro de cuidador y avanzar hasta el último paso (Revisa tu información).
2. Con DevTools o un proxy, modificar el payload antes de enviar para que falle validación, por ejemplo:
   - Quitar `profile.zone` o enviar `profile.zone: ""`.
   - Enviar `profile.bio` con menos de 50 caracteres.
   - Enviar `profile.photos` con menos de 4 URLs.
   - Quitar `profile.ciAnversoUrl` o `profile.ciReversoUrl`.
3. Enviar el formulario.
4. **Comprobar:**
   - Respuesta **400** con `errors` en el body.
   - En la app: varios toasts con los mensajes de la tabla anterior.
   - La vista vuelve al **paso** correspondiente al primer error (ej. zona → paso 3, fotos → paso 8, CI → paso 10).

### 2. Envío completo (debe responder 201)

1. Completar todos los pasos del wizard:
   - Nombre, apellido, teléfono (+591...).
   - Email y contraseña.
   - Zona elegida.
   - Al menos un servicio (Hospedaje o Paseo).
   - Descripción de al menos 50 caracteres.
   - Si hay Hospedaje: tipo de espacio y, si aplica, tarifas.
   - Al menos 4 fotos del espacio (subir y seguir).
   - Términos, privacidad y verificación aceptados.
   - CI anverso y reverso subidos (y opcional número de CI).
2. En el último paso, pulsar "Enviar solicitud".
3. **Comprobar:**
   - Respuesta **201**.
   - Perfil en estado **PENDING_REVIEW**.
   - Toast de éxito y redirección al dashboard de cuidador.

### 3. Logs en el backend

En el log del API deberías ver algo como:

```
Intento registro cuidador – body + files { body: { user: {...}, profile: {...} }, files: undefined }
```

Si la validación falla:

```
Registro cuidador – validación fallida { issues: [{ path: ['profile','zone'], message: 'Elige una zona' }, ...] }
```

## Requisitos mínimos MVP (resumen)

- **Fotos del espacio:** mínimo 4, máximo 6 (cada una URL válida).
- **CI:** anverso y reverso subidos (URLs guardadas en el perfil).
- **Servicios:** al menos uno (HOSPEDAJE o PASEO).
- **Zona:** una valor del enum (EQUIPETROL, URBARI, NORTE, LAS_PALMAS, CENTRO_SAN_MARTIN, OTROS).
- **Bio:** entre 50 y 500 caracteres.
