---
id: SPEC-0013
title: "El punto se fija al crear la propiedad"
aliases:
  - "SPEC-0013: El punto se fija al crear la propiedad"
type: spec
platform: mobile
status: implementado
goal: "Fijar el punto en el mapa es parte del alta de la propiedad —la misma hoja, una sola operación `site.create`, la dirección rellenada desde el punto sin pisar lo escrito a mano, una búsqueda que lleva la cámara a una dirección sin fijar nunca el punto, y en una propiedad ya guardada mover el punto ofrece actualizar su dirección comparándola campo por campo—, y toda obra cuya propiedad no tiene punto lo dice y ofrece fijarlo ahí mismo, tanto en su alta como en su tab Detalle."
apps:
  - mobile
depends_on:
  - "0007-ubicacion-de-la-propiedad-en-el-mapa"
  - "0005-proyectos-en-el-movil"
domain:
  - cliente
frente: campo
created: 2026-09-22
updated: 2026-09-23
tags:
  - spec
  - spec/implementado
  - mobile
---

# SPEC-0013: El punto se fija al crear la propiedad

> **Meta**
> - Apps afectadas: `mobile`
> - Depende de: [[../0007-ubicacion-de-la-propiedad-en-el-mapa/README|SPEC-0007]], [[../0005-proyectos-en-el-movil/README|SPEC-0005]]
> - Frente: campo — ver [[vision]]
>
> _Estado, goal, tags y resto de metadata viven en el frontmatter arriba — no duplicar aquí._

---

## Problema

SPEC-0007 trajo la pantalla del mapa y la enganchó **solo a la corrección** de una
propiedad: `site_form_sheet.dart` esconde el bloque «Ubicación en el mapa» cuando
`site == null`, con la nota de que el punto se guarda contra el id de la propiedad
y por eso hay que crearla primero.

El resultado, encontrado el 2026-09-22 probando con los dos clientes reales de
William: crea la propiedad, no ve ningún mapa, crea la obra, y **la obra queda sin
geocerca**. Para fijar el punto tiene que volver a Clientes, entrar al cliente,
tocar la propiedad que acaba de crear, y recién ahí aparece el botón. Nadie hace
ese camino sin que se lo digan, y el marcaje de asistencia queda sin nada contra
qué comparar: la bandera de geocerca de SPEC-0008 no se enciende nunca.

La razón técnica no se sostiene. **Los ids los genera el dispositivo antes de
guardar** (regla 18): `addSite` crea el UUIDv7 en la misma transacción que
inserta la fila. Y el contrato ya lo permite: `SiteInputDto` —el cuerpo de
`POST /customers/{id}/sites`— acepta `lat`, `lng` y `geofenceRadiusM` desde el
primer día, y `SyncSiteCreateDto` lo extiende. Lo que falta es la pantalla, no el
modelo ni el API.

El momento correcto para fijar el punto es cuando se está cargando la propiedad,
que en el móvil es casi siempre parado en la obra o a la puerta de la casa del
cliente. Pedirlo después es pedirlo desde la oficina, que es exactamente el caso
que SPEC-0009 web descartó por impreciso.

## Alcance

### Entra

- **La dirección se rellena desde el punto.** Al volver del mapa en el alta, la
  app consulta el geocodificador **del teléfono** —`CLGeocoder` en iOS,
  `Geocoder` en Android, vía el paquete `geocoding`— y **completa los campos
  vacíos**: calle y número, ciudad, estado o provincia y código postal.
  **Lo escrito a mano no se pisa, pero lo que puso el propio geocodificador
  sí se reemplaza si el punto cambia**: la dirección del punto viejo ya no
  corresponde, y dejarla sería peor que corregirla. Se distingue recordando qué
  valor escribió en cada campo: si sigue igual, es suyo y se reemplaza; si
  difiere, alguien lo editó y queda intocable. **Un campo vacío se rellena
  siempre**, lo haya vaciado una persona o no: un campo en blanco no puede
  quedar protegido, porque nada en la pantalla mostraría que lo está, y el
  formulario igual va a exigirlo para guardar. El país **no se rellena**: el
  selector nunca está vacío —arranca en Estados Unidos— y no hay forma de saber
  si quien carga lo eligió o lo dejó. Lo que sí hace el país del teléfono es
  **guardar** el estado: se rellena solo si coincide con el del selector, para
  no meter «Alajuela» en un campo que exige dos letras. Los campos siguen editables: el
  número de casa a veces viene del vecino, y corregir un número es menos que
  tipear seis campos parado en la obra. Una línea bajo la dirección dice que se
  rellenó lo que faltaba y que conviene revisar el número.
- **Mientras se busca la dirección, los campos se bloquean.** Al volver del
  mapa, la dirección, «Agregar» y el propio botón del mapa se deshabilitan, y
  una línea dice que se está buscando. El botón del mapa también, porque elegir
  otro punto dejaría dos búsquedas escribiendo sobre los mismos campos. Dura lo que tarde el teléfono, con el tope de ocho segundos. Sin
  esto, lo que aparece se mezcla con lo que se estaba tipeando.
- **Lo rellenado se revisa antes de seguir.** Si al menos un campo se rellenó,
  se abre una hoja con la lista de lo que se completó, campo por campo, y dos
  salidas: «Está bien» cierra; «Corregir» cierra y deja el foco en calle y
  número. **Cerrarla deslizando o tocando afuera cuenta como «Está bien»**: no
  hay nada que perder, los campos siguen editables. Es hoja y no diálogo, como
  toda confirmación de la app. Si no se rellenó nada, no se abre nada. La línea bajo la dirección queda como
  recordatorio después de cerrarla.
