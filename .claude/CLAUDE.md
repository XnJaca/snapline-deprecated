# CLAUDE.md — Snapline

> [!WARNING]
> **Proyecto deprecado el 2026-09-23.** Congelado, se rearranca desde cero.
> Las reglas de abajo siguen siendo correctas y son lo que hay que llevarse al
> proyecto nuevo, sobre todo las del dominio (9 a 20). Ver la entrada del
> 2026-09-23 en `docs/DECISIONES.md`.
>
> **No se implementa nada nuevo acá.**


## Qué es Snapline

Software de gestión para el contratista que no tiene oficina, que cierra el ciclo
publicando la obra terminada en su web y sus redes.

Dos cosas a la vez, ninguna funciona sola: **se usa sin entrenamiento** y **la foto
termina publicada**. Ver `docs/product/vision.md`.

Design partner: William Ferman, Professional Construction LLC, Maryland.

## Estado

Monorepo pnpm + Turborepo. Alcance reestructurado el 2026-08-08.

`apps/mobile` — **438 tests**. La obra completa: sus cuatro tabs —Avance, Fotos,
Horas y Detalle—, el marcaje de asistencia, clientes y propiedades con su mapa, y
la capa local con su bandeja de salida. Ninguna tab de obra usa ya `Placeholder`;
lo que queda de andamiaje son los ejes que todavía no tienen spec.

`apps/web` — el panel, con clientes y propiedades (SPEC-0009), obras (SPEC-0010) y
**el alta de trabajadores con sus cuadrillas y asignaciones** (SPEC-0011). 92 tests.
`apps/site` sin scaffold.

`apps/api` — esquema completo (35 tablas, 35 entities, RLS en 30), **92 endpoints**,
110 tests unitarios y 95 e2e:

| Módulo | Estado |
|---|---|
| auth · customers · projects · media · time-entries | Completo |
| crews · memberships | Completo — SPEC-0011 lo escribió retroactivamente |
| catalog · billing · reports | Completo, **sin spec** — ver deuda abajo |
| publishing | Completo — publicar, antes/después, feed público y de redes |
| client-portal | Completo — magic link y las cinco rutas del portal |

Lo único que separa la demo de tener fotos reales: **cargar las credenciales de
Backblaze**. Todo lo demás del recorrido corre. Ver `docs/PENDIENTES.md`.

**Deuda declarada:** catalog, billing y reports se construyeron sin spec, contra la
regla 2. Escribirlos retroactivamente antes de que la superficie crezca. `crews` ya
salió de esa lista: SPEC-0011 lo cubrió al usarlo desde el panel.

## Stack

| Capa | Tecnología | Directorio |
|---|---|---|
| Backend | NestJS + PostgreSQL | `apps/api/` |
| Móvil | Flutter (iOS + Android) | `apps/mobile/` |
| Admin web | Angular | `apps/web/` |
| Sitio público | Astro consumiendo el mismo API | `apps/site/` |
| Contrato | Tipos generados desde `openapi.json` | `packages/contracts/` |

**Flutter está adentro del repo pero fuera del workspace de pnpm** — pub y pnpm no
se mezclan. Consume el contrato generando modelos Dart desde `openapi.json`.

Fotos en **Backblaze B2** vía su API compatible con S3 (ADR-0010). El bucket no es
público: todo se sirve con URL firmada y de vida corta.

## Docs de lectura obligatoria

Antes de implementar cualquier cosa:

| Archivo | Qué contiene |
|---|---|
| `docs/product/vision.md` | Tesis, los cinco frentes, y **"Qué NO somos"** — el gate duro |
| `docs/product/roadmap.md` | Orden de construcción y lo descartado |
| `docs/domain/` | Un agregado por ficha; las reglas transversales en su `README` |
| `docs/DECISIONES.md` | Decisiones tomadas y estado comercial |
| `docs/PENDIENTES.md` | Qué falta hacer y qué bloquea qué |
| `docs/adr/` | Decisiones arquitectónicas con su porqué |

Cuando `DECISIONES.md` y `docs/product/vision.md` se contradigan, **gana la visión**.

---

## Reglas duras

### 1. No inventar dominio

Si una entidad, flujo o regla no está en `docs/domain/` o en un spec, **preguntar antes de implementar**. No deducir el modelo del código.

### 2. Specs antes de código de feature, y todo spec tiene un `goal`

