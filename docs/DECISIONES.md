# Decisiones tomadas y pendientes

Contexto para arrancar sin repetir discusiones. Última actualización: 2026-09-23.

## El proyecto se depreca y se rearranca — 2026-09-23

**Snapline queda congelado.** No se abandona la idea: se abandona esta
construcción. @jaca lo decidió después de recorrer la app completa en su
teléfono, sobre una base vacía, creando todo desde cero como lo haría William.

**El motivo, textual:** *"el diseño y los flujos se me hacen demasiado confusos,
realmente no me siento como usándolo"*.

Esa frase es el veredicto contra la tesis número uno del producto, la que la
visión pone primera: **se usa sin entrenamiento**. Si el dueño del producto,
que conoce cada pantalla porque las especificó, no se siente usándola, un
contratista de dos cuadrillas tampoco. Nada de lo que sigue importa si eso
falla, y falló.

### Qué no es el motivo

No se cayó por calidad de ejecución ni por deuda técnica. Al congelarlo:

| | |
|---|---|
| Commits | 221 |
| Specs | 24, todos revisados antes de codear |
| ADRs | 16 |
| Deuda registrada | 18 fichas, con su disparador |
| Tests | 503 en el móvil, 205 en el API, 92 en el panel |

El API está entero: 92 endpoints, RLS en 30 tablas, publicación y portal del
cliente incluidos. Las fotos suben a Backblaze de verdad. El proceso funcionó:
los revisores atajaron un GRAVE el último día, y cada regla dura evitó el bug
que decía que iba a evitar.

**Lo que falló fue el producto, no el código.** Se construyó pantalla por
pantalla contra specs correctos, y el conjunto no se siente como una
herramienta. Un spec verifica que lo implementado hace lo que dice; ninguno
verifica que las quince pantallas juntas se sientan como una sola cosa.

### Qué rescatar cuando se rearranque

Esto es lo que no hay que volver a pensar:

- **El modelo de dominio.** Las 35 tablas y sus invariantes salieron de
  conversaciones reales con William, no de suposiciones. Las reglas 9 a 20 del
  `CLAUDE.md` —marcar nunca falla, dos marcas de tiempo, la tarifa se congela al
  aprobar, las líneas copian y no referencian— son caras de descubrir y baratas
  de copiar.
- **Los cinco ADRs de fondo:** RLS desde el día uno, `openapi.json` como fuente
  del contrato, Backblaze con URL firmada, el envelope de errores, y el
  geocodificador del sistema en vez del SKU pago.
- **La evidencia del brief**, incluida la contradicción del portal del cliente,
  que William refutó con un *"no mandamos fotos"* y que entró igual por decisión
  de producto.
- **Lo que se probó este día**: los seis hallazgos de la tanda de QA, que son
  exactamente los lugares donde el flujo se siente confuso.

### Qué hacer distinto

La lección que deja, y que el proceso nuevo tendría que atacar: **el recorrido
completo no se probó hasta el final.** Cada spec se verificó solo, y recién al
encadenarlos sobre una base vacía apareció que el conjunto no se sostiene. Un
recorrido de punta a punta, en un teléfono, antes de la tercera pantalla, habría
dado esta misma señal meses antes.

### Estado del repositorio

Se congela como está, sin borrar nada. Queda público en
`github.com/XnJaca/snapline` con su historia completa, que es el valor que
sobrevive.



## El photo release sale del producto — 2026-08-12

**Publicar una obra no requiere permiso del cliente.** El gate que exigía
`customer.photo_release_granted_at` para llegar a `PUBLIC` se elimina: columnas,
triggers, endpoint y pantalla. Ejecuta [DEBT-0005](tech-debt/0005-photo-release-se-quita.md).

El razonamiento: el contratista está autorizado a fotografiar la obra en la que
trabaja, la decisión de publicarla es suya, y **no hay dónde subir un permiso
firmado** — ni pantalla, ni flujo, ni intención de construirlos. Un campo que solo
se puede otorgar por API es un gate que en la práctica bloquea a todos.

Se decidió con el contraargumento sobre la mesa, que queda anotado: el gate no
impedía tomar fotos ni mostrárselas al cliente, solo publicarlas, y lo que evitaba
es que la casa de alguien termine en Instagram sin que nadie lo haya pensado. El
problema que produce sacarlo se descubre tarde, con la foto ya publicada.

Lo que **sí** queda protegido en la base de datos, ocupando el lugar que deja el
trigger: **`PUBLIC` exige `exif_stripped_at`** en las fotos. Publicar las
coordenadas GPS de la casa de un cliente es la fuga concreta, y esa sigue cerrada
por esquema y no por formulario. La regla 17 del `CLAUDE.md` se reescribió con ese
contenido, conservando su número.