- **En una propiedad ya guardada, mover el punto ofrece actualizar su
  dirección.** Al volver del mapa se consulta la dirección del punto nuevo y se
  compara con la guardada. Si algún campo difiere, se abre la hoja de revisión
  **en modo comparación**: cada campo con su valor anterior y el nuevo, y dos
  salidas, «Actualizar la dirección» y «Dejarla como está». **Nada se pisa sin
  confirmar**, porque lo guardado lo escribió alguien a propósito, y **aceptar
  escribe y encola en el acto**, sin esperar a «Guardar»: el punto ya se guardó
  solo al volver del mapa, así que una dirección esperando un toque más
  reconstruye el mismo desacuerdo que esto viene a resolver.

  Acá **sí entra el país**, a diferencia del alta. Lo que impedía tocarlo era
  no poder distinguir una elección de un valor por defecto; con una
  confirmación explícita delante, esa ambigüedad no existe.

  Es el caso que lo pidió, visto el 2026-09-22 en un teléfono real: una
  propiedad con el punto en Florida y la dirección diciendo San Ramón, Costa
  Rica. Mover el punto guardaba las coordenadas y dejaba la dirección
  contradiciéndolas, sin ninguna señal.
- **Se puede buscar una dirección en el mapa.** Un campo de búsqueda en la
  pantalla del mapa lleva la cámara a la dirección escrita, con el
  geocodificador del teléfono. **Nunca fija el punto**, solo mueve la vista:
  ADR-0012 es explícito en que una dirección geocodificada cae en el centro de
  la manzana o sobre la calle, y acá el punto **es** la geocerca. Sirve para
  cargar una obra desde la oficina sin arrastrar el mapa medio continente, que
  es el uso que el propio ADR ya contemplaba. Si no encuentra nada, lo dice y
  no mueve nada.
- **El mapa se puede ver en satélite.** Un botón en la barra de la pantalla del
  mapa alterna entre mapa y satélite **con calles** —sin nombres de calle el
  satélite solo no ubica—. La elección se recuerda en el dispositivo, como el
  tema: quien ubica casas lo va a querer siempre.
- **En el alta el mapa va primero.** El bloque de ubicación se muestra arriba
  de la dirección, porque el orden natural pasa a ser tocar «Usar mi
  ubicación» y después corregir lo que vino. En corrección la dirección sigue
  arriba: ahí lo común es arreglar un dato, no ubicar.
- **El bloque «Ubicación en el mapa» aparece en toda pantalla que cree una
  propiedad**: la hoja de propiedad y **el alta de cliente**, que carga la
  primera. En el alta de cliente, elegir punto vuelve obligatoria la dirección
  —que ahí es opcional—, porque sin ella no se crea la propiedad y el punto se
  perdería sin que nadie lo note.
- **El bloque aparece siempre en la hoja de propiedad**,
  también en el alta. En el alta, «Fijar en el mapa» abre la misma pantalla
  completa de SPEC-0007, pero **devuelve el punto en vez de guardarlo**: el punto
  y el radio se guardan con la propiedad, en la misma inserción local y en la
  misma operación `site.create`.
- **La hoja muestra lo elegido antes de guardar**: coordenadas y radio en texto,
  con la acción cambiada a «Mover el punto». Cerrar la hoja sin guardar descarta
  el punto junto con la dirección, como cualquier otro campo.
- **El alta de obra dice cuándo la propiedad elegida no tiene punto** y ofrece
  fijarlo ahí mismo, sin salir del formulario. Aplica tanto a una propiedad que ya
  existía como a una recién creada desde el selector. Guardar la obra **sigue
  permitido** sin punto: la geocerca es deseable, no obligatoria, y bloquear el
  alta de una obra por un dato que se puede completar después es el tipo de
  fricción que hace que alguien deje de usar la app.
- **La tab Detalle de la obra muestra si la propiedad tiene punto.** Si no lo
  tiene, la misma línea ofrece fijarlo; abre la pantalla de SPEC-0007 en su modo
  actual, que guarda contra la propiedad existente con `site.update`. Es el camino
  para las obras que ya existen hoy sin geocerca.

### No entra

- **Fijar el punto desde el panel web.** SPEC-0009 lo dejó afuera a propósito:
  el punto se fija parado en la obra. Si William lo pide, se revisa esa decisión
  en su spec, no acá.
- **Hacer obligatorio el punto** para crear una propiedad o una obra. Ver arriba.
- **Geocodificar sola la dirección del formulario.** Que lo escrito en los
  campos mueva el mapa o fije el punto por su cuenta, sin que nadie lo pida,
  sigue afuera. La búsqueda del mapa es una acción explícita y solo mueve la
  cámara: son cosas distintas.
- **Que la búsqueda fije el punto.** Mueve la cámara y nada más, por la razón
  de ADR-0012. Quien busca sigue teniendo que tocar dónde es.
- **La API de Geocoding de Google.** Es un SKU facturable con otra llave; el
  geocodificador del teléfono no cuesta ni necesita clave. Ver la adenda de
  ADR-0012.