Una feature sin archivo en `docs/specs/web/` o `docs/specs/mobile/` no se implementa.
Si pido implementar sin spec, **detenerme**. Usar `/spec-new <título>`.

El campo **`goal`** del frontmatter es obligatorio: una sola frase, en presente,
verificable leyendo código. Es contra lo que el `code-reviewer` valida después lo
implementado, así que "mejorar la gestión de fotos" no es un goal — deja al revisor
sin nada que comprobar.

Excepción: scaffold inicial, configuración y chores no necesitan spec.

### 3. BOARD obligatorio en cada transición

El `status` del frontmatter es la única fuente de verdad; el BOARD lo refleja.
**Se tocan los dos en el mismo acto**, nunca después.

| Evento | Transición |
|---|---|
| `/spec-new` crea el spec | Backlog → **Borrador** |
| Spec completo | Borrador → **Review** |
| Aprobado | Review → **Aprobado** |
| Empieza la implementación | Aprobado → **En implementación** |
| PR mergeado + criterios `[x]` | En implementación → **Implementado** |
| Aparece un bloqueador | cualquiera → **Bloqueado** (con razón entre paréntesis) |

Media feature mergeada no es Implementado.

### 4. ADRs para decisiones que cuesta revertir

Stack, librerías principales, patrones de seguridad, estrategia de deploy, cambios
estructurales del modelo → ADR en `docs/adr/NNNN-slug/README.md`. Usar `/adr-new`.

Si la decisión se revierte en una tarde, no es ADR.

### 5. Deuda técnica se registra, no se deja como TODO

Cuando se posterga algo a conciencia, va a `docs/tech-debt/` con severidad, origen,
workaround actual y **trigger** — el evento concreto que la despierta. Usar `/debt-new`.

No cuenta como deuda: bugs (son tickets), features del roadmap (van a specs),
TODOs locales de implementación (viven en el código).

### 6. `company_id` en toda tabla, y el scope en el guard

Sin excepción, desde la primera migración. El filtro por tenant va en un repositorio
scoped, no repetido en cada query. Si una consulta necesita cruzar tenants, se marca
explícitamente y se audita.

Barato hoy, carísimo después con datos reales adentro.

### 7. Default deny en endpoints

Todo endpoint declara su permiso explícitamente. Sin declaración → 403.
Roles: `OWNER`, `ADMIN`, `FOREMAN`, `WORKER`, `ACCOUNTANT`. El cliente final no es
un rol de membresía — entra por token, con su propio camino.

### 8. Contrato primero, y `openapi.json` es la fuente

El shape de request y response se define en el DTO antes de tocar el controller.
Los tres consumidores (Angular, Flutter, Astro) se adaptan después, no al revés.

`openapi.json` en la raíz es la **fuente única del contrato**: lo emite el API desde
sus DTOs y de ahí salen los tipos de TS y los modelos de Dart. Ver ADR-0007.

**Regenerarlo es parte de la definición de "endpoint terminado"**:

```bash
pnpm contracts:generate
```

Un endpoint nuevo sin `openapi.json` actualizado deja a Flutter con modelos viejos
y nadie se entera hasta producción.

**Lo que se devuelve también es contrato.** El plugin introspecciona `.dto.ts` y
`.entity.ts`; un tipo de respuesta declarado en otro archivo —una interfaz suelta en
un `.service.ts`, por ejemplo— sale al spec como `{"type":"object"}` sin
propiedades, y el cliente generado lo tipa como `dynamic`: parsea la respuesta,
descarta todo y **no falla**. Si un handler devuelve algo que no es DTO ni entity,
declararlo con `@ApiOkResponse({ type: ... })`.

Campos sensibles que igual viven en una entity (`passwordHash`, `tokenHash`) van con
`@ApiHideProperty()`: no deben aparecer ni como documentación.

**Los errores también son contrato** (ADR-0011). Todos tienen la misma forma, y el
campo que importa es `code`: estable, en `SCREAMING_SNAKE`, **nunca traducido**. Un
`throw` que el cliente necesite distinguir de otro del mismo status usa `ApiError`
con su código; si solo se muestra el texto, alcanza el genérico.

Cuando el rechazo venga de un trigger o un índice de la base, mapearlo en
`http-exception.filter.ts` para que llegue con el mismo código que si lo hubiera
atajado el servicio.

---

## Reglas del dominio

