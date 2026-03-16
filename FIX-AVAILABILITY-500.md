# Fix: Error 500 en Calendario de Disponibilidad

## Problema Identificado

El endpoint `GET /api/caregivers/:id/availability` estaba retornando error 500 (Internal Server Error) debido a:

1. **Falta de validación de parámetros**: No se validaban fechas inválidas en el query string
2. **Manejo de errores insuficiente**: No había try/catch completo en el servicio
3. **Acceso a propiedades potencialmente nulas**: `a.date.toISOString()` podía fallar si `date` era null/undefined
4. **Parsing de timeBlocks sin validación**: El casting de `timeBlocks` podía fallar con formatos inesperados
5. **Falta de logging**: No había logs suficientes para debugging

## Cambios Realizados

### Backend

#### 1. `caregiver.controller.ts` - Endpoint `getAvailability`

**Mejoras**:
- ✅ Validación de `caregiverId` (no puede ser vacío)
- ✅ Validación de fechas `from` y `to` (deben ser fechas ISO válidas)
- ✅ Try/catch completo con logging detallado
- ✅ Logs de debug en puntos clave del flujo
- ✅ Manejo de errores específicos (404 para cuidador no encontrado, 400 para fechas inválidas)

**Código agregado**:
```typescript
// Validación de fechas
if (req.query.from) {
  const fromDate = new Date(req.query.from as string);
  if (isNaN(fromDate.getTime())) {
    throw new CaregiverProfileValidationError('Fecha "from" inválida...');
  }
  from = fromDate;
}
```

#### 2. `caregiver.service.ts` - Función `getCaregiverAvailability`

**Mejoras**:
- ✅ Validación de `caregiverId` antes de consultar DB
- ✅ Try/catch completo alrededor de toda la función
- ✅ Validación de `date` antes de llamar `toISOString()`
- ✅ Manejo seguro de `timeBlocks` con try/catch interno
- ✅ Logging de errores con contexto completo
- ✅ Continuación en caso de filas inválidas (no falla todo el request)

**Código agregado**:
```typescript
// Validación de date antes de procesar
if (!a.date || !(a.date instanceof Date) || isNaN(a.date.getTime())) {
  logger.warn('Invalid date in availability row', { ... });
  continue; // Saltar esta fila, continuar con las demás
}

// Manejo seguro de timeBlocks
try {
  const blocks = a.timeBlocks as Record<string, boolean> | null;
  // ... procesamiento ...
} catch (blockError) {
  logger.warn('Error parsing timeBlocks', { ... });
  // Continuar con siguiente registro
}
```

### Frontend

#### 3. `useCaregiverAvailability.ts` - Hook React Query

**Mejoras**:
- ✅ Try/catch en `queryFn` para capturar errores
- ✅ Logging de errores en consola
- ✅ Retry configurado (1 intento adicional)
- ✅ Lanzamiento de errores para que React Query los maneje

#### 4. `CaregiverDetailPage.tsx` - Componente de detalle

**Mejoras**:
- ✅ Manejo de estado de error (`errorAvailability`)
- ✅ UI para mostrar mensaje de error al usuario
- ✅ Loading state visible mientras carga
- ✅ Calendarios solo se muestran cuando hay datos válidos

## Archivos Modificados

1. ✅ `garden-api/src/modules/caregiver-service/caregiver.controller.ts`
2. ✅ `garden-api/src/modules/caregiver-service/caregiver.service.ts`
3. ✅ `garden-web/src/hooks/useCaregiverAvailability.ts`
4. ✅ `garden-web/src/pages/CaregiverDetailPage.tsx`

## Logs Esperados

### Backend (Terminal)

**Cuando funciona correctamente**:
```
[INFO] GET /api/caregivers/:id/availability entry { caregiverId: '...', from: '...', to: '...' }
[INFO] calling getCaregiverAvailability { caregiverId: '...', from: '...', to: '...' }
[INFO] getCaregiverAvailability success { hospedajeCount: 30, paseosCount: 15 }
```

**Cuando hay error (cuidador no encontrado)**:
```
[WARN] Caregiver not found or not approved for availability { caregiverId: '...' }
[ERROR] Error en GET /api/caregivers/:id/availability { error: 'Cuidador no encontrado: ...', caregiverId: '...' }
```

**Cuando hay error (fecha inválida)**:
```
[ERROR] Error en GET /api/caregivers/:id/availability { error: 'Fecha "from" inválida...', query: { from: 'invalid' } }
```

**Cuando hay filas con datos inválidos**:
```
[WARN] Invalid date in availability row { availabilityId: '...', caregiverId: '...', date: null }
[WARN] Error parsing timeBlocks { availabilityId: '...', timeBlocks: {...}, error: '...' }
```