- **Rellenar el país.** No tiene estado vacío, así que no se puede saber si se
  eligió. Se elige a mano, como hoy; el impacto es bajo porque el alta arranca
  en el país donde opera el design partner.
- **Mover un punto que ya existe desde la obra.** Eso sigue viviendo en la
  propiedad. Desde la obra solo se ofrece cuando falta.
- **Cambiar la pantalla del mapa en sí**: marcador, radio, «Usar mi ubicación» y
  los estados de permiso quedan como los dejó SPEC-0007.

## Modelo de dominio afectado

- [[cliente]] — la propiedad (`site`) con `lat`, `lng` y `geofence_radius_m`.
  **No cambia ningún campo ni ningún invariante**: los tres ya existen y ya son
  opcionales. Cambia el momento en que se llenan.

## Comportamiento sin señal

Hereda la tabla de SPEC-0007, con una diferencia a favor:

| Situación | Comportamiento |
|---|---|
| Crear la propiedad con punto sin señal | **Funciona.** El GPS no necesita red. La propiedad sale con su punto en **un solo `site.create`**, en vez de un `site.create` seguido de un `site.update` que dependían del orden por `occurredAt`. |
| Abrir el mapa desde el alta sin señal | Igual que SPEC-0007: el mapa avisa que falta la red y «Usar mi ubicación» funciona igual. Se vuelve a la hoja con el punto puesto. |
| Cerrar la hoja sin guardar | No queda nada: ni la propiedad ni el punto. Nada se encoló. |
| Rellenar la dirección sin señal | **No funciona**: el geocodificador necesita red. El punto queda igual, los campos quedan como estaban y se escriben a mano. No se avisa aparte: el mapa ya dijo que falta la red. |
| Con señal, el geocodificador no devuelve nada o falla | Misma salida, en silencio: los campos quedan como estaban. Un error acá no le da a nadie nada que hacer distinto de escribir la dirección. |
| Satélite sin señal | Igual que el mapa: los tiles necesitan red. El aviso de la pantalla ya lo dice. |
| Mover el punto de una propiedad guardada, sin señal | El punto se guarda y se encola como siempre. La dirección no se ofrece actualizar, porque no hay con qué compararla: no aparece ninguna hoja. |
| Buscar una dirección sin señal | **No funciona**, y se dice en el mismo lugar donde se diría «no se encontró»: el geocodificador necesita red. El punto y el mapa quedan como estaban. |
| Fijar el punto desde la obra sin señal | Es el camino de SPEC-0007 sin cambios: `site.update` encolado. |

**Lo pendiente se ve**: la propiedad recién creada lleva su marca de sincronización
como hasta hoy. No aparece una marca nueva.

## Flujo de usuario

**Alta de propiedad, el caso principal:**

1. Cliente → «Agregar propiedad». Arriba, el bloque «Ubicación en el mapa» con
   «Fijar en el mapa»; debajo, la dirección vacía.
2. Se abre la pantalla completa. «Usar mi ubicación» si está parado en la obra, o
   tocar el mapa. Se ajusta el radio. «Guardar ubicación» **vuelve a la hoja**, no
   escribe nada todavía.
3. La hoja vuelve con coordenadas y radio, con «Mover el punto». **La dirección
   queda bloqueada** con la línea de búsqueda mientras el teléfono responde.
4. Se abre la hoja de revisión con lo que se rellenó, campo por campo. «Está
   bien» la cierra; «Corregir» la cierra y deja el cursor en calle y número.
   Lo que ya estaba escrito queda como estaba.
5. Se corrige lo que haga falta. «Agregar» guarda dirección y punto juntos.

Si se escribe la dirección primero y el mapa después, funciona igual: se
rellenan solo los campos que quedaron vacíos.

**Alta de obra sobre una propiedad sin punto:**

1. Obras → «Nueva obra» → cliente → propiedad.
2. Debajo del selector, si la elegida no tiene punto: el aviso y «Fijar en el mapa».
3. Se abre la pantalla de SPEC-0007 en su modo normal —la propiedad existe— y
   guarda con `site.update`. Al volver, el aviso desaparece.
4. Guardar la obra funciona con o sin haber pasado por el paso 2.

**Obra existente sin geocerca:** tab Detalle, la propiedad muestra «Sin punto en el
mapa» y la acción. Mismo modo que el flujo anterior.

## Contrato de API

**No cambia.** Verificado antes de escribir esto:

- `POST /customers/{id}/sites` acepta `lat`, `lng` y `geofenceRadiusM` opcionales
  desde SPEC-0006.
- `site.create` del lote de sincronización extiende `SiteInputDto`, así que lleva
  los mismos campos.
- El `GET` de propiedades ya los devuelve; es lo que hoy usa la ficha.

`openapi.json` no se regenera, y **que no cambie es criterio de aceptación**: si un
diff aparece, algo se implementó de más.

## UI

Sobre las pantallas que ya existen; ninguna pantalla nueva.

- **Hoja de propiedad** (`site_form_sheet.dart`): el bloque de ubicación deja de
  depender de `site != null`. En alta, el bloque tiene dos estados: sin punto
  —texto de invitación y «Fijar en el mapa»— y con punto elegido —coordenadas,
  radio y «Mover el punto»—. Es el mismo `SiteLocationBlock` en su parte visible,
  pero **lo que recibe cambia**: hoy exige un `SiteSummary` y lee el stream de la
  propiedad; en alta no hay propiedad. Se separa lo que dibuja de lo que lee: el
  bloque pasa a recibir **el punto y el radio como valores** más la acción de
  fijar, y la ficha de la propiedad lo envuelve con el stream como hasta hoy.
  En el alta, la hoja guarda el punto elegido en su estado y se lo pasa.
