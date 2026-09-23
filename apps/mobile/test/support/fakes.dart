import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snapline/core/navigation/last_destination_store.dart';
import 'package:snapline/core/session/session_storage.dart';
import 'package:snapline/core/theme/locale_store.dart';
import 'package:snapline/core/theme/theme_store.dart';
import 'package:snapline/main.dart';
import 'package:snapline/api/models/project_status.dart';
import 'package:snapline/data/local/app_database.dart';
import 'package:uuid/uuid.dart';
import 'package:snapline/data/repositories/time_entry_repository.dart';
import 'package:snapline/data/sync/outbox.dart';
import 'package:snapline/data/local/tables.dart';
import 'package:snapline/data/sync/connectivity.dart';
import 'package:snapline/data/sync/sync_controller.dart';

import 'package:snapline/api/models/auth_membership_dto.dart';
import 'package:snapline/api/models/auth_membership_dto_role.dart';
import 'package:snapline/api/models/auth_user_dto.dart';
import 'package:snapline/api/models/auth_user_dto_locale.dart';
import 'package:snapline/core/navigation/app_destination.dart';
import 'package:snapline/core/location/device_location.dart';
import 'package:snapline/core/location/device_geocoder.dart';
import 'package:snapline/core/location/map_type_store.dart';
import 'package:snapline/api/clients/media_client.dart';
import 'package:snapline/core/network/api_client.dart';
import 'package:snapline/core/theme/app_theme.dart';
import 'package:snapline/l10n/app_localizations.dart';
import 'package:snapline/core/media/photo_capture.dart';
import 'package:snapline/core/session/session.dart';

/// Almacenamiento en memoria: el Keychain no existe en un test de unidad.
class FakeSessionStorage implements SessionStorage {
  FakeSessionStorage([this.session]);

  Session? session;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Lo mismo para la preferencia de pestaña: `SharedPreferences` tampoco existe
/// en un test de unidad.
class FakeLastDestinationStore implements LastDestinationStore {
  FakeLastDestinationStore([this.destination]);

  AppDestination? destination;

  @override
  Future<AppDestination?> read() async => destination;

  @override
  Future<void> write(AppDestination value) async => destination = value;

  @override
  Future<void> clear() async => destination = null;
}

/// El idioma elegido, en memoria.
class FakeLocaleStore implements LocaleStore {
  FakeLocaleStore([this.locale]);

  Locale? locale;

  @override
  Future<Locale?> read() async => locale;

  @override
  Future<void> write(Locale? value) async => locale = value;
}

/// El tema elegido, en memoria.
class FakeMapTypeStore implements MapTypeStore {
  FakeMapTypeStore([this.satellite = false, this.demora = Duration.zero]);

  bool satellite;

  /// Para probar que un toque no lo pisa una lectura que llega tarde.
  final Duration demora;

  @override
  Future<bool> readSatellite() async {
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    return satellite;
  }

  @override
  Future<void> writeSatellite(bool value) async => satellite = value;
}

class FakeThemeStore implements ThemeStore {
  FakeThemeStore([this.mode]);

  ThemeMode? mode;

  @override
  Future<ThemeMode?> read() async => mode;

  @override
  Future<void> write(ThemeMode value) async => mode = value;
}

/// Los mismos que devuelve el API para cada rol. Ver `permissionsForRole` en
/// `apps/api/src/auth/permissions.ts`.
const permisosWorker = [
  'projects.read',
  'time.clock',
  'media.capture',
  'media.read',
  'profile.write',
];

const permisosForeman = [
  'projects.read',
  'crews.read',
  'time.clock',
  'time.read',
  'media.capture',
  'media.read',
  'profile.write',
];

const permisosAccountant = [
  'customers.read',
  'projects.read',
  'time.read',
  'catalog.read',
  'billing.read',
  'reports.read',
  'profile.write',
];

const permisosOwner = [
  'customers.read',
  'customers.write',
  'projects.read',
  'projects.write',
  'projects.publish',
  'crews.read',
  'crews.write',
  'time.clock',
  'time.read',
  'time.approve',
  'media.capture',
  'media.read',
  'media.visibility',
  'media.delete',
  'catalog.read',
  'catalog.write',
  'billing.read',
  'billing.write',
  'reports.read',
  'members.manage',
  'profile.write',
];

/// `ADMIN` tiene exactamente lo mismo que `OWNER` en `permissions.ts`.
const permisosPorRol = <AuthMembershipDtoRole, List<String>>{
  AuthMembershipDtoRole.owner: permisosOwner,
  AuthMembershipDtoRole.admin: permisosOwner,
  AuthMembershipDtoRole.foreman: permisosForeman,
  AuthMembershipDtoRole.worker: permisosWorker,
  AuthMembershipDtoRole.accountant: permisosAccountant,
};

Session buildSession({
  String name = 'William Ferman',
  AuthUserDtoLocale locale = AuthUserDtoLocale.es,
  String companyName = 'Professional Construction LLC',
  AuthMembershipDtoRole role = AuthMembershipDtoRole.owner,
  List<String>? permissions,
  DateTime? expiresAt,
}) {
  final membership = AuthMembershipDto(
    id: 'm1',
    companyId: 'c1',
    companyName: companyName,
    role: role,
    permissions: permissions ?? permisosPorRol[role] ?? permisosOwner,
  );

  return Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    accessTokenExpiresAt:
        expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
    user: AuthUserDto(
      id: 'u1',
      name: name,
      locale: locale,
      email: 'w@example.com',
      phone: '+13015550142',
    ),
    membership: membership,
    memberships: [membership],
  );
}

