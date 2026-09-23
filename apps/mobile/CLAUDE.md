# CLAUDE.md — apps/mobile

App de campo en Flutter. Las reglas duras están en el `CLAUDE.md` raíz; acá va lo
específico de esta carpeta. La arquitectura se decidió en ADR-0008 y el sistema de
diseño en ADR-0009.

**Esta app está fuera del workspace de pnpm**, a propósito: pub y pnpm no se
mezclan. No aparece en `pnpm-workspace.yaml` y no la toca `turbo`.

## Dependencias no obvias

| Paquete | Por qué está |
|---|---|
| `phone_form_field` | Un teléfono no se puede validar sin saber su país: diez dígitos son válidos en Estados Unidos y no en Guatemala. Trae los datos de libphonenumber portados a **Dart puro**, así que valida sin señal, y sus textos ya vienen en `en` y `es` |
| `flutter_country_selector` | Viene con el anterior; se usa directo para el país de una dirección y para los nombres de país traducidos. Una sola lista de países en la app |
| `google_maps_flutter` | El mapa donde se fija el punto de una propiedad. Elegido en ADR-0012: los SDK móviles son gratis y sin límite, y los tiles públicos de OSM no se pueden usar comercialmente |
| `geolocator` | Lee la posición **una sola vez**, al tocar "usar mi ubicación". No se usa su stream: la visión descarta el tracking continuo |
| `geocoding` | Del punto a la dirección, con el geocodificador **del teléfono**: sin llave ni SKU de Google. Rellena los campos vacíos al fijar el punto en el alta de una propiedad. Adenda de ADR-0012 |
| `url_launcher` | Abre la dirección en la app de mapas del teléfono. Construir navegación adentro es lo que la visión descarta |

Los dos se registran en `main.dart` vía `PhoneFieldLocalization.delegates`. Sin
eso el selector sale en inglés con la app en español.

La lista de países ofrecidos es corta a propósito y vive en
`core/i18n/supported_countries.dart`.

## Levantar en desarrollo

```bash
flutter pub get
dart run swagger_parser                              # cliente desde openapi.json
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Los tres comandos del medio son obligatorios después de clonar: **el código
generado no se versiona.** Son ~240 archivos y versionarlos haría ilegible el diff
de cualquier PR.

### La llave de Google Maps

**No se versiona, y sin ella la app compila y corre igual** — solo el mapa queda
gris. Clonar el repo no exige tener llave.

| Plataforma | Dónde va | Archivo |
|---|---|---|
| Android | `MAPS_API_KEY=...` | `android/local.properties` |
| iOS | `MAPS_API_KEY = ...` | `ios/Flutter/Secrets.xcconfig`, copiado de `Secrets.example.xcconfig` |

Son **dos llaves distintas**, cada una restringida a su plataforma: SHA-1 del
certificado en Android, bundle id en iOS. Una filtrada no sirve en la otra.

iOS pide **deployment target 14.0** como mínimo, que es lo que exige
`google_maps_flutter_ios`. Está fijado en el `Podfile` y en el proyecto de Xcode.

### Si iOS deja de linkear: `Framework 'Pods_Runner' not found`

Pasa después de cambiar de rama o de que se borren ramas mergeadas: la carpeta
`Pods/` no se versiona y queda desincronizada del `Podfile` del branch actual.

```bash
cd ios && rm -rf Pods .symlinks && pod install
```

## Código generado — qué lo produce

| Qué | Comando | Sale en |
|---|---|---|
| Cliente y DTOs del API | `dart run swagger_parser` | `lib/api/` |
| `.g.dart` de json_serializable, Retrofit y Drift | `dart run build_runner build` | junto a su fuente |
| `AppLocalizations` | `flutter pub get` o `flutter gen-l10n` | `lib/l10n/` |
| Tokens de diseño | `pnpm tokens:generate` (desde la raíz) | `lib/core/theme/tokens.dart` |

**`tokens.dart` es la excepción que sí se versiona.** Los demás generados quedan
fuera de git porque son cientos de archivos; este es uno solo, lo consume todo el
tema, y su comando vive del lado de pnpm — pedirle a alguien que corra el generador
de Node antes de abrir el proyecto en Flutter sería una trampa.

`lib/api/` **no se edita a mano.** Sale de `openapi.json` en la raíz del monorepo,
que emite el API desde sus DTOs. Si falta un campo, el arreglo va en `apps/api`, no
acá. Ver ADR-0007.

El orden importa: `swagger_parser` primero, porque `build_runner` genera los
`.g.dart` de lo que aquel escribió.

## Estructura

```
lib/
├── core/            tema, i18n, router, navegación, db, red, errores
├── api/             generado — no se edita
├── data/            tablas Drift, repositorios, sincronizador y bandeja de salida
└── features/        una carpeta por frente del producto
```

Por feature, no por capa: agregar una pantalla toca un solo directorio.

## Offline es el camino normal, no un caso especial

**La UI nunca lee de la red.** Lee de Drift y observa sus streams; el sincronizador
escribe en Drift y la pantalla se actualiza sola. Sin señal no hay ninguna ruta
distinta que recorrer.

- Toda fila que sincroniza lleva `sync_status`: `PENDING | SYNCING | SYNCED | CONFLICT`.
- `CONFLICT` solo lo produce `time_entry` y **lo resuelve un humano** (regla 12).
  Todo lo demás va con última escritura gana.
- Las mutaciones pendientes viven en una **tabla** de bandeja de salida, no en
  memoria: sobreviven a que el sistema mate la app.
- Cada una guarda su clave de idempotencia y se reintenta con esa misma (regla 19).
- Los IDs son UUIDv7 **generados en el dispositivo** (regla 18). El registro nace
  con su ID definitivo.

## Tema — cero valores literales

Los widgets consumen el tema. Un `Color(0x...)`, un `EdgeInsets.all(16)` o un
`fontSize: 16` fuera de `lib/core/theme/` es un error de revisión.

```dart
// ❌
Container(padding: const EdgeInsets.all(16), color: const Color(0xFF1D4ED8))