- **Geocodificador** (`core/location/device_geocoder.dart`, nuevo): calca el
  patrón de `DeviceLocation` —una abstracción con su provider, la implementación
  real sobre `geocoding`, y en tests siempre una falsa, porque es un canal de
  plataforma que bajo el reloj falso cuelga para siempre, como la cámara—.
  Devuelve los cinco campos ya en la forma del formulario: **en Estados Unidos y
  Canadá el estado se traduce a su código de dos letras** cuando la plataforma
  devuelve el nombre entero —Android dice «Maryland», iOS dice «MD»—, con una
  tabla estática de estados y provincias; el país se traduce a `IsoCode` solo
  para eso y para decidir si el estado se rellena. Cualquier fallo devuelve nada.
- **Hoja de propiedad, rellenado**: al volver del mapa en el alta, `AddressFields`
  se deshabilita y `FormSheet` pierde su acción mientras se consulta; por cada
  campo vacío se escribe lo que vino y los que tenían texto no se tocan. Si al
  menos uno se rellenó, se abre `address_review_sheet.dart` —misma forma que
  `confirm_sheet.dart`: título, cuerpo, la lista de campos con su valor, y dos
  botones a ancho completo— y al cerrarla queda la línea
  `siteAddressFilledFromPoint`.
- **Hoja de revisión, modo comparación**: la misma hoja, con cada campo
  mostrando el valor anterior y el nuevo en vez de solo el nuevo, y las dos
  salidas con su texto propio. Un campo que antes estaba vacío se muestra sin
  la línea «antes».
- **Búsqueda en el mapa**: un campo sobre el mapa, arriba, sobre superficie con
  borde y no con elevación —la app no usa sombras en ningún lado—, con acción de
  buscar en el teclado. Llama a `DeviceGeocoder.searchAddress`, que envuelve
  `locationFromAddress` con el mismo tope y el mismo «cualquier fallo devuelve
  nada» que el resto. Con resultado, anima la cámara; sin resultado, un aviso
  con el mismo `StatusChip` que ya usan los avisos de la pantalla.
- **Tipo de mapa** (`core/location/map_type_store.dart`, nuevo): un store
  sobre `SharedPreferences` calcando `ThemeStore`, y un notifier booleano. La
  pantalla del mapa lee el notifier para elegir `MapType.normal` o
  `MapType.hybrid`, y el botón de la barra lo alterna.
- **Pantalla del mapa** (`site_location_screen.dart`): hoy exige la propiedad
  para mostrar su dirección y para guardar contra su id. Gana un modo **elegir**
  que recibe **la dirección tal como está escrita en la hoja en ese momento** —
  puede estar incompleta, y se muestra lo que haya con el mismo `oneLine`— y el
  punto y radio ya elegidos si se vuelve a entrar. En ese modo «Guardar ubicación»
  **devuelve el punto y el radio al llamador** con `pop` y no escribe nada. La
  pantalla se ve igual; solo cambia de dónde sale la dirección y qué hace el botón
  primario. El modo actual, con propiedad, no cambia.
- **Alta de obra** (`project_form_screen.dart`): debajo del selector de propiedad,
  un aviso de una línea con acción, en el mismo tono que
  `projectFieldSiteNoneForCustomer`. Solo cuando hay propiedad elegida y no tiene
  punto.
- **Detalle de la obra** (`project_details_tab.dart`): la línea de la propiedad
  muestra el estado del punto. Con punto: las coordenadas, como en la ficha de la
  propiedad. Sin punto: el aviso y la acción.

### Copy

Se reusa todo lo de SPEC-0007 —`siteLocationSection`, `siteLocationEmpty`,
`siteLocationSet`, `siteLocationEdit`, `siteLocationCoords`,
`siteLocationRadiusValue`—. Claves nuevas, en `en` y `es`:

| Clave | es |
|---|---|
| `siteLocationChosen` | Punto elegido. Se guarda con la propiedad. |
| `projectFieldSiteNoLocation` | Esta propiedad no tiene punto en el mapa. Sin él, la app no puede saber si alguien marcó entrada en la obra. |
| `projectSiteNoLocation` | Sin punto en el mapa |
| `siteAddressFilledFromPoint` | Se rellenó la dirección desde el punto. Revise el número de casa. |
| `siteAddressLookingUp` | Buscando la dirección del punto… |
| `siteAddressReviewTitle` | Revise la dirección |
| `siteAddressReviewBody` | Se rellenó desde el punto. El número de casa puede ser el del vecino. |
| `siteAddressReviewAccept` | Está bien |
| `siteAddressReviewFix` | Corregir |
| `siteAddressUpdateTitle` | Revisar la dirección |
| `siteAddressUpdateBody` | El punto se movió. La dirección guardada no coincide con la ubicación nueva. |
| `siteAddressUpdateAccept` | Actualizar la dirección |
| `siteAddressUpdateKeep` | Dejarla como está |
| `siteAddressBefore` | antes |
| `siteAddressAfter` | ahora |
| `siteLocationSearch` | Buscar una dirección |
| `siteLocationSearchEmpty` | No se encontró esa dirección. Revísela, o toque el mapa para fijar la ubicación. |
| `siteLocationSatellite` | Ver satélite |
| `siteLocationStandardMap` | Ver mapa |