/// Base en memoria: cada test arranca con la suya, vacía.
AppDatabase testDatabase() => AppDatabase(NativeDatabase.memory());

TimeEntryRepository testTimeEntryRepository(AppDatabase db) =>
    TimeEntryRepository(db, Outbox(db, const Uuid()), const Uuid());

/// No toca la red. La sincronización de verdad se prueba contra el API en
/// `integration_test/`; acá lo que importa es que la UI lea de local.
class FakeSyncController extends SyncController {
  /// Cuántas veces se pidió sincronizar a mano. Lo usa el test del gesto de
  /// tirar para refrescar.
  static int refrescos = 0;

  @override
  Future<bool> build() async => true;

  @override
  Future<void> refresh() async => refrescos++;
}

/// El cliente de media que nunca se llama.
///
/// Solo `cambiarVisibilidad` toca la red desde el repositorio, y ningún test de
/// captura o de subida pasa por ahí.
class MediaClientNulo implements MediaClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('el test no debería llamar al API de media');
}

class _GeocoderNulo implements DeviceGeocoder {
  const _GeocoderNulo();

  @override
  Future<GeocodedAddress?> fromCoordinates(double lat, double lng) async =>
      null;

  @override
  Future<({double lat, double lng})?> searchAddress(String address) async =>
      null;
}

class _CamaraNula implements PhotoCapture {
  @override
  Future<String?> takePhoto() async => null;

  @override
  Future<PhotoResult> capture(PhotoQuality calidad) async =>
      const PhotoResult.failed(PhotoFailure.cancelled);
}

/// La app montada para un test: base en memoria, sin red, con la sesión que se
/// le pase. Evita repetir seis overrides en cada caso.
Widget testApp({
  required AppDatabase db,
  Session? session,
  bool sinSesion = false,
  AppDestination? lastDestination,
  FakeLastDestinationStore? lastDestinationStore,
  LocaleStore? localeStore,
  ThemeStore? themeStore,
  DeviceLocation? deviceLocation,
  DeviceGeocoder? deviceGeocoder,
  PhotoCapture? photoCapture,
}) {
  return ProviderScope(
    overrides: [
      if (deviceLocation != null)
        deviceLocationProvider.overrideWithValue(deviceLocation),
      // Siempre falso, como la cámara: el real es un canal de plataforma.
      deviceGeocoderProvider.overrideWithValue(
        deviceGeocoder ?? const _GeocoderNulo(),
      ),
      // Siempre con cámara falsa: la real es un canal de plataforma que en un
      // test cuelga para siempre bajo el reloj falso.
      photoCaptureProvider.overrideWithValue(photoCapture ?? _CamaraNula()),
      appDatabaseProvider.overrideWithValue(db),
      syncControllerProvider.overrideWith(FakeSyncController.new),
      sessionStorageProvider.overrideWithValue(
        FakeSessionStorage(sinSesion ? null : (session ?? buildSession())),
      ),
      lastDestinationStoreProvider.overrideWithValue(
        lastDestinationStore ?? FakeLastDestinationStore(lastDestination),
      ),
      localeStoreProvider.overrideWithValue(localeStore ?? FakeLocaleStore()),
      // El plugin de conectividad no existe en un test: su stream se quedaría
      // abierto y el árbol nunca terminaría de desmontarse.
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      connectivityWatcherProvider.overrideWithValue(const FakeConnectivity()),
      themeStoreProvider.overrideWithValue(themeStore ?? FakeThemeStore()),
      mapTypeStoreProvider.overrideWithValue(FakeMapTypeStore()),
    ],
    child: const SnaplineApp(),
  );
}

/// Monta **un widget suelto** con lo mínimo: base, sesión y tema, sin el router
/// ni el shell. Para probar una pantalla entera dentro de la app está `testApp`.
///
/// Trae el `MaterialApp` con los dos temas y los delegados de idioma, que es lo
/// que hace falta para verificar que nada esté quemado y que se vea en oscuro.
Widget testWidget({
  required AppDatabase db,
  required Widget child,
  Session? session,
  AuthUserDtoLocale locale = AuthUserDtoLocale.es,
  ThemeMode themeMode = ThemeMode.light,
  PhotoCapture? photoCapture,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      photoCaptureProvider.overrideWithValue(photoCapture ?? _CamaraNula()),
      mediaClientProvider.overrideWithValue(MediaClientNulo()),
      sessionStorageProvider.overrideWithValue(
        FakeSessionStorage(session ?? buildSession(locale: locale)),
      ),
      syncControllerProvider.overrideWith(FakeSyncController.new),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      connectivityWatcherProvider.overrideWithValue(const FakeConnectivity()),
    ],
    child: MaterialApp(
      locale: Locale(locale.name),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: Scaffold(body: child),
    ),
  );
}