### Frontend (Consola del Navegador)

**Cuando funciona**:
- No hay errores en consola
- El calendario se muestra correctamente

**Cuando hay error**:
```
[useCaregiverAvailability] Error: Error: Cuidador no encontrado: ...
```
- Se muestra mensaje de error en la UI (fondo amarillo con texto)

## Instrucciones para Probar

### 1. Reiniciar el Backend

```bash
cd garden-api
npm run build  # Ya compilado, pero por si acaso
npm run dev    # O npm start si ya está en producción
```

### 2. Probar Manualmente con curl/Postman

**Caso 1: Cuidador válido con disponibilidad**
```bash
curl http://localhost:3000/api/caregivers/<caregiver-id>/availability
```

**Respuesta esperada (200)**:
```json
{
  "success": true,
  "data": {
    "caregiverId": "...",
    "from": "2026-02-05",
    "to": "2026-05-06",
    "hospedaje": ["2026-02-10", "2026-02-11", ...],
    "paseos": {
      "2026-02-10": ["MANANA", "TARDE"],
      ...
    }
  }
}
```

**Caso 2: Cuidador no encontrado**
```bash
curl http://localhost:3000/api/caregivers/invalid-id/availability
```

**Respuesta esperada (404)**:
```json
{
  "success": false,
  "error": {
    "code": "CAREGIVER_NOT_FOUND",
    "message": "Cuidador no encontrado: invalid-id"
  }
}
```

**Caso 3: Fecha inválida**
```bash
curl "http://localhost:3000/api/caregivers/<id>/availability?from=invalid-date"
```

**Respuesta esperada (400)**:
```json
{
  "success": false,
  "error": {
    "code": "CAREGIVER_VALIDATION",
    "message": "Fecha \"from\" inválida. Debe ser una fecha ISO válida."
  }
}
```

### 3. Probar en el Navegador

1. **Abrir** `http://localhost:5173` (o el puerto del frontend)
2. **Navegar** a cualquier cuidador del listado (debe tener status `APPROVED`)
3. **Verificar** que el calendario de disponibilidad carga sin errores
4. **Abrir DevTools** (F12) → Console
5. **Verificar** que no hay errores 500 en Network tab

**Resultado esperado**:
- ✅ Calendario se muestra correctamente
- ✅ Días disponibles en verde/claro
- ✅ Días bloqueados en gris
- ✅ No hay errores en consola
- ✅ No hay errores 500 en Network tab

### 4. Probar Casos Edge

**Caso A: Cuidador sin disponibilidad**
- El calendario debe mostrar "No hay fechas disponibles" o similar
- No debe haber error 500

**Caso B: Cuidador con filas inválidas en Availability**
- El backend debe loguear warnings pero continuar
- El calendario debe mostrar solo las fechas válidas

**Caso C: Error de red**
- El frontend debe mostrar mensaje de error amigable
- No debe crashear la aplicación

## Verificación Post-Fix

### Checklist

- [ ] Backend compila sin errores (`npm run build`)
- [ ] Endpoint responde 200 para cuidadores válidos
- [ ] Endpoint responde 404 para cuidadores no encontrados
- [ ] Endpoint responde 400 para fechas inválidas
- [ ] Logs aparecen en terminal del backend
- [ ] Calendario carga correctamente en el navegador
- [ ] No hay errores 500 en Network tab
- [ ] Mensajes de error se muestran correctamente en UI
- [ ] Casos edge (sin disponibilidad, datos inválidos) funcionan

## Notas Técnicas

1. **Logging**: Los logs de debug están activos con `fetch` a `http://127.0.0.1:7242/ingest/...`. Estos se pueden desactivar en producción si es necesario.

2. **Manejo de Errores**: El sistema ahora diferencia entre:
   - Errores operacionales (AppError): Se re-lanzan tal cual
   - Errores inesperados: Se envuelven en Error genérico con mensaje descriptivo

3. **Resiliencia**: Si una fila de Availability tiene datos inválidos, el sistema:
   - Loguea un warning
   - Continúa procesando las demás filas
   - No falla todo el request

4. **Frontend**: React Query maneja automáticamente:
   - Retry en caso de error de red
   - Cache de respuestas exitosas
   - Estados de loading/error/data

## Próximos Pasos (Opcional)

1. **Monitoreo**: Agregar métricas para errores de disponibilidad
2. **Validación de Schema**: Validar que `timeBlocks` tenga el formato correcto en Prisma
3. **Tests**: Agregar tests unitarios e integración para estos casos edge
4. **Documentación API**: Actualizar OpenAPI/Swagger con ejemplos de errores
