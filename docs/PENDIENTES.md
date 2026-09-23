---
id: PENDIENTES
title: "Pendientes — qué falta hacer"
type: pendientes
updated: 2026-09-01
tags:
  - pendientes
---

# Pendientes

Lo que falta, ordenado por qué tan caro sale olvidarlo. Las decisiones de producto
y comerciales viven en [[DECISIONES]]; esto es ejecución.

Marcar con `[x]` al completar y borrar la línea cuando ya no aporte contexto.

---

## 🔴 Antes de desplegar

Ninguno bloquea el prototipo: el recorrido corre completo en desarrollo.

- [x] ~~**Crear el bucket de Backblaze de desarrollo.**~~ Hecho el 2026-08-08:
      `snapline-dev` privado en `us-east-005`, con llave acotada a ese bucket.

- [x] ~~**Probar la subida real de punta a punta.**~~ Verificado el 2026-08-08:
      registrar → PUT firmado (200) → `uploaded` → descarga firmada (200), archivo
      idéntico byte a byte. Sin firma el bucket responde `401 UnauthorizedAccess`,
      así que la afirmación de "bucket privado" está comprobada y no supuesta.

- [ ] **Bucket de producción aparte, con su propia application key.** Nunca la
      misma llave que desarrollo: una demo no debe poder escribir sobre las fotos
      reales de un cliente.

      **1. Crear el bucket** (B2 Cloud Storage → Create a Bucket):

      | Campo | Valor | Por qué |
      |---|---|---|
      | Bucket Unique Name | `snapline-prod` | **Con guion, nunca guion bajo** |
      | Files in Bucket are | **Private** | ADR-0010: todo se sirve con URL firmada |
      | Default Encryption | **Enable** (SSE-B2) | Gratis y transparente para el API de S3 |
      | Object Lock | Disable | Vuelve los archivos inmutables y complica el borrado |

      > **El guion bajo rompe.** B2 solo acepta letras, números y `-`, y aunque los
      > aceptara, el cliente arma la URL como `bucket.s3.<region>.backblazeb2.com`:
      > un guion bajo no es válido en DNS y el certificado TLS no haría match. El
      > nombre es único **entre todas las cuentas de B2**.

      **2. Application key** (Account → Application Keys):
      **alcance solo ese bucket**, no "All"; Read and Write; sin *Duration* — un
      vencimiento hace que las subidas empiecen a fallar con 403 sin que nada avise.
      **La `applicationKey` se muestra una sola vez.**

      **3. La región se copia del endpoint que muestra el bucket, no se adivina.**

      > Ya mordió una vez: con la región equivocada Backblaze responde
      > `InvalidAccessKeyId — the key is not valid`, que suena a llave mal copiada y
      > en realidad es región mal puesta. Esta cuenta está en **`us-east-005`**.
      > Para diagnosticarlo, un `HeadBucket` contra cada región dice cuál la acepta.

      **4. Variables** (`STORAGE_ENDPOINT`, `STORAGE_REGION`, `STORAGE_BUCKET`,
      `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY`) — ver `.env.example`.

- [ ] **La cuenta de Backblaze es compartida con ACDEMIC.** El bucket
      `acdemic-attachments` vive en la misma cuenta: la facturación se mezcla y el
      radio de daño de cualquier credencial cruza los dos productos. Revisar antes
      de producción si conviene separar cuentas.

- [ ] **`JWT_SECRET` propio para producción.** El de desarrollo ya es aleatorio
      (se generó el 2026-08-08), pero producción necesita el suyo y **nunca el
      mismo**: `openssl rand -base64 48`.

- [x] ~~**Probar una subida real de punta a punta.**~~ Verificado el 2026-08-08:
      registrar → PUT firmado (200) → `uploaded` → descarga firmada (200), archivo
      idéntico byte a byte. Sin firma el bucket responde `401 UnauthorizedAccess`.

## 🟠 Antes de que crezca la superficie

- [x] ~~**Endpoint de sincronización para el móvil.**~~ Hecho el 2026-08-08.
      `POST /api/sync` sube la bandeja entera en una llamada y `GET /api/sync?since=`
      trae solo lo cambiado.

      Cuatro decisiones que importan: **cada operación va en su propia transacción**
      —una que falle no tira abajo las 39 que entraron—, se ordenan por `occurredAt`
      porque una salida no puede aplicarse antes que su entrada, **reintentar
      devuelve `duplicate` en vez de error** aprovechando que los ids los genera el
      dispositivo, y cada payload se valida contra su DTO: sin eso el lote entraba
      sin la validación que sí tienen los endpoints sueltos.

      El cursor lo da el servidor, no el reloj del dispositivo. Un WORKER solo
      sincroniza sus proyectos asignados.