Estas salen de este producto en particular. Romperlas produce bugs que se
descubren tarde y se arreglan caro.

### 9. Marcar asistencia nunca puede fallar

Sin red, sin GPS, sin permiso de cámara: se registra igual con lo que haya y se
marca con una bandera. Un trabajador que no puede fichar deja de usar la app el
primer día, y ahí se cae el frente entero.

### 10. Todo lo capturado en campo lleva dos marcas de tiempo

`device_recorded_at` y `server_received_at`. Nunca son la misma con señal
intermitente, y confundirlas convierte los timesheets en ficción.

### 11. `is_mock_location` se guarda siempre

Android permite falsear el GPS con una app gratis. Si no se registra la bandera,
la geocerca es teatro.

### 12. Las horas no se borran ni se sobrescriben

Toda corrección deja rastro: quién, cuándo, valor anterior. Esto es defensa legal
en una disputa de horas, y esas disputas pasan.

Un conflicto de sincronización en `time_entry` **no se resuelve solo** — se marca
y lo revisa un humano. Última escritura gana aplica a todo lo demás, a esto no.

### 13. La tarifa se congela al aprobar

`pay_rate_cents` se copia al `time_entry` cuando se aprueba. Si sube el pago en
octubre, las horas de septiembre no pueden recalcularse solas.

### 14. Las líneas de estimado y factura copian, no referencian

`name`, `description`, `unit`, `unit_price` y `taxable` se guardan **como valor**
en la línea. Referenciar el catálogo vivo significa que cambiar un precio reescribe
facturas del año pasado.

Se guarda también el `service_item_id`, pero solo para reportes.

### 15. Dinero en enteros de centavos

Nunca punto flotante. Columna con sufijo `_cents`, siempre.

### 16. Numeración de documentos con contador por empresa

Contador propio con lock de fila, no `SERIAL` global. Los números de factura de
una empresa no pueden saltar porque otra empresa insertó.

Una factura enviada no se edita: se anula y se emite otra.

### 17. Publicar exige EXIF limpio

`visibility = PUBLIC` requiere `exif_stripped_at` no nulo en las fotos, y la regla
vive **en la base de datos**, no en una validación de formulario. Las fotos llevan
coordenadas GPS porque la app captura ubicación a propósito: publicarlas expone la
dirección exacta de la casa de un cliente.

La visibilidad es una escalera: `INTERNAL` → `CLIENT` → `PUBLIC`.

Esta regla pedía el **photo release del cliente** hasta el 2026-08-12. Se retiró
—no hay permiso del cliente que habilite publicar, la decisión es de la empresa— y
el número se conserva con el invariante que sí sobrevive. Ver DEBT-0005 y la
entrada de esa fecha en `docs/DECISIONES.md`.

### 18. IDs UUIDv7 generados en el cliente

Sin esto no hay offline real: el dispositivo crea el registro con su ID definitivo
y no hay que reconciliar IDs temporales al sincronizar.

### 19. Escrituras idempotentes desde móvil

Toda mutación lleva clave de idempotencia. La red se cae a mitad de un POST y el
reintento no puede duplicar.

### 20. Borrado suave en todo lo que sincroniza

Un borrado duro no se puede propagar a un dispositivo que estuvo sin señal.

---

## Reglas de UI

Estas no son preferencias de estilo. Cada una corrige algo que ya salió caro antes.

**Antes de escribir una línea de CSS de una pantalla nueva, leer
`docs/code-guidelines/estilos-y-temas.md` y abrir la pantalla equivalente que ya
existe.** El sistema está construido; el error caro no es elegir mal un valor, es
no darse cuenta de que la decisión ya estaba tomada. Ver también
`docs/code-guidelines/i18n.md`, `PRODUCT.md` y `DESIGN.md` en la raíz.

### 21. Angular: tres archivos, siempre

Todo componente es `.ts` + `.html` + `.scss` separados, con `templateUrl` y
`styleUrls`. **Nunca `template:` inline. Nunca `styles: []` inline.**

Sin excepción por "es un componente chiquito" — ese es exactamente el que crece.
En ACDEMIC los estilos terminaron dentro del archivo de lógica y dejaron de ser
buscables, reutilizables y auditables. No se repite.

Lo mismo en Flutter: los widgets no llevan valores de estilo literales, consumen
el tema.

### 22. Los estilos viven arriba, no en el componente