El copy no fiscaliza (regla de SPEC-0009): dice qué falta y para qué sirve, no
que alguien se olvidó.

## Criterios de aceptación

- [x] En «Nueva propiedad» aparece «Ubicación en el mapa» con «Fijar en el mapa»,
      antes de guardar nada.
- [x] Fijar el punto desde el alta y tocar «Agregar» deja **una** fila en `sites`
      con `lat`, `lng` y `geofence_radius_m`, y **una sola** operación
      `site.create` en la bandeja, con los tres campos en el payload.
- [x] Cerrar la hoja de alta después de fijar el punto y sin tocar «Agregar» no
      deja ni fila ni operación. **Verificado leyendo código y en el simulador,
      no con test**: el mapa no se dibuja en tests de widget, así que no hay
      forma de elegir un punto desde ahí. El punto vive en el estado de la hoja
      y lo único que escribe es `_guardar`; el test cubre que abrir la hoja no
      deja nada.
- [x] En el alta, volver del mapa muestra las coordenadas y el radio elegidos, y
      la acción pasa a «Mover el punto».
- [x] Corregir una propiedad existente sigue guardando el punto con `site.update`,
      como hasta hoy: SPEC-0007 no se rompe.
- [x] En el alta de obra, elegir una propiedad sin punto muestra el aviso y la
      acción; elegir una con punto no muestra nada.
- [x] Fijar el punto desde el alta de obra y volver hace desaparecer el aviso, y
      la propiedad queda con `site.update` encolado.
- [x] Una obra se puede guardar con una propiedad sin punto.
- [x] La tab Detalle de una obra cuya propiedad no tiene punto muestra «Sin punto
      en el mapa» y la acción; con punto, muestra las coordenadas.
- [x] Fijar el punto desde la tab Detalle y volver hace desaparecer el aviso y
      muestra las coordenadas **sin salir de la obra**, y la propiedad queda con
      `site.update` encolado.
- [x] En la ficha de una propiedad existente, fijar el punto y volver muestra las
      coordenadas nuevas **sin cerrar y reabrir la hoja**: el refresco que
      SPEC-0007 tenía dentro del bloque no se pierde al separarlo.
- [x] Sin señal: crear la propiedad con «Usar mi ubicación» funciona y encola un
      solo `site.create` con el punto. La parte del repositorio está en test; el
      GPS sin red es el mismo camino de SPEC-0007, sin cambios.
- [x] Volver del mapa en el alta con la dirección vacía deja calle y número,
      ciudad, estado y código postal rellenados con lo que devolvió el
      geocodificador, y muestra la línea de aviso. El selector de país queda
      como estaba. **El armado de la dirección y el rellenado están en test
      unitario** (`device_geocoder_test.dart`); el disparo desde la hoja al
      volver del mapa se verifica en el simulador, porque el mapa no se dibuja
      en tests.
- [x] Un campo escrito a mano no se pisa.
- [x] **Mover el punto reemplaza lo que el geocodificador había puesto** y
      vuelve a abrir la hoja de revisión; un campo que la persona editó a mano
      después del primer rellenado sobrevive al segundo. **La regla está en
      test**; que la hoja se reabra al volver del mapa se verifica en el
      simulador, porque la pantalla del mapa no se monta en tests.
- [x] Un campo **vaciado a mano** se vuelve a rellenar al mover el punto: en
      blanco no hay nada que proteger y el formulario lo exige igual.
- [x] En una propiedad guardada, mover el punto a una ubicación con otra
      dirección abre la hoja en modo comparación, con el valor anterior y el
      nuevo de cada campo que cambia. **La comparación y la hoja están en
      test**; que se dispare al volver del mapa se verifica en el simulador.
- [x] «Actualizar la dirección» reemplaza esos campos, el país incluido, y deja
      la propiedad con su `site.update` de dirección encolado **en el acto**,
      sin depender de que después se toque «Guardar».
- [x] El país se muestra con su nombre en los dos lados de la comparación, no
      con su código ISO.
- [x] Mientras se consulta la dirección del punto nuevo, los campos y el botón
      del mapa se bloquean, y una respuesta que llega tarde se descarta.
- [x] «Dejarla como está» no toca ningún campo, y el punto queda guardado igual.
- [x] Si la dirección del punto nuevo coincide con la guardada, no se abre nada.
- [x] Sin señal o sin resultado del geocodificador, no se abre nada y el punto
      se guarda igual.
- [x] Buscar una dirección mueve la cámara y **no fija el punto**: el marcador
      queda donde estaba, o sigue sin existir si no había. **El contrato está
      en test**; que la cámara se mueva se verifica en el simulador, porque la
      pantalla del mapa no se monta en tests.
- [x] Una búsqueda sin resultado lo dice y no mueve la cámara.
- [x] Si el geocodificador no devuelve nada o falla, los campos quedan como
      estaban y no aparece ningún error.
- [x] En Estados Unidos y Canadá el estado queda como código de dos letras
      aunque la plataforma devuelva el nombre entero; en el resto, el nombre.
- [x] Si el país que devolvió el teléfono no es el del selector, el estado no
      se rellena y el resto sí; si el teléfono no dijo país, el estado se
      rellena.
- [x] Mover el punto de una propiedad existente no toca su dirección.
- [x] En el alta el bloque de ubicación va arriba de la dirección; en
      corrección, abajo.