- [ ] **El porqué de una foto — sobre todo cuando la etiqueta es `PROBLEM`.**
      Hoy tomar una foto guarda la etiqueta y nada más: `media_asset` **no tiene
      un solo campo de texto** —ni caption, ni nota, ni descripción— y la hoja de
      `photo_tag_sheet.dart` solo elige entre las seis etiquetas.

      Una foto de un problema sin una línea que lo explique obliga a reconstruir
      de memoria qué se estaba mirando. Es el caso que lo pide: `BEFORE` y `AFTER`
      se explican solas, un incidente no.

      **Necesita spec, y ficha de dominio antes** (reglas 1 y 2): es un campo
      nuevo en [[domain/contenido|Contenido]], no un ajuste de pantalla. Frente
      `campo`, no `administrativo` — lo escribe quien está parado en la obra, no
      William en la oficina, así que toca `ObraScreen`, que
      [[specs/mobile/0012-avance-de-la-obra/README|SPEC-0012]] deja explícitamente
      sin tocar.

      **No lo cubre la nota de avance de SPEC-0012**, y conviene no confundirlos:
      esa nota es de la obra y la escribe la oficina; esta razón es de la foto y
      la escribe quien la toma. Una foto `PROBLEM` con su porqué es después una
      entrada del hilo de Avance que se lee sola.

      **Trigger:** la próxima tanda de trabajo sobre captura de fotos, o el primer
      problema real que William tenga que explicarle a alguien por teléfono.

- [ ] **Confirmar el tratamiento de sales tax en Maryland** con el contador de
      William. Hoy la tasa es configurable y está en cero. Ver ADR-0001.

- [ ] **Hablar con el contador antes de que salga la primera factura real.**
      Si no acepta los datos, el módulo no sirve por impecable que esté.

- [ ] **CDN delante del bucket** si el sitio público agarra tráfico. B2 cobra
      egreso; hacia la CDN de Cloudflare no. **Trigger:** cuando el portafolio
      público pase de ~10k visitas al mes. Ver ADR-0010.

- [ ] **Cobro con tarjeta.** Hoy solo se registra el pago recibido. Fuera de
      alcance a propósito — ver "Qué NO somos" en [[product/vision]].

- [x] ~~**Rate limit** en endpoints públicos y login.~~ Hecho el 2026-08-08 con
      `@nestjs/throttler`: 120 req/min general, y **8/min en lo que acepta
      credenciales sin autenticación previa** — login, refresh y el portal del
      cliente. Verificado: al cuarto intento contra `/p/:token` responde 429.

- [x] ~~**Tests e2e contra Postgres.**~~ Hecho el 2026-08-08: 21 tests en
      `apps/api/test/`, con `pnpm test:e2e`. Cubren lo que se venía verificando a
      mano con curl —aislamiento entre dos empresas reales, geocerca recalculada,
      tarifa congelada, snapshot de precios, idempotencia de pagos, token del
      portal hasheado— contra el Postgres real, porque los invariantes viven en
      triggers, índices parciales y RLS que un mock no ejercita.

      El seed usa el rol migrador aparte: sembrar con el rol de runtime falla por
      RLS, que es exactamente lo que debe pasar. Y limpiar exige desactivar a
      propósito el trigger que bloquea el borrado de horas.

- [x] ~~**El estado de una dirección exige dos letras, y la app ofrece 16 países.**~~
      Resuelto el 2026-09-03 en la rama de SPEC-0012: `@Length(2, 2)` fuera,
      `@IsNotEmpty()` + `@MaxLength(100)`, label «Estado o provincia» y cinco
      tests en `address.spec.ts`. **Falta el panel**, que tiene el mismo
      `Validators.maxLength(2)` en `address-group.ts` pero vive en la rama
      `feature/web-0009-clientes`. El diagnóstico original:
      `AddressDto.state` lleva `@Length(2, 2)` y el móvil fuerza `maxLength: 2`
      con solo letras (`address_fields.dart:139`), pero
      `supported_countries.dart` ofrece Estados Unidos, Canadá y toda América
      Latina. En Costa Rica la provincia es «Alajuela»; en México, «Jalisco».
      No entran. La app deja elegir el país y después no deja escribir su
      división administrativa.
      *Encontrado el 2026-09-03 probando con una dirección de Costa Rica.*
      **Toca tres superficies** —`AddressDto`, el móvil y el panel— y es
      decisión de dominio antes que de validación: qué es `state` cuando el país
      no es Estados Unidos. La ficha de dominio de la propiedad no lo dice.

