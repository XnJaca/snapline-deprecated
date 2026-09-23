---
id: BOARD-specs-mobile
title: Board — Specs mobile
type: board
tags:
  - board
  - kanban
  - mobile
kanban-plugin: board

---

## 📝 Backlog (sin empezar)


## ✏️ Borrador (escribiendo el spec)

- [ ] [[specs/mobile/0002-idioma-de-la-app/README|SPEC-0002: Idioma de la app]]



## 🔍 Review (listo para revisar)



## ✅ Aprobado (listo para implementar)



## 🛠️ En implementación




## 🎉 Implementado

- [x] [[specs/mobile/0013-el-punto-se-fija-al-crear-la-propiedad/README|SPEC-0013: El punto se fija al crear la propiedad]] — sale de probar el alta con los clientes reales de William el 2026-09-22: SPEC-0007 enganchó el mapa solo a la corrección de la propiedad, así que se crea sin pasar por él y la obra queda sin geocerca. El punto pasa a ser parte del alta —una sola hoja, un solo `site.create`—, y el alta de obra avisa cuando la propiedad elegida no tiene punto. **El contrato ya lo acepta**: `openapi.json` no cambia, y que no cambie es criterio · **`spec-reviewer` APROBADO en la tercera pasada**: la primera amplió el `goal` a la tab Detalle y aclaró qué recibe el mapa cuando la propiedad no existe; la segunda trajo el criterio de ida y vuelta en Detalle y el riesgo de mover el `watch` del bloque al envoltorio · **Alcance agregado el mismo día**, pedido al probar el alta: la dirección se rellena desde el punto con el geocodificador **del teléfono** —sin llave ni SKU de Google, adenda en ADR-0012—, sin pisar lo escrito; el país no se rellena porque el selector nunca está vacío, y solo decide si el estado entra. Dos pasadas más de `spec-reviewer` hasta APROBADO · **Tercer tramo**: los campos se bloquean mientras se busca, lo rellenado se revisa en una hoja antes de guardar, y el mapa se puede ver en satélite con la elección guardada en el dispositivo. El `code-reviewer` encontró acá dos MEDIO de concurrencia que ningún test veía —una segunda búsqueda pisando a la primera, y la lectura del disco pisando un toque—, los dos cerrados con su test · **Copy de la hoja de revisión reescrito** a voz de producto, y con él las siete cadenas de la pantalla del mapa que seguían en voseo desde SPEC-0007 · **Cuarto tramo**, de probar en el teléfono: mover el punto no reabría la hoja ni reemplazaba la dirección —`fillMissing` solo escribía en campos vacíos—, y se sumó buscar una dirección en el mapa, que **mueve la cámara y nunca fija el punto**, como ADR-0012 exige  · **Quinto tramo**: mover el punto de una propiedad guardada ofrece actualizar su dirección comparándola campo por campo, sin pisar nada sin confirmar. Sale de «No entra», donde este mismo spec lo había puesto, porque en un teléfono real dejaba el punto en Florida y la dirección en Costa Rica· **Implementado en el working tree**: 61 tests nuevos, suite en 499, `openapi.json` sin diff; **PR #50 mergeado**
- [x] [[specs/mobile/0012-avance-de-la-obra/README|SPEC-0012: Avance de la obra]] — 423 tests en el móvil, 97 unitarios y 78 e2e, PR #39 mergeado; llenó la última tab placeholder de la obra y trajo `project_status_change`, la tabla que faltaba porque `project.status` guarda el ahora y pisa lo anterior. **El spec cambió de forma probando en el simulador**: nació como hilo cronológico y terminó siendo una vista de estado —«cómo va», no «qué pasó»—, con el hilo detrás de un toque; el `goal` se reescribió con la pantalla. Y el riesgo que el propio spec declaraba se materializó: la migración sembraba un hito copiando el estado de hoy a la fecha de creación, así que el hilo afirmaba que una obra estaba «En proceso» el día que se creó. De ahí salieron tres bugs que ningún test veía —el pull entero caído por una relación de entity requerida en el contrato, la URL firmada pedida en cada cambio de tab, y una clave de `l10n` definida dos veces que pisaba el texto de otra pantalla— y sus tres guardarraíles: `sync_contract_test.dart`, el caché de firmas y `l10n_arb_test.dart`
- [x] [[specs/mobile/0011-horas-de-la-obra/README|SPEC-0011: Horas de la obra]] — 92 tests en el API y 347 en el móvil, PR #32 mergeado; llenó la primera de las dos tabs placeholder de la obra. Trajo `decision_reason` al dominio, las dos operaciones de decisión al lote y **el turno de la bandeja**, que sale de un GRAVE: corregirse a uno mismo sin señal dejaba en el servidor la decisión descartada
- [x] [[specs/mobile/0010-fotos-de-la-obra/README|SPEC-0010: Fotos de la obra]] — 322 tests, PRs #25 y #26; trajo `POST /media/:id/tags` y la escalera de visibilidad aplicada al API. Dos tandas: la segunda salió entera de probar en el teléfono —etiquetar pasó a obligatorio y de a una, y apareció que volver la red no sincronizaba con la obra abierta— y dejó la regla de copy en `code-guidelines/i18n.md`
- [x] [[specs/mobile/0009-la-obra-como-lugar/README|SPEC-0009: La obra como lugar, no como botón]] — 269 tests, PR #20 mergeado; siete tandas de diseño probando en el teléfono, y de ahí salieron `SectionCard`, `StatusLine` y la regla de que el copy no fiscaliza
- [x] [[specs/mobile/0004-capa-local-y-sincronizacion/README|SPEC-0004: Capa local y sincronización]] — cerró con la tanda 2 de SPEC-0008: los dos criterios de `CONFLICT` verificados observando streams
- [x] [[specs/mobile/0001-login-movil/README|SPEC-0001: Login en la app móvil]] — 67 tests, revisado con `code-reviewer`
- [x] [[specs/mobile/0003-arquitectura-de-navegacion/README|SPEC-0003: Arquitectura de navegación]] — 104 tests + 9 de integración, PR #1 mergeado
- [x] [[specs/mobile/0005-proyectos-en-el-movil/README|SPEC-0005: Proyectos en el móvil]] — 226 tests + 2 de integración, PR #7 mergeado; trajo la escalera de estados al API
- [x] [[specs/mobile/0006-clientes-en-el-movil/README|SPEC-0006: Clientes en el móvil]] — 170 tests + 2 de integración, PR #4 mergeado; trajo `site.update` al API
- [x] [[specs/mobile/0008-asistencia-en-el-movil/README|SPEC-0008: Asistencia en el móvil]] — 266 tests, cinco PRs; la escalera de evidencia completa, los conflictos de SPEC-0004 cerrados y la foto subiendo a Backblaze
- [x] [[specs/mobile/0007-ubicacion-de-la-propiedad-en-el-mapa/README|SPEC-0007: Ubicación de la propiedad en el mapa]] — 239 tests en la suite, PR #12 mergeado; trajo Google Maps (ADR-0012), el bundle `com.snapline.app` y dos fixes de sincronización de SPEC-0004 con sus tests de regresión


## 🚧 Bloqueado


%% kanban:settings
```
{"kanban-plugin":"board","show-checkboxes":true}
```
%%