- [x] Al volver del mapa en el alta, mientras se busca la dirección los campos
      y «Agregar» están deshabilitados y se ve la línea de búsqueda; al
      terminar, se habilitan, con o sin resultado.
- [x] Si se rellenó al menos un campo se abre la hoja de revisión con esos
      campos y sus valores; si no se rellenó ninguno, no se abre.
- [x] «Está bien» cierra la hoja de revisión; «Corregir» la cierra y deja el
      foco en calle y número.
- [x] El mapa arranca en modo mapa la primera vez; el botón de la barra alterna
      a satélite con calles; la elección se conserva al reabrir la pantalla y
      al reabrir la app. **El notifier y el store están en test; el botón se verifica en
      el simulador**, porque la pantalla del mapa no se dibuja en tests.
- [x] Tests: el store y el notifier del tipo de mapa, la hoja de revisión como
      widget aislado, y `AddressFields` deshabilitado.
- [x] Un toque en el botón de satélite **gana sobre la lectura del disco** que
      todavía no resolvió.
- [x] El botón del mapa está deshabilitado mientras se busca la dirección.
      **Probado sobre el bloque aislado**; que dos búsquedas no se pisen se
      verifica por lectura, porque forzar la segunda exige volver del mapa y la
      pantalla del mapa no se monta en tests —comprobado, no supuesto—. El
      número de búsqueda es defensa en profundidad detrás del botón bloqueado,
      que sí tiene test.
- [x] `openapi.json` **no cambia**.
- [x] Tests de widget de la hoja en los dos modos, del aviso en el alta de obra y
      de la línea en Detalle; test del repositorio para `addSite` con y sin punto;
      `l10n_arb_test.dart` verde con las claves nuevas en los dos idiomas.

## Riesgos / consideraciones

- **La pantalla del mapa con dos modos** es el punto donde más fácil se rompe
  SPEC-0007. El modo nuevo no escribe; si por error escribe contra un id que
  todavía no existe, la escritura falla en silencio en Drift. El test del
  criterio de «una sola operación» es el que lo atrapa.
- **Separar el bloque en lo que dibuja y lo que lee mueve el `watch` del
  stream** que hoy vive adentro de `SiteLocationBlock` hacia quien lo envuelve.
  Si el envoltorio no observa el stream de la propiedad, la ficha muestra
  coordenadas viejas al volver del mapa hasta el próximo rebuild. Es la clase de
  bug que SPEC-0007 ya tuvo dos veces con streams que no notificaban; por eso
  hay un criterio que exige ver el punto nuevo sin reabrir la hoja.
- **El geocodificador acierta la calle y casi siempre el número, no siempre.**
  Por eso rellena y no decide: los campos quedan editables y la línea pide
  revisar el número. En Android depende de Google Play Services, que en Maryland
  está; en un teléfono sin ellos devuelve vacío y se escribe a mano.
- **Es otro canal de plataforma.** En tests se reemplaza siempre por uno falso,
  como la cámara: el real cuelga bajo el reloj falso.
- **Escribir a mano exactamente lo que el geocodificador había puesto es
  indistinguible de no haberlo tocado**, porque se guarda el último valor por
  campo y no un origen. En ese caso el campo se trata como suyo y se reemplaza
  al mover el punto. Es el borde aceptado del diseño más simple, y el daño es
  reescribir un texto idéntico al que la persona acababa de tipear.
- **Dos búsquedas a la vez.** Con ocho segundos de tope, alguien puede querer
  corregir el punto antes de que la primera respuesta llegue. Además de
  bloquear el botón, cada búsqueda lleva su número y una respuesta con número
  viejo se descarta: si no, rellenaría la dirección del punto que se descartó.
- **La hoja de revisión se abre sobre la hoja de propiedad.** Dos hojas
  apiladas es raro en la app, pero es lo que la confirmación de fotos ya hace
  sobre su pantalla, y una hoja de propiedad no puede cerrarse para preguntar
  sin perder lo escrito.
- **El radio por default sigue siendo el de la empresa**, que hoy es una
  constante (DEBT-0004). Este spec no lo cambia ni lo empeora.
- **La versión instalada en el teléfono de William** no tiene esto. Hasta que se
  instale, el camino sigue siendo el de hoy: entrar a la propiedad ya creada.

## ADRs relacionados

- [[../../../adr/0012-proveedor-de-mapas/README|ADR-0012]] — proveedor de mapas, y
  su adenda del 2026-09-22 sobre el geocodificador del teléfono.
- [[../../../adr/0003-asistencia-geocerca-foto/README|ADR-0003]] — la geocerca que este punto alimenta.

---

## Historial