// ✅
Container(padding: EdgeInsets.all(context.spacing.lg), color: context.colors.primary)
```

Los accesos son `context.spacing`, `context.colors`, `context.texts` y
`context.statusColors`, definidos en `core/theme/theme_extensions.dart`.

- `context.colors` es el `ColorScheme` de Material: `error` es danger, `outline` es
  border y `onSurfaceVariant` es el texto atenuado.
- `context.statusColors` tiene solo lo que Material no cubre: `warning` y `success`
  con sus variantes `container`, que son las banderas de asistencia.

### La regla del naranja

El acento está a 17 grados del rojo de error y a 18 del ámbar de las banderas. Medido.
El tono no alcanza para distinguirlos, así que lo hace la forma:

- **El naranja saturado es exclusivo de la acción primaria.** Un botón sólido por
  pantalla. Si dos cosas son naranjas, ninguna es la acción.
- **Los estados van siempre en `container` / `onContainer`**: fondo tenue, texto
  oscuro, icono. Nunca relleno sólido.
- **El icono es obligatorio en todo estado.** Nunca color solo.

```dart
// ❌ compite con la acción primaria y depende solo del color
Container(color: context.statusColors.warning, child: Text(l10n.flagOutsideGeofence))

// ✅
Container(
  color: context.statusColors.warningContainer,
  child: Row(children: [
    Icon(Icons.warning_amber_rounded, color: context.statusColors.onWarningContainer),
    Text(l10n.flagOutsideGeofence),
  ]),
)
```

### Dos alturas de acción primaria, y no son intercambiables

- **`FilledButton`** sale del tema a 52dp: el "Guardar" de un formulario, el
  "Entrar" del login. Arriba del mínimo táctil de Material.
- **`FieldActionButton`** sube a 64dp y se pide a mano: es la acción que se pulsa
  **con guantes sobre un techo** —marcar entrada, tomar la foto—, donde fallar el
  toque es fallar la jornada.

Los 64 estuvieron en el tema y hacían que un formulario de quince campos entrara
a la mitad en pantalla. Ver ADR-0009.

### Widgets de formulario que ya existen

No volver a resolverlos por pantalla:

| Widget | Para qué |
|---|---|
| `FormFooter` | La acción al pie, **con el área segura de abajo**. Sin él el botón queda bajo la barra gestual y el toque se lo lleva el sistema |
| `PhoneField` | Teléfono con selector de país y validación por país. Guarda E.164 |
| `CountryField` | El país de una dirección, elegido de lista y nunca tecleado |
| `HelpButton` / `showHelpSheet` | Explicar algo que la interfaz nombra pero no puede explicar al lado de un campo |
| `AddressFields` | Los seis campos de una dirección, con su modo opcional |

**Lo obligatorio se dice en el label, con palabras**: `l10n.fieldRequiredLabel(...)`
produce "Nombre (obligatorio)". Un asterisco solo lo entiende quien ya conoce la
convención, y esta app se usa sin entrenamiento.

**El teclado ya se cierra al tocar afuera, en toda la app.** `DismissKeyboard` está
en `MaterialApp.builder`, así que no hay que resolverlo por pantalla — y no se hace
con `GestureDetector`: el gesto lo gana el hijo y un `onTap` de ancestro nunca
dispara. Va con `Listener` sobre los eventos de puntero, y **excluye los toques que
caen sobre otro campo** con un hit test, o el teclado parpadearía al saltar de uno
al siguiente.

### Los estados se muestran con `StatusChip` o `StatusLine`, según cuántos haya

No se arma a mano un contenedor de color: `core/widgets/status_chip.dart` ya trae
el par `container`/`onContainer` y el icono obligatorio por tono.

```dart
StatusChip(tone: StatusTone.warning, label: l10n.flagOutsideGeofence)
StatusChip(tone: StatusTone.danger, label: mensaje, expand: true)  // error de formulario
StatusLine(tone: StatusTone.success, label: l10n.crewInSince(hora))  // fila de lista
```

`expand: true` ocupa el ancho, para errores de formulario. Sin él queda compacto,
para banderas.

**`StatusChip` es para lo que aparece de a uno**: una bandera, un aviso, el estado
de una jornada abierta. **En una lista va `StatusLine`** —icono con el color del
tono y texto atenuado, sin relleno—: un chip por fila convierte cada renglón en un
globo que pesa más que el nombre y más que el botón, y el estado es lectura, no
acción.

### Sesión

`core/session/` es la única puerta a la sesión. Nadie lee tokens de otro lado.

- `sessionControllerProvider` — `AsyncValue<Session?>`; `null` es que no hay sesión.
- La sesión vive en Keychain/Keystore, nunca en la base local ni en preferencias.
- **Un refresh fallido no borra la sesión.** Solo `signOut()` la elimina. Un token
  vencido sin red no puede dejar a un trabajador sin poder capturar.
- El `AuthInterceptor` renueva en `401` y reintenta la petición **una vez**. Varias
  peticiones en paralelo comparten un solo refresh.
- Login y refresh usan `bareDioProvider`, sin interceptor: si no, un login fallido
  dispararía un refresh sobre sí mismo.

### Navegación

`core/navigation/` es el catálogo, no el router. Un eje nuevo se agrega ahí y en
las ramas del `StatefulShellRoute`, en el mismo commit.

- **Cada destino declara su permiso** y se oculta si no está en
  `membership.permissions`. El móvil nunca replica la tabla de roles: qué ejes ve
  cada rol es decisión de producto y vive en `_byRole`; quién puede qué lo dice
  el servidor.
- El orden de `AppDestination.values` **es** el orden de las ramas. Meter uno en
  el medio mueve todas las de abajo.
- El índice visible y el de rama no coinciden: un `WORKER` ve dos pestañas que
  son las ramas 0 y 3. Siempre navegar con `goBranch(destino.index)`.
- **La pestaña activa nunca usa `primary`.** Va en `primaryContainer` /
  `onPrimaryContainer`, y lo mismo las tabs de un proyecto. Ver la regla del
  naranja arriba; hay tests que lo verifican en los dos temas.
- La última pestaña se guarda en `SharedPreferences`, **no** en el almacén
  seguro: es preferencia de interfaz, no credencial. Se valida contra los
  destinos del rol al restaurarla — el teléfono es de la empresa y lo usa más de
  una persona.

Las pantallas de eje usan `AppScaffold`, que ya trae la barra y el botón de
cuenta. `PlaceholderScreen` es andamiaje: cada una se reemplaza cuando su spec
llegue.

**Lo que se abre con `push` deja la pantalla anterior en el árbol**, con su
propio scroll. En un test, `scrollUntilVisible` sin `scrollable:` toma el
primero que encuentra —el de atrás— y desplaza la pantalla equivocada. Hay que
acotarlo con `find.descendant(of: find.byType(LaPantalla), ...)`. Y si el
objetivo vive en una lista horizontal virtualizada, después del scroll va un
`ensureVisible`, o el toque cae en el borde y no pasa nada.

### Dónde puede colarse el naranja sin que se note

Material pinta varios controles con `primary` por defecto, y cada uno de esos es
un naranja saturado que compite con la acción de la pantalla. Ya están cubiertos
en `AppTheme` — `TextButton`, `OutlinedButton`, `Chip`, `SegmentedButton`,
`NavigationBar` y `TabBar`—, pero **un control nuevo probablemente traiga el suyo**: se revisa en
captura, no leyendo el código.

### Tipografía y tamaño de toque

Dos familias, y no se cruzan:

- **Inter** — todo el texto de interfaz. Es la del tema, así que sale sola.
- **Bricolage Grotesque** — **solo el wordmark**, dentro de `core/brand/`. Ningún
  texto de interfaz la usa.

Las dos van embebidas como asset. **No se usa `google_fonts`**: descarga en runtime
y esta app trabaja sin señal.

La marca tiene dos lockups: `SnaplineLogo` horizontal y atenuado para barras, y
`SnaplineLogoStacked` vertical y en color pleno para pantallas donde la marca es
protagonista. El horizontal no crece — a tamaño grande desborda en pantallas
angostas; para eso está el vertical.

Las cifras que corren o se leen en columna —cronómetro, montos— llevan
`FontFeature.tabularFigures()`, que ya trae `displaySmall`. Sin eso el texto se
mueve en cada segundo.

El mínimo táctil de Material es 48dp; acá **la acción primaria es de 64dp y ancho
completo**, porque un dedo con guante de trabajo no acierta un botón de 48.

Ningún control se dimensiona al texto en inglés: "Clock in" son 8 caracteres y
"Marcar entrada" son 14. Si el label no entra en español, el diseño está mal.

Los valores salen de `design-tokens.json` en la raíz. **`core/theme/tokens.dart` es
un archivo generado y no se edita**: lo produce `packages/tokens` con
`pnpm tokens:generate` desde la raíz del monorepo, en el mismo acto que el SCSS de
`apps/web`. Un color se cambia en el JSON, se regenera, y cambia en las dos
superficies.

Las explicaciones de un token —por qué el target de campo son 64dp, por qué las
tipografías van embebidas— viven en el `$comment` de su grupo en el JSON, que sale
como docblock en el archivo generado. Escribirlas en el `.dart` se pierde al
regenerar.

**`ColorScheme.fromSeed` no se usa nunca.** Derivaría colores distintos a los que
usa Angular desde el mismo JSON. Ver ADR-0009.

Toda pantalla se prueba en claro y en oscuro. La pantalla de tokens (`/`) sirve para
verificarlo de un vistazo.

## i18n — cero cadenas quemadas

Ningún texto visible al usuario se escribe literal en un `.dart`.

```dart
// ❌
Text('Clock in')

