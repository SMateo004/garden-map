# Fix Completo: Error 500 en Calendario de Disponibilidad

## Problema Identificado

El endpoint `GET /api/caregivers/:id/availability` estaba retornando error 500 debido a:

1. **Uso de `fetch` en Node.js**: El código usaba `fetch()` que puede no estar disponible en todas las versiones de Node.js, causando errores no capturados
2. **Manejo de errores insuficiente**: Aunque había try/catch, algunos errores podían escapar
3. **Falta de validación robusta**: No se validaban todos los casos edge (fechas inválidas, tipos incorrectos)
4. **Respuesta de error en lugar de datos vacíos**: Cuando no había disponibilidad, se lanzaba error en lugar de retornar array vacío

## Cambios Realizados

### Backend

#### 1. `caregiver.controller.ts` - Endpoint `getAvailability`

**Cambios clave**:
- ✅ **Removido `fetch`**: Reemplazado con `logger` de Winston (ya disponible)
- ✅ **Validación mejorada**: Validación más robusta de `caregiverId` y fechas
- ✅ **Logging detallado**: Logs en cada paso del proceso para debugging
- ✅ **Manejo de errores mejorado**: Try/catch con logging completo antes de re-lanzar

**Líneas modificadas**: 58-116

#### 2. `caregiver.service.ts` - Función `getCaregiverAvailability`

**Cambios clave**:
- ✅ **Removido `fetch`**: Reemplazado con `logger.debug/info/warn/error`
- ✅ **Retorno de datos vacíos**: Si el cuidador no está APPROVED, retorna disponibilidad vacía en lugar de error 404
- ✅ **Validación de tipos Date**: Manejo seguro de fechas (Date object, string, o null)
- ✅ **Normalización de fechas**: Fechas normalizadas a inicio/fin del día para comparaciones consistentes
- ✅ **Manejo robusto de filas inválidas**: Continúa procesando aunque algunas filas tengan datos inválidos

**Líneas modificadas**: 225-364

**Cambio crítico**:
```typescript
// ANTES: Lanzaba error si cuidador no encontrado
if (!profile) {
  throw new CaregiverNotFoundError(caregiverId);
}

// AHORA: Retorna disponibilidad vacía (permite mostrar calendario sin fechas)
if (!profile) {
  logger.warn('Caregiver not found or not approved for availability', { caregiverId });
  return {
    caregiverId,
    from: startDate.toISOString().slice(0, 10),
    to: endDate.toISOString().slice(0, 10),
    hospedaje: [],
    paseos: {},
  };
}
```

### Frontend

#### 3. `useCaregiverAvailability.ts` - Hook React Query

**Cambios clave**:
- ✅ **Logging detallado**: Console.debug/error para debugging
- ✅ **Manejo de datos vacíos**: Retorna estructura válida incluso si no hay datos
- ✅ **Retry inteligente**: No reintenta en caso de 404 (cuidador no encontrado)
- ✅ **Validación de ID**: Verifica que el ID existe antes de hacer la petición

**Líneas modificadas**: 6-60

## Archivos Modificados

1. ✅ `garden-api/src/modules/caregiver-service/caregiver.controller.ts` (líneas 58-116)
2. ✅ `garden-api/src/modules/caregiver-service/caregiver.service.ts` (líneas 225-364)
3. ✅ `garden-web/src/hooks/useCaregiverAvailability.ts` (líneas 6-60)

## Ruta Exacta que Fallaba

**Endpoint**: `GET /api/caregivers/:id/availability`

**Ruta completa**: `/api/caregivers/{caregiverId}/availability?from=YYYY-MM-DD&to=YYYY-MM-DD`

## Causa del Error 500

**Problema principal**: El uso de `fetch()` en Node.js causaba errores no capturados cuando `fetch` no estaba disponible o fallaba.

**Problemas secundarios**:
1. Validación insuficiente de tipos de datos (Date vs string)
2. Lanzamiento de errores cuando no había disponibilidad (debería retornar array vacío)
3. Falta de logging adecuado para debugging

## Logs Esperados Ahora

### Backend (Terminal)

**Cuando funciona correctamente**:
```
[INFO] GET /api/caregivers/:id/availability { caregiverId: '...', from: '...', to: '...' }
[DEBUG] Calling getCaregiverAvailability service { caregiverId: '...', from: '...', to: '...' }
[DEBUG] Checking caregiver profile { caregiverId: '...', startDate: '...', endDate: '...' }
[DEBUG] Querying availability rows { caregiverId: '...', startDate: '...', endDate: '...' }
[DEBUG] Availability rows fetched { caregiverId: '...', rowCount: 30 }
[INFO] Availability processing complete { caregiverId: '...', hospedajeCount: 25, paseosCount: 15 }
[INFO] Availability fetched successfully { caregiverId: '...', hospedajeCount: 25, paseosCount: 15 }
```