- [x] ~~**Un cliente muestra su sección «Obras» y no ofrece crear una.**~~
      Resuelto el 2026-09-03: la acción vive en el `action` del `SectionHeader`
      y abre el alta con el cliente ya puesto.
      Se ve la lista y no hay acción para agregar. Hoy hay que ir a Obras y
      elegir el cliente de vuelta, que es el camino largo del dato que ya estaba
      en pantalla. *Encontrado el 2026-09-03.*

- [x] ~~**«Tomar foto» debería ser un botón flotante en la tab Fotos.**~~
      Resuelto el 2026-09-03: `FloatingActionButton.extended` de 64dp, no los 56
      de Material, porque se pulsa con guantes (ADR-0009).
      Hoy es una acción al pie. *Pedido el 2026-09-03.* Revisar contra la regla
      de las dos alturas de acción primaria: el objetivo de campo son 64dp y un
      FAB de Material mide 56.

- [x] **No hay forma de dar de alta a un trabajador, y sin eso la cuadrilla no
      existe.** ~~Pendiente~~ **Resuelto por SPEC-0011, PR #45 mergeado el
      2026-09-09.** El API tiene `crews` completo —crear cuadrilla, editarla, sumar
      y sacar miembros, designar capataz— y `POST /projects/:id/assignments`
      para asignarla a una obra en una fecha. Lo que **no existe en ningún
      lado** es crear la membresía: no hay `POST /memberships`, ni invitación,
      ni registro. Los tres usuarios de desarrollo existen porque el seed los
      insertó por SQL. Y el móvil no tiene ninguna pantalla de cuadrilla: el
      `CrewsClient` generado no lo llama nadie.
      *Encontrado el 2026-09-03: se entró como Carlos y la app dijo que no tiene
      obra asignada, sin ningún camino para arreglarlo desde la app.*
      Era el spec que desbloqueaba el uso real: hasta acá la app solo la podía
      usar quien ya estuviera en la base. El alta va con un código de seis
      dígitos que se dicta en persona y se canjea en la app, y la asignación de
      la cuadrilla a la obra es un período. Saldó también la deuda declarada de
      `crews`, que se había construido sin spec.

- [ ] **Una nota para el cliente no tiene forma de salir en una obra en modo
      etapas.** Hoy el aviso ofrece cambiar el modo de la obra entera, que es
      todo o nada. Lo pedido es poder **forzar una nota concreta** —o una foto—
      sin abrirle al cliente el avance completo.
      *Pedido el 2026-09-03.* **Necesita decisión de dominio antes que código:**
      el modo `etapas` existe para que el cliente no vea el detalle, así que una
      excepción por nota lo convierte en un default y no en una regla. Hay que
      decidir si `client_visibility_mode` pasa a ser el valor por defecto de cada
      nota, o si aparece una marca aparte en `project_update`. Ver
      `docs/domain/acceso-del-cliente.md`.


## ⚪ Higiene

- [x] ~~**Commitear.**~~ Hecho el 2026-08-08: repo en
      github.com/XnJaca/snapline, **público por ahora**. Auditada toda la historia
      antes de publicar — sin `.env`, sin `brief.md`, sin llaves.

      **Pendiente de decisión:** `DECISIONES.md` quedó público con la estrategia
      de precios y la nota de no mencionarle a William la fase 1. Pasar el repo a
      privado no deshace la exposición: sirve para adelante, no para atrás.