// ✅
Text(AppLocalizations.of(context).clockIn)
```

Las claves son jerárquicas por frente y pantalla, en camelCase porque `gen-l10n`
las convierte en getters: `timeEntryClockInButton`, no `time_entry.clock_in.button`
ni `clockIn`.

Los dos idiomas, `en` y `es`, se agregan en el mismo commit. Lo que falte queda
listado en `l10n-faltantes.txt` al generar.

El locale es **por usuario**, no por empresa: William administra en inglés y sus
trabajadores probablemente usen la app en español, en la misma cuenta.

## Antes de abrir PR

```bash
flutter analyze
flutter test
```

### Tests de integración

`integration_test/` corre contra el **API de verdad**, en un simulador. Es lo único
que verifica de punta a punta que se entra con teléfono o con email y que el idioma
sale del usuario.

```bash
# desde la raíz del monorepo
pnpm api:db:up && pnpm api:migrate && pnpm api:seed && pnpm api:dev

# en otra terminal
flutter test integration_test/login_test.dart -d <id-del-simulador>
flutter test integration_test/navigation_test.dart -d <id-del-simulador>
```

`integration_test/support/arranque.dart` tiene el arranque limpio, el login y el
menú de cuenta. **Cada caso limpia también la última pestaña guardada**: si no,
abre donde lo dejó el caso anterior y la afirmación se cae sin motivo.

Usuarios del seed: `william@pcdmv.com` (locale `en`, OWNER) y `+15551234567`
(locale `es`, WORKER). Contraseña `Snapline123!` para los dos.

**No afirmes textos de UI que dependan del idioma** cuando no hay sesión: sin
`user.locale` la app cae al idioma del dispositivo, y el test pasa o falla según
cómo esté configurado el simulador.

## Qué NO hacer

- Editar nada de `lib/api/`: se regenera y se pierde.
- Leer de la red desde un widget. Siempre pasa por Drift.
- Resolver un conflicto de `time_entry` automáticamente.
- Borrado duro en tablas que sincronizan (regla 20).
- Aceptar del servidor —o mandarle— valores que él deriva: `withinGeofence`,
  `distanceM`.
- Bloquear el marcaje por falta de GPS, foto o red (regla 9). Se registra con lo
  que haya y se marca con bandera.

## Pendiente conocido

`riverpod_generator` y `riverpod_lint` **no están instalados**: las versiones
compatibles con Riverpod 3 exigen Dart ≥3.12 y el Flutter fijado trae 3.11.5. Los
providers se escriben con la API manual (`Notifier` + `NotifierProvider`), que es
equivalente. Al subir Flutter se pueden agregar sin tocar lo escrito.