Consecuencias: la ficha de [[domain/cliente|cliente]] pierde el campo y sus dos
eventos, [[domain/contenido|contenido]] cambia de invariante, y el código de error
`PHOTO_RELEASE_REQUIRED` se retira del contrato — el ejemplo de
[ADR-0011](adr/0011-envelope-de-errores/README.md) lo conserva como registro
histórico. Si un cliente pide que bajen su obra, se despublica: la decisión es
reversible, solo que no vive en un campo del cliente.

## Roles de membresía — 2026-08-10

Las dos preguntas que `product/vision.md` tenía abiertas quedaron resueltas, y la
respuesta a las dos fue la misma: **el sistema soporta las dos formas, no elige
una.**

| Pregunta | Decisión |
|---|---|
| ¿Hay alguien más que administre? | **`ADMIN` se queda y deja de ser un rol sin usar.** Tiene que funcionar igual si administra William solo o si aparece una segunda persona. Lo que no puede pasar es que la app **exija** un `ADMIN`. |
| ¿Las cuadrillas tienen encargado fijo? | **`FOREMAN` se queda, y el encargado puede ser el dueño.** Se designa a alguien, o el dueño mismo lo es. |

Ninguna de las dos toca el modelo: `crew.foreman_membership_id` ya apunta a
cualquier membresía, y la ficha de cuadrilla dice que ser encargado *"no es un rol
ni un permiso"*. Un `OWNER` que sea `crew_member` puede liderar su cuadrilla.

### Quién ficha por otra persona

| Quién | Decisión |
|---|---|
| `OWNER` y `ADMIN` | **Sin acotar.** William va a la obra a cargo de una cuadrilla; hacerlo depender de estar cargado como miembro de una cuadrilla formal es la burocracia que este producto no puede pedir. |
| `FOREMAN` | **Criterio: la obra, no la cuadrilla.** Quien fue a la obra ese día ficha por quien también fue — `project_assignment` con su `work_date`. Resuelve sola la cobertura entre encargados. |
| Cómo se aplica | **Bandera, no bloqueo.** Una asignación sin cargar dejaría a la cuadrilla sin fichar, y la regla 9 no lo permite. Se registra igual y se marca; la aprobación del dueño —que el `FOREMAN` nunca tuvo— recibe algo concreto que mirar. |

Se puede endurecer a bloqueo cuando la asignación del día se cargue de rutina. **Al
revés no se puede**, y de ahí el orden. Va al spec de asistencia, que no existe aún.

**Dos cosas del rastro que quedaron anotadas** en `product/vision.md`, las dos
afectan a la regla 12: `method` dice `FOREMAN` aunque fiche el dueño, y el pull de
`/sync` acota solo al `WORKER` — un `FOREMAN` baja todas las horas de la empresa con
la tarifa de cada uno.

## Reunión con William — 2026-08-08

Describió su día a día y el alcance cambió de raíz. **El alcance nuevo vive en `product/vision.md` y `product/roadmap.md`; el modelo de datos en `domain/`.** Lo de abajo se conserva por el histórico; donde haya contradicción, gana la visión.

Lo que dijo, textual en lo esencial:

1. Todo arranca en un proyecto: información del cliente → descripción → carpeta de fotos y documentos.
2. **Control de gente.** Tiene dos cuadrillas y se le vuelve un desorden: no sabe cuántos mandó a cada proyecto, no controla horas ni asistencia, y después tiene que juntarlo todo a mano para mandárselo al contador y hacer payroll.
3. **Usa QuickBooks** para clientes, estimados y facturas, pero aprenderlo le resulta demasiado tedioso. Termina estimando e ingresando productos y servicios a mano.

No es solo él: varios del gremio están igual.

### Decisiones de esa reunión

| Decisión | Elegido |
|---|---|
| QuickBooks | **Reemplazar.** Estimados y facturas nativos. |
| Superficies | **Flutter móvil + Angular admin**, como ya estaba. |
| Asistencia | **Geocerca + foto al marcar.** Registra evidencia y levanta bandera; no bloquea. |
| Portal del cliente | **Link ahora, cuenta opcional.** |

**Publicar hacia afuera sigue siendo la premisa de venta.** Operaciones no la reemplaza, la alimenta: la foto llega etiquetada por proyecto, cliente y servicio en vez de suelta por WhatsApp. Ahí se cierra el ciclo — William publica a su web sin intermediario y de esa misma fuente sale el contenido de redes que ya se le cobra.

**Queda anulada la frase "esto no es un sistema de operaciones"** del README anterior. Lo que William pidió es exactamente eso. Se anula a conciencia, no por deriva.

## Arquitectura

**Un solo backend sirve al producto y al cliente.** El Nest API con Postgres es el núcleo. El admin en Angular *es* el panel que se le vendió a William como fases 1–3. Flutter consume el mismo API. El sitio pcdmv.com se queda estático en Astro y consume ese API para publicar.