/// Siembra una obra con su cliente y su sitio, como si hubiera bajado del
/// servidor: todo `SYNCED`, que es como entra lo que ya está allá.
Future<void> seedProject(
  AppDatabase db, {
  required String id,
  required String name,
  required String customerName,
  ProjectStatus status = ProjectStatus.inProgress,
  String line1 = '412 Ellsworth Dr',
  String city = 'Silver Spring',
  double? siteLat,
  double? siteLng,
  DateTime? createdAt,
  SyncStatus syncStatus = SyncStatus.synced,
}) async {
  final ahora = DateTime.now();
  final customerId = 'c-$id';
  final siteId = 's-$id';

  await db
      .into(db.customers)
      .insertOnConflictUpdate(
        CustomersCompanion.insert(
          id: customerId,
          companyId: 'c1',
          updatedAt: ahora,
          displayName: customerName,
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db
      .into(db.sites)
      .insertOnConflictUpdate(
        SitesCompanion.insert(
          id: siteId,
          companyId: 'c1',
          updatedAt: ahora,
          customerId: customerId,
          // Los seis campos, no tres: `AddressDto` exige `postalCode`, así que una
          // dirección incompleta la descartaba `AddressJson.decode` y la propiedad
          // salía vacía en toda la app — con los tests pasando igual.
          address: jsonEncode({
            'line1': line1,
            'city': city,
            'state': 'MD',
            'postalCode': '20910',
            'country': 'US',
          }),
          lat: Value(siteLat),
          lng: Value(siteLng),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db
      .into(db.projects)
      .insertOnConflictUpdate(
        ProjectsCompanion.insert(
          id: id,
          companyId: 'c1',
          updatedAt: ahora,
          customerId: customerId,
          siteId: siteId,
          name: name,
          status: status.json!,
          clientVisibilityMode: 'STAGES',
          createdAt: Value(createdAt),
          syncStatus: Value(syncStatus),
        ),
      );
}

/// Siembra un cliente como si hubiera bajado del servidor, con su propiedad
/// opcional. `SYNCED`, que es como entra lo que ya está allá.
Future<void> seedCustomer(
  AppDatabase db, {
  required String id,
  required String displayName,
  String? companyName,
  String? phone,
  String? email,
  String? siteLine1,
  double? siteLat,
  double? siteLng,
  SyncStatus syncStatus = SyncStatus.synced,
}) async {
  final ahora = DateTime.now();

  await db
      .into(db.customers)
      .insertOnConflictUpdate(
        CustomersCompanion.insert(
          id: id,
          companyId: 'c1',
          updatedAt: ahora,
          displayName: displayName,
          companyName: Value(companyName),
          phone: Value(phone),
          email: Value(email),
          syncStatus: Value(syncStatus),
        ),
      );

  if (siteLine1 != null) {
    await db
        .into(db.sites)
        .insertOnConflictUpdate(
          SitesCompanion.insert(
            id: 's-$id',
            companyId: 'c1',
            updatedAt: ahora,
            customerId: id,
            address: jsonEncode({
              'line1': siteLine1,
              'city': 'Silver Spring',
              'state': 'MD',
              'postalCode': '20910',
              'country': 'US',
            }),
            lat: Value(siteLat),
            lng: Value(siteLng),
            syncStatus: Value(syncStatus),
          ),
        );
  }
}

/// Monta la app para un test.
///
/// Hay que cerrarla con [disposeApp] antes de que el caso termine: Drift crea un
/// timer al cancelar sus streams, y el framework verifica que no queden timers
/// **antes** de correr los `tearDown`. Desmontar ahí llega tarde.
Future<void> pumpApp(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
}

/// Desmonta el árbol y deja correr el timer que Drift agenda al cancelar sus
/// streams. Sin esto el caso termina en "A Timer is still pending".
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // El timer nace durante el desmontaje, así que hace falta un frame más para
  // que llegue a ejecutarse. Sin esto el caso termina con él todavía en cola.
  await tester.pump(const Duration(milliseconds: 100));
}

/// `testWidgets` que desmonta el árbol al terminar, pase lo que pase.
///
/// Se usa en todo caso que monte la app. Dejarlo a cargo de cada test es
/// olvidarse en uno y perseguir un "A Timer is still pending" que no dice de
/// dónde salió.
void testWithApp(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await disposeApp(tester);
    }
  });
}

/// Siempre con red y sin canal de plataforma. Sin esto el motor se suscribe al
/// `Connectivity` real, que en un test no existe.
class FakeConnectivity implements ConnectivityWatcher {
  const FakeConnectivity({this.hay = const [true]});

  final List<bool> hay;

  @override
  Stream<bool> hayInterfaz() => Stream.fromIterable(hay);
}