Tokens globales de color, espaciado, tipografía, radios y sombras, definidos como
variables CSS. El componente **consume tokens, no valores**.

**Un hex literal en el archivo de un componente es un error de revisión.** Si un
token no existe para lo que se necesita, se agrega al sistema — no se hardcodea
y se sigue. Un `line-height` literal cuenta igual.

**El sistema se consume entero, y a veces está a medias.** Dos formas de romperlo
sin escribir un solo literal, las dos encontradas el 2026-09-04:

- **Un `font-size` sin su `line-height` hermano** hereda el de Material — un único
  20px para los cuatro tamaños de la escala, con el título de 20px en ratio 1.00.
  Los `--sl-font-leading-*` existen: se usan siempre, en la misma regla.
- **El atajo compuesto de Material no se recompone.** Pisar `body-medium-size` deja
  `--mat-sys-body-medium` diciendo el valor viejo, y las dos variables conviven en
  desacuerdo. Se consumen las **piezas**, nunca el atajo.

### 23. Modo claro y oscuro desde el primer componente

Los dos temas se definen el día uno, como tokens. Un componente que solo se ve
bien en claro está sin terminar.

No es cosmético en este producto: la misma app se usa en un techo con sol directo
y en un sótano sin luz. Retrofitear el modo oscuro después significa tocar todos
los componentes, uno por uno.

### 24. i18n obligatorio — cero cadenas quemadas

**Ningún texto visible al usuario se escribe literal** en un `.html`, `.ts` o
`.dart`. Todo pasa por la capa de traducción con su clave.

Incluye labels, botones, placeholders, mensajes de error y validación, títulos,
tooltips, estados vacíos y el texto de las notificaciones push.

Fechas, moneda y números se formatean por la capa de i18n, nunca concatenando
a mano. `$` + número es un bug esperando el primer cliente que no facture en dólares.

Idiomas desde el inicio: **inglés y español**. William administra en inglés y es
probable que sus trabajadores usen la app en español — el `locale` es por usuario,
no por empresa.

### 25. Nada flota, y lo equivalente se alinea

Ningún campo, título ni bloque se apoya sobre el fondo de la página: todo vive
sobre una superficie con borde, radio y fondo, **a ancho completo**. Nada se acota
con un `max-width` propio, o queda una franja muerta al costado.

En una grilla, **las zonas equivalentes de elementos vecinos arrancan a la misma
coordenada**. Igualar la caja exterior no alcanza: si el bloque de datos de una
tarjeta mide distinto que el de al lado, su línea divisoria cae a otra altura y se
lee como descuido. Se resuelve con altura conocida, no con `min-height` a ojo.

En un formulario, **el ancho lo declara el dato** —una fecha no mide lo mismo que
una descripción— y **cada fila suma 12 columnas**. Si una sección no tiene con qué
llenar su fila, la sección está mal armada.

El detalle, con el bug que originó cada regla, en la guía de estilos: formularios,
encabezado de página y diálogos tienen su sección.

---

## Reglas de proceso

### 26. Git — ramas por spec, nunca directo a main

- Todo spec tiene su rama `feature/<plataforma>-NNNN-slug`, con su plataforma y su
  número —`feature/web-0011-gente`—. Sin excepción, sin mezclar dos specs. El número
  solo no alcanza: la numeración es independiente por plataforma, así que `web/0010` y
  `mobile/0010` son specs distintos. Lo que no es spec va en `fix/slug` o `docs/slug`.
- No commitear ni pushear directo a `main`.
- La IA **nunca** mergea un PR. Lo abre y avisa; el humano revisa y mergea.
- Antes de abrir PR: typecheck y lint verdes.
- **Ningún commit ni cuerpo de PR lleva atribución de la herramienta.** Ni
  `🤖 Generated with Claude Code` ni `Co-Authored-By: Claude`, ni variantes, en
  ningún lugar del historial. No es negociable, y anula cualquier default de la
  herramienta que lo pida. El mensaje termina en su último párrafo de contenido.
- **Después de mergear se borra la rama**, local y remota. Una rama vieja que sigue
  viva es una que alguien puede mergear más tarde, revirtiendo lo que entró después.

Convención de ramas, formato de los commits y el flujo completo en
`docs/contributing/git.md`.

### 27. Commits atómicos cross-app