| Fecha | Estado | Nota |
|-------|--------|------|
| 2026-09-23 | implementado | **Hueco encontrado probando**: el alta de cliente carga la primera propiedad y se había quedado sin el mapa, así que esa propiedad nacía sin punto. El `goal` ya lo cubría —dice «el alta de la propiedad», sin calificar cuál pantalla—, así que es un arreglo del spec y no alcance nuevo. Se calcó el patrón de la hoja: bloque arriba de la dirección, rellenado con su hoja de revisión, y la dirección pasa a obligatoria cuando hay punto. Tres tests nuevos, suite en 502 |
| 2026-09-23 | implementado | **PR #50 mergeado.** Los 40 criterios cumplidos, 499 tests en el móvil y `openapi.json` sin cambios, que era criterio del spec: el contrato ya aceptaba el punto al crear. Nació como un arreglo de flujo —el mapa solo se abría corrigiendo una propiedad ya creada— y creció a cinco tramos, los cuatro últimos salidos de probar la app en un teléfono real |
| 2026-09-22 | en-implementacion | `code-reviewer`, segunda pasada del quinto tramo: **LISTO PARA PR**, sin hallazgos abiertos ni nuevos. Verificó además que reconstruir los dos archivos de test —los trunqué por error al editarlos— no perdió ningún caso ni debilitó ninguna aserción. **Los 40 criterios marcados; queda el commit, el PR y el merge, que hace @jaca.** Al mergear, este spec pasa a Implementado y el BOARD lo refleja en el mismo acto |
| 2026-09-22 | en-implementacion | `code-reviewer` sobre el quinto tramo: **un GRAVE**, arreglado. Aceptar la comparación solo mutaba el formulario abierto: cerrar la hoja sin tocar «Guardar» dejaba el punto nuevo sincronizado y la dirección vieja intacta, que es exactamente el bug que el tramo venía a resolver. Ahora escribe y encola en el acto. Con él, dos MEDIO: faltaba el número de búsqueda y el gate del botón que el tercer tramo ya había resuelto para el alta, y el país salía como código ISO de un lado y como nombre del otro. La carrera al leer el punto del stream se cerró de raíz: la pantalla del mapa devuelve el punto que guardó en vez de `true` |
| 2026-09-22 | en-implementacion | Implementado el quinto tramo: `AddressFormControllers.diff` y `applyChanges`, `AddressChange` con lo anterior y lo nuevo, la hoja con su modo comparación y `SavedSiteLocationBlock.onMoved` avisando a la hoja de propiedad. 9 tests nuevos, suite en 496. Va a los dos revisores |
| 2026-09-22 | en-implementacion | **Quinto tramo**, de probar en un teléfono real: mover el punto de una propiedad guardada dejaba la dirección contradiciendo las coordenadas —punto en Florida, dirección en Costa Rica— sin ninguna señal. Era lo que este spec declaraba fuera de alcance, y la decisión estaba mal: @jaca eligió que se ofrezca actualizarla comparando campo por campo, sin pisar nada sin confirmar. Sale de «No entra» y entra con su forma |
| 2026-09-22 | en-implementacion | `code-reviewer` sobre el cuarto tramo: **LISTO PARA PR**. Un MEDIO aplicado: el buscador fijaba `elevation: 2`, el único literal de elevación de toda la app, contra la regla 22 y contra la convención de superficie con borde que usan los otros siete `Material`. Y un menor: el docblock de `fillMissing` narraba la regla entera, ahora la cita |
| 2026-09-22 | en-implementacion | `spec-reviewer` sobre el cuarto tramo, segunda pasada: **LISTO PARA IMPLEMENTAR**, sin bloqueantes ni menores |
| 2026-09-22 | en-implementacion | `spec-reviewer` sobre el cuarto tramo, cuatro bloqueantes, los cuatro resueltos: «No entra» seguía prohibiendo centrar el mapa desde una dirección y ahora acota lo que de verdad excluye —el geocodificado automático y silencioso—; la adenda de ADR-0012 cubría solo el sentido punto → dirección; el `goal` no nombraba la búsqueda; y **nadie había decidido qué pasa con un campo vaciado a mano**, que el código rellenaba sin que el spec lo dijera. Se decide que sí se rellena: un campo en blanco no puede quedar protegido sin que nada en pantalla lo muestre |
| 2026-09-22 | en-implementacion | Implementado el cuarto tramo: `fillMissing` recuerda qué escribió el geocodificador y reemplaza lo suyo al mover el punto, respetando lo corregido a mano; `DeviceGeocoder.searchAddress` sobre `locationFromAddress`, y un buscador sobre el mapa que solo anima la cámara. 6 tests nuevos, suite en 486. Va a los dos revisores |
| 2026-09-22 | en-implementacion | **Cuarto tramo**, de probar en el teléfono: @jaca encontró que **mover el punto no volvía a abrir la hoja ni reemplazaba la dirección** —`fillMissing` solo escribía en campos vacíos, y tras el primer rellenado ya no quedaba ninguno—, y pidió poder buscar una dirección en el mapa. Lo primero es un bug del tramo anterior; lo segundo, alcance nuevo que ADR-0012 ya contemplaba mientras no fije el punto |
| 2026-09-22 | en-implementacion | `code-reviewer` confirma los dos MEDIO cerrados: **LISTO PARA PR**. Dejó dos notas, las dos atendidas: el guard `ref.mounted` antes de escribir el estado del satélite ya está, y la falta de test de integración de la reentrancia queda declarada en su criterio —se intentó montar la pantalla del mapa en un test y no se monta, así que no hay ruta— |
| 2026-09-22 | en-implementacion | Copy reescrito a pedido de @jaca: la hoja de revisión decía «el número de casa puede ser el del vecino», que no es voz de producto. Queda «Revisar la dirección» y «La información de la ubicación se rellenó automáticamente. Verifique que sea correcta.», con «Confirmar» y «Corregir» como salidas. De paso, **las siete cadenas de la pantalla del mapa que habían quedado en voseo desde SPEC-0007 pasan a voz de usted**, que es la del resto de la app |
| 2026-09-22 | en-implementacion | `code-reviewer` sobre el tercer tramo: **dos MEDIO de concurrencia**, los dos arreglados con su test. `_rellenarDireccion` no era reentrante y el botón del mapa seguía activo durante la búsqueda: ahora se bloquea y cada búsqueda lleva su número, así una respuesta vieja no rellena la dirección de un punto descartado. Y la lectura del disco del modo satélite podía pisar un toque que llegó antes: ahora el toque gana. Más dos menores: un docblock que repetía el spec y la tarjeta del BOARD |
| 2026-09-22 | en-implementacion | `spec-reviewer` sobre el tercer tramo: **APROBADO**. Un menor aplicado: la hoja de revisión tiene una tercera salida —deslizar o tocar afuera— que el texto no nombraba y que cuenta como «Está bien» |
| 2026-09-22 | en-implementacion | Implementado el tercer tramo: `AddressFields` y `CountryField` con `enabled`, `address_review_sheet.dart` con la lista scrolleable —el primer test encontró que con cuatro campos desbordaba—, `map_type_store.dart` con su notifier, y el botón en la barra del mapa. 7 tests nuevos, suite en 477. Va a los dos revisores |
| 2026-09-22 | en-implementacion | **Tercer tramo de alcance**, pedido al ver el rellenado funcionando: los campos se bloquean mientras se busca, lo rellenado se revisa en una hoja antes de seguir, y el mapa se puede ver en satélite con la elección guardada en el dispositivo. Vuelve a los dos revisores |
| 2026-09-22 | en-implementacion | `code-reviewer` sobre el alcance nuevo: **LISTO PARA PR**, un menor —la tarjeta del BOARD un paso atrás— corregido |
| 2026-09-22 | en-implementacion | Quinta pasada de `spec-reviewer`: **APROBADO**. Implementado el alcance nuevo: `device_geocoder.dart` sobre `geocoding` 5 con `GeocodedAddress.fromParts` separado del canal de plataforma, `StateCodes` en `core/i18n/`, `AddressFormControllers.fillMissing`, y la hoja con el mapa arriba en el alta. 17 tests nuevos, suite en 470. Va a `code-reviewer` |
| 2026-09-22 | en-implementacion | Cuarta pasada de `spec-reviewer` sobre el alcance nuevo, un bloqueante: el selector de país nunca está vacío, así que «no pisar lo escrito» no se podía aplicar ahí. Se resuelve sacando el país del rellenado; el país del teléfono solo decide si el estado se rellena. Las dos causas de fallo del geocodificador pasan a filas separadas |
| 2026-09-22 | en-implementacion | **Alcance agregado después de la aprobación**, pedido por @jaca al probar el alta: la dirección se rellena desde el punto con el geocodificador del teléfono, sin pisar lo escrito, y en el alta el mapa pasa arriba de la dirección. El `goal` lo incorpora. Vuelve a `spec-reviewer` y a `code-reviewer` |
| 2026-09-22 | en-implementacion | `code-reviewer`: **LISTO PARA PR** en la segunda pasada. La primera dejó dos menores, aplicados: un comentario que repetía el spec, y el gate por `customers.write` que vivía solo en Detalle y ahora vive adentro de `SiteWithoutLocationNotice`, así el alta y Detalle no pueden divergir |
| 2026-09-22 | en-implementacion | Implementado: 15 tests nuevos en `site_location_at_create_test.dart`, suite en 453, `openapi.json` sin diff. La pantalla del mapa tiene su modo elegir con `SiteLocationScreen.pick`, el bloque se separó en `SiteLocationBlock` (valores) y `SavedSiteLocationBlock` (stream), y el aviso de la obra es `SiteWithoutLocationNotice`, compartido por el alta y Detalle. En Detalle la acción solo se ofrece con `customers.write`: a quien no lo tiene se le dice que falta, sin ofrecerle una escritura que el servidor rechazaría |
| 2026-09-22 | en-implementacion | Tercera pasada de `spec-reviewer`: **APROBADO, sin bloqueantes ni menores**. Pasa por Review y Aprobado en el mismo acto porque @jaca pidió trabajarlo hoy: el spec nació de su prueba con los clientes reales y la decisión de producto es suya. Arranca la implementación en `feature/mobile-0013-punto-al-crear` |
| 2026-09-22 | borrador | Segunda pasada: Detalle tenía criterio de los dos estados pero no de la transición —fijar y volver—, y el refactor del bloque movía el `watch` del stream sin que Riesgos lo dijera; se agregaron el criterio simétrico, el riesgo y un criterio que exige ver el punto nuevo sin reabrir la hoja |
| 2026-09-22 | borrador | Primera pasada de `spec-reviewer`: el `goal` no cubría la tab Detalle de una obra existente, que es un tercio del alcance, y se amplió; «`CreateSiteDto`» no existe, el cuerpo del endpoint es `SiteInputDto`; y la sección de UI no decía qué recibe el mapa cuando la propiedad todavía no existe: ahora dice que recibe la dirección escrita en la hoja y devuelve el punto, y que el bloque se separa en lo que dibuja y lo que lee |
| 2026-09-22 | borrador | Creado. Sale de probar el alta con los clientes reales de William: la propiedad se crea sin pasar por el mapa y la obra queda sin geocerca. Verificado antes de escribir que el contrato ya acepta el punto al crear, así que el API no cambia. |