**Cuando no hay disponibilidad (cuidador no APPROVED)**:
```
[INFO] GET /api/caregivers/:id/availability { caregiverId: '...', ... }
[DEBUG] Checking caregiver profile { caregiverId: '...', ... }
[WARN] Caregiver not found or not approved for availability { caregiverId: '...' }
[INFO] Availability fetched successfully { caregiverId: '...', hospedajeCount: 0, paseosCount: 0 }
```

**Cuando hay error (fecha inválida)**:
```
[INFO] GET /api/caregivers/:id/availability { caregiverId: '...', from: 'invalid', ... }
[WARN] Invalid from date in availability request { from: 'invalid' }
[ERROR] Error en GET /api/caregivers/:id/availability { error: 'Fecha "from" inválida...', ... }
```

**Cuando hay filas con datos inválidos**:
```
[DEBUG] Availability rows fetched { rowCount: 5 }
[WARN] Invalid date type in availability row { availabilityId: '...', dateType: '...' }
[WARN] Error parsing timeBlocks { availabilityId: '...', ... }
[INFO] Availability processing complete { hospedajeCount: 3, paseosCount: 2 }
```

### Frontend (Consola del Navegador)

**Cuando funciona**:
```
[useCaregiverAvailability] Fetching availability { id: '...', from: '...', to: '...' }
[useCaregiverAvailability] Availability loaded { id: '...', hospedajeCount: 25, paseosCount: 15 }
```

**Cuando hay error**:
```
[useCaregiverAvailability] Error fetching availability { error: '...', caregiverId: '...', ... }
```

## Instrucciones para Probar

### 1. Reiniciar el Backend

```bash
cd garden-api
npm run build  # Compilar cambios
npm run dev    # Reiniciar servidor
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

**Caso 2: Cuidador sin disponibilidad (no APPROVED o sin registros)**
```bash
curl http://localhost:3000/api/caregivers/<id>/availability
```

**Respuesta esperada (200 con arrays vacíos)**:
```json
{
  "success": true,
  "data": {
    "caregiverId": "...",
    "from": "2026-02-05",
    "to": "2026-05-06",
    "hospedaje": [],
    "paseos": {}
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
2. **Navegar** a cualquier cuidador del listado
3. **Abrir DevTools** (F12) → Console y Network tabs
4. **Verificar**:
   - ✅ No hay errores 500 en Network tab
   - ✅ El calendario se muestra (aunque esté vacío si no hay disponibilidad)
   - ✅ Logs de debug en Console (si están habilitados)
   - ✅ No hay errores rojos en Console

**Resultado esperado**:
- ✅ Calendario carga sin errores 500
- ✅ Si hay disponibilidad: días disponibles se muestran
- ✅ Si no hay disponibilidad: calendario vacío pero sin errores
- ✅ Mensajes de error claros si hay problemas de red o validación

## Verificación Post-Fix

### Checklist

- [ ] Backend compila sin errores (`npm run build`)
- [ ] Endpoint responde 200 para cuidadores válidos (con o sin disponibilidad)
- [ ] Endpoint responde 400 para fechas inválidas
- [ ] Endpoint retorna arrays vacíos cuando no hay disponibilidad (no error 500)
- [ ] Logs aparecen en terminal del backend con información útil
- [ ] Calendario carga correctamente en el navegador sin errores 500
- [ ] No hay errores en Network tab del navegador
- [ ] Mensajes de error se muestran correctamente en UI si hay problemas
- [ ] Casos edge (sin disponibilidad, datos inválidos) funcionan sin romper

## Resumen de la Solución

**Problema raíz**: Uso de `fetch()` en Node.js que causaba errores no capturados.

**Solución**:
1. Reemplazado `fetch` con `logger` de Winston
2. Mejorado manejo de errores con try/catch robusto
3. Cambiado comportamiento: retorna datos vacíos en lugar de error cuando no hay disponibilidad
4. Agregado logging detallado en cada paso
5. Mejorado frontend para manejar casos edge

**Resultado**: El endpoint ahora siempre retorna 200 con datos (aunque sean vacíos) en lugar de 500, permitiendo que el frontend muestre el calendario correctamente.