- [ ] **Tres cadenas del móvil siguen en voseo, y el resto de la app es de usted.**
      `todayNoAssignments`, `todayCheerLate` y `obrasSectionAsignadas` dicen
      «no tenés», «no te olvidés» y «estás asignado», contra 31 cadenas en voz
      de usted. Las tres son de las pantallas de campo —Hoy y Obras—, no de
      las que tocó SPEC-0013.

      *Encontrado el 2026-09-22 al reescribir el copy de la hoja de revisión de
      dirección.* Ahí salieron siete más, todas de la pantalla del mapa, y esas
      **ya se corrigieron** en la rama de SPEC-0013 porque era la pantalla que
      el spec estaba tocando. Estas tres quedaron afuera a propósito: cambiarlas
      es tocar dos pantallas que el spec no abre, y sus tests afirman el texto.

      No rompe nada en ejecución. Es la clase de inconsistencia que se nota
      cuando el mismo usuario pasa de una pantalla a otra, y la app le habla de
      dos maneras distintas. **La voz del producto es de usted**, y es la que
      el panel ya reusa del móvil.

- [ ] **El copy del móvil dice "tres etapas" y ahora son cuatro.**
      `projectVisibilityStagesHelpBody`, en `app_es.arb` y `app_en.arb`, describe
      lo que ve el cliente como *"tres etapas: Inicio, En proceso y Finalizado"*.
      El fix del 2026-09-02 que separó `CANCELLED` de `FINALIZADO` agregó una
      cuarta, **Cancelado**, y ese texto quedó desactualizado.

      No se corrigió en la rama del fix a propósito: SPEC-0012 está reescribiendo
      esa misma cadena, así que tocarla ahí era conflicto garantizado. **Se cierra
      con SPEC-0012**, que es quien tiene el texto nuevo en la mano.

      Es copy de ayuda para el contratista, no para el cliente final, y no rompe
      nada en ejecución: es una inexactitud de producto, no un bug.

- [ ] **`apps/web` y `apps/site`** sin scaffold. Al crearlas, agregarlas a
      `pnpm-workspace.yaml` — hoy solo lista `apps/api` y `packages/*`.

- [ ] **CORS en el bucket de Backblaze — cuando el panel suba su primera foto.**
      Subir desde el navegador a una URL firmada dispara un preflight; sin reglas
      de CORS el browser corta la subida antes de que salga del cliente, y el
      error no dice CORS de forma obvia.

      > **El trigger se corrigió el 2026-08-30.** Decía *"solo cuando arranque
      > `apps/web`"*, y arrancar la app no es el momento: SPEC-0007 y SPEC-0008 no
      > suben nada. Lo que lo dispara es la primera pantalla que mande un archivo
      > al bucket desde el navegador, que todavía no tiene spec.

      **Desde Flutter nativo no aplica** — no hay CORS fuera del navegador, por eso
      el prototipo no lo necesita.

      En B2: Bucket Settings → CORS Rules, permitiendo `PUT` y `GET` desde el
      origen del admin, con `content-type` entre los headers permitidos (el cliente
      lo manda firmado). En desarrollo el origen es `http://localhost:4200`; en
      producción, el dominio real. **Nunca `*` en producción.**

- [x] ~~**ADR-0005 — librería de i18n para Angular.**~~ Aceptado el 2026-08-08:
      **Transloco**. Pesaron los catálogos JSON compartidos con Flutter y Astro, y
      el cambio de idioma sin recargar, porque el `locale` es por usuario dentro de
      una misma cuenta. Ya no bloquea `apps/web`.

- [ ] **Verificar el nombre** en App Store Connect, Google Play y USPTO antes de
      registrar bundle ID o dominio. Ver [[NOMBRE]].

---

- [ ] **Los e2e corren contra la misma base que desarrollo.**
      `test/setup.ts` usa `DB_NAME ?? 'snapline'`, igual que `datasource.ts`, y
      no hay `.env.test`. Con el API de desarrollo levantado —o justo después de
      sembrar— la suite puede fallar por interferencia y no por una regresión.
      *Pasó el 2026-09-03: tres tests en rojo en una corrida y verdes en las dos
      siguientes, sin tocar nada en medio.* Un test que falla por el ambiente
      enseña a ignorar los rojos, que es peor que no tenerlo.
      Se cierra con una base propia —`snapline_test`— y su `.env.test`.


## Cómo se mantiene

Este archivo es para lo que **no** tiene lugar en otro lado. Si algo encaja en una
categoría existente, va ahí y no acá:

| Si es… | Va a |
|---|---|
| Una feature | `/spec-new` → `docs/specs/` |
| Deuda técnica con trigger | `/debt-new` → `docs/tech-debt/` |
| Una decisión que cuesta revertir | `/adr-new` → `docs/adr/` |
| Un pendiente comercial o de relación | [[DECISIONES]] |