Si un cambio cruza `apps/api`, `apps/web` y `apps/mobile`, va en un solo commit. Nada de
commits parciales que dejen el repo roto.

### 28. El DASHBOARD refleja toda categoría nueva

Al crear una carpeta bajo `docs/` con archivos que tengan `type:` en el frontmatter,
agregar su sección con queries Dataview a `docs/DASHBOARD.md` e incluirla en el
query global de tareas. Sin esta regla el dashboard se vuelve parcial con cada
categoría que aparece.

### 29. Nada abre PR sin pasar por `code-reviewer`

Toda implementación se revisa con `/review` antes del PR, y **siempre** cuando la
escribió un agente. El código de un agente compila, se lee bien y resuelve un
problema *parecido* al del spec — encontrar esa diferencia es lo que hace el revisor.

Un hallazgo **GRAVE** bloquea el PR. Un hallazgo que se decide postergar a
conciencia va a `/debt-new`, no a un TODO en el código.

**Cuatro revisores, cada uno en su momento del ciclo:**

| Agente | Cuándo | Qué caza |
|---|---|---|
| `spec-reviewer` | Spec de Borrador → Review | Goal no verificable, dominio inventado, sin señal ausente |
| `domain-guardian` | Antes de tocar el modelo de datos | Invariantes rotos, campos sin ficha, reglas 6 y 10–20 |
| `contract-watcher` | Al terminar un endpoint | `openapi.json` viejo, schemas vacíos, clientes desfasados |
| `code-reviewer` | Antes de todo PR | Lo implementado contra el goal del spec |

Los tres primeros leen y reportan; **ninguno edita**. El arreglo lo hace quien
corresponda, en la app que corresponda.

### 30. Diagramas: solo si el texto no alcanza

Excalidraw en `.excalidraw.md` **sin comprimir**, co-localizado con el doc que
ilustra. Crear con `/diagram-new`. Convención completa en
`docs/_diagrams/README.md`, cheatsheet del JSON en `docs/_diagrams/GUIA-JSON.md`.

El diagrama es **visual puro**: cajas con nombre y 2-4 campos clave, grupos con
background suave, flechas curvas con cardinalidades. **Cero texto duplicado del MD
que lo embebe.**

**Si el diagrama termina siendo "el MD pero en cajas", no se hace.** Un diagrama
redundante envejece peor que el texto, porque nadie lo actualiza cuando cambia la
decisión que ilustraba.

`docs/domain/mapa-dominio.excalidraw.md` es el mapa canónico: **todo agregado nuevo
recibe su caja ahí**, con `link` a su ficha.

### 31. CLAUDE.md locales mandan en su carpeta

Cada app tendrá el suyo con sus convenciones de testing, estructura y naming.
Dentro de esa carpeta, ese archivo gana sobre este.

---

## Idioma

Documentación, specs y commits en **español**. Código en **inglés**: variables,
tablas, columnas, endpoints, tipos.

**Comentarios: en español, pocos y solo cuando hacen falta de verdad.** Todo lo
explicativo —el porqué de una decisión, el contexto de negocio, los invariantes
del dominio— vive en los specs y en `docs/`, no en el código. Un docblock que
narra reglas de negocio duplica el spec y se desactualiza sin que nadie lo note.

Se comenta solo cuando el código engañaría al lector sin la nota: que un campo lo
deriva el servidor y no se acepta del cliente, que un valor está congelado a
propósito. **Si la explicación pasa de dos líneas, pertenece al spec.**

La app se usa en Maryland: la UI necesita español e inglés desde el diseño, y el
`locale` es por usuario, no por empresa. Es probable que los trabajadores la usen
en español y William el admin en inglés.

## Estilo de trabajo

- Preguntar cuando la respuesta cambia el diseño. Decidir cuando hay un default sensato.
- No implementar de más. El alcance del spec es el alcance.
- Si algo del spec está mal, decirlo en dos líneas y seguir — no rediseñar por cuenta propia.

## Context7

Para documentación de librerías (NestJS, Angular, Flutter, Prisma/TypeORM, Astro),
usar Context7 antes de responder de memoria.

## Qué NO hacer

- No implementar features sin spec.
- No inventar entidades ni campos que no estén en el modelo.
- No agregar dependencias sin justificarlas.
- No tocar `docs/DECISIONES.md` para borrar historia — se agregan entradas, se
  tachan las anuladas con su fecha y motivo.
- No mergear PRs.