Esto evita construir el mismo CRUD dos veces y hace que lo que paga William financie el núcleo del producto en vez de un panel desechable.

**`company_id` en todas las tablas desde el día uno.** Sin multi-tenancy completa —nada de subdominios, roles ni facturación— pero la columna y el scope en el guard van desde el inicio. Misma lógica que el cliente en proyectos: barato hoy, carísimo después con datos reales adentro.

~~**Cloudflare R2 para las fotos, no S3.**~~ **Reemplazado el 2026-08-08 por Backblaze B2** — ver [ADR-0010](adr/0010-backblaze-b2-para-fotos/README.md). El argumento de R2 era el egreso sin cobro; pesó más el costo de almacenamiento, que es la partida que crece con el archivo histórico. S3 sigue descartado.

**Funcionar sin señal es requisito, no lujo.** Obras sin cobertura, sótanos, techos. CompanyCam lo incluye desde su plan de entrada. Las fotos se guardan local y suben cuando haya red. No construirlo en la v1, pero que el diseño lo contemple.

## Orden de construcción

La demo para William no necesita el admin de Angular. Necesita que vea en su teléfono: entrar, crear un proyecto, tomar una foto, verla ahí.

1. **Nest + Postgres** — esquema y endpoints de auth, projects y photos
2. **Flutter** — solo ese flujo, como si fuera producto final.
3. **Angular admin** — después; es la fase 1 que se le cobra
4. **Astro consumiendo el API** para publicar en pcdmv.com

## Estado comercial

- **William Ferman** (Professional Construction LLC, Maryland) es el design partner. Usa la app gratis durante el desarrollo.
- Ya paga **$300/mes** por redes y pagó **$600** por su sitio web.
- Se le cotizó el panel en **$1,600 en 3 fases**: servicios $800, proyectos $500, reseñas $300. Mitad al iniciar y mitad al entregar cada fase, y se vendieron como independientes entre sí(aun no ha decidido la compra).
- Ofreció **contactos en el gremio y sociedad**. Nada firmado. La recomendación es comisión de por vida sobre clientes que traiga (20–30%) y sociedad formal solo cuando haya facturación real ( esto es idea mia, no le he propuesto nada hasta mostrarle una demo ).
- **Prototipo comprometido para la semana del 2026-08-10**, con llamada para mostrárselo.

## Pendientes que no se pueden olvidar

- [ ] **Quitar la cláusula de la base de datos** del bloque de condiciones que se le va a mandar a William. Decía que la BD y el almacenamiento iban a nombre de él y por su cuenta; con este cambio de arquitectura la infraestructura es propia. Todavía no se le ha enviado ese bloque.
- [ ] **Mantener sí o sí la cláusula de propiedad de datos:** todo lo que él cargue (fotos, textos, servicios, proyectos, datos de sus clientes) es suyo y se le entrega cuando lo pida; el sistema es una herramienta propia bajo licencia de uso. Ahora que sus datos viven en infraestructura ajena, esa cláusula importa más, no menos.
- [x] ~~**En la fase 2, "cliente" es un campo del proyecto, no un módulo de gestión de clientes.**~~ **Anulado el 2026-08-08.** Con estimados, facturas y portal del cliente, ahora sí es un módulo con entidad propia. Ojo con lo comercial: lo que se le cotizó a William como fase 2 por $500 ya no es lo mismo que se va a construir.
- [ ] **Hablar con el contador de William antes de construir facturación.** Si él factura desde la app, ese contador tiene que aceptar los datos. Es la conversación más barata del proyecto y la que más cuesta si se salta.
- [ ] **Confirmar el tratamiento de sales tax en Maryland** para servicios de mejora de propiedad, con ese mismo contador. No inventarlo: dejarlo escrito en `domain/factura.md`.
- [ ] **Consentimiento firmado de ubicación** para los trabajadores, en el onboarding. Registrar GPS de empleados sin consentimiento informado no es una opción.
- [x] ~~**Photo release del cliente como cláusula del estimado.** El sistema ya bloquea publicar sin ella; falta el papel.~~ **Anulado el 2026-08-12** — el gate salió del producto entero, ver la entrada de esa fecha arriba. No hay cláusula que agregar porque no hay nada que habilitar.
- [ ] **Revisar el precio.** Si reemplaza QuickBooks y le arma el paquete del contador, el sistema vale bastante más que las tres fases de $1,600 que se cotizaron. No se le cambia el precio a lo ya vendido, pero el producto no se cotiza contra eso.
- [ ] **Verificar el nombre** en App Store Connect, Google Play Console y USPTO. Ver `NOMBRE.md`.
- [ ] **No mencionarle a William** que la fase 1 es también la base del prototipo. Para él son dos proyectos separados.


Brief completo del producto: `product/brief.md` — **documento interno, fuera de git a propósito**.
