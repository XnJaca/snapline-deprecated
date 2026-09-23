import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../api/models/address_dto.dart';
import '../local/address_json.dart';
import '../local/app_database.dart';
import '../local/tables.dart';
import '../sync/outbox.dart';

/// Un cliente como lo muestra la lista.
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.displayName,
    required this.companyName,
    required this.phone,
    required this.email,
    required this.pending,
  });

  final String id;
  final String displayName;
  final String? companyName;
  final String? phone;
  final String? email;

  /// Todavía no llegó al servidor.
  final bool pending;

  /// Sin ninguno de los dos no puede entrar al portal del cliente.
  bool get canBeInvited =>
      (email?.isNotEmpty ?? false) || (phone?.isNotEmpty ?? false);
}

/// La ficha completa, con la dirección ya parseada.
class CustomerDetail {
  const CustomerDetail({
    required this.id,
    required this.displayName,
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.billingAddress,
    required this.source,
    required this.notes,
    required this.pending,
  });

  final String id;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? email;
  final String? phone;
  final AddressDto? billingAddress;
  final String? source;
  final String? notes;

  final bool pending;

  bool get canBeInvited =>
      (email?.isNotEmpty ?? false) || (phone?.isNotEmpty ?? false);
}

/// Una propiedad del cliente.
class SiteSummary {
  const SiteSummary({
    required this.id,
    required this.customerId,
    required this.address,
    required this.pending,
    this.lat,
    this.lng,
    this.geofenceRadiusM,
  });

  final String id;
  final String customerId;
  final AddressDto? address;
  final bool pending;

  /// El punto de la propiedad. Nulo mientras nadie lo fijó, que es el estado de
  /// todo lo cargado antes de SPEC-0007.
  final double? lat;
  final double? lng;

  /// Nulo es válido: cae al default, no es un formulario a medio llenar.
  final int? geofenceRadiusM;

  factory SiteSummary.fromLocal(LocalSite fila) => SiteSummary(
    id: fila.id,
    customerId: fila.customerId,
    address: AddressJson.decode(fila.address),
    pending: fila.syncStatus != SyncStatus.synced,
    lat: fila.lat,
    lng: fila.lng,
    geofenceRadiusM: fila.geofenceRadiusM,
  );

  /// Los dos o ninguno: media coordenada no ubica nada.
  bool get hasLocation => lat != null && lng != null;

  String get oneLine => AddressJson.oneLine(address);
}

/// Lo que la pantalla de alta y de edición devuelve. Un solo tipo para los dos:
/// el alta manda lo mínimo y la edición manda todo, pero el payload es el mismo.
class CustomerInput {
  const CustomerInput({
    required this.displayName,
    this.firstName,
    this.lastName,
    this.companyName,
    this.email,
    this.phone,
    this.billingAddress,
    this.source,
    this.notes,
  });

  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? email;
  final String? phone;
  final AddressDto? billingAddress;
  final String? source;
  final String? notes;

  /// Lo que viaja al servidor. Los vacíos se omiten: un `""` en un `@IsEmail()`
  /// del API es un 400, y significa lo mismo que no mandarlo.
  Map<String, Object?> toPayload() => {
    'displayName': displayName,
    if (_hay(firstName)) 'firstName': firstName,
    if (_hay(lastName)) 'lastName': lastName,
    if (_hay(companyName)) 'companyName': companyName,
    if (_hay(email)) 'email': email,
    if (_hay(phone)) 'phone': phone,
    if (billingAddress != null) 'billingAddress': billingAddress!.toJson(),
    if (_hay(source)) 'source': source,
    if (_hay(notes)) 'notes': notes,
  };

  static bool _hay(String? valor) => valor != null && valor.isNotEmpty;
}

/// La puerta de las pantallas a los clientes y sus propiedades.
///
/// **Lee de Drift y escribe en Drift.** Nadie llama al API: una escritura se
/// aplica local y se encola, y el sincronizador se ocupa cuando haya señal.
class CustomerRepository {
  const CustomerRepository(this._db, this._outbox, this._uuid);

  final AppDatabase _db;
  final Outbox _outbox;
  final Uuid _uuid;

  // ─── Lectura ───────────────────────────────────────────────────────────────

  /// La lista, filtrada por lo que se haya escrito en el buscador.
  ///
  /// Busca por nombre, empresa y teléfono, que es lo que William tiene a mano
  /// cuando llama alguien: un nombre a medias o los últimos dígitos.
  Stream<List<CustomerSummary>> watchAll({String query = ''}) {
    final consulta = _db.select(_db.customers)
      ..where((c) => c.deletedAt.isNull());

    final buscado = query.trim().toLowerCase();
    if (buscado.isNotEmpty) {
      final patron = '%$buscado%';
      consulta.where(
        (c) =>
            c.displayName.lower().like(patron) |
            c.companyName.lower().like(patron) |
            c.phone.lower().like(patron),
      );
    }
    consulta.orderBy([(c) => OrderingTerm.asc(c.displayName)]);

    return consulta.watch().map(
      (filas) => filas.map(_resumen).toList(growable: false),
    );
  }

  Stream<CustomerDetail?> watchOne(String id) {
    return (_db.select(_db.customers)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((fila) => fila == null ? null : _detalle(fila));
  }

  /// Las propiedades de un cliente. Incluye las que todavía no sincronizaron:
  /// se crearon en este dispositivo y ya se pueden usar para una obra.
  Stream<List<SiteSummary>> watchSites(String customerId) {
    return (_db.select(_db.sites)
          ..where((s) => s.customerId.equals(customerId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.updatedAt)]))
        .watch()
        .map((filas) => filas.map(_sitio).toList(growable: false));
  }

  // ─── Escritura ─────────────────────────────────────────────────────────────

  /// Da de alta un cliente y devuelve su id.
  ///
  /// El id es UUIDv7 del dispositivo y es el definitivo: el mismo con el que va a
  /// quedar en el servidor, así que se puede usar de inmediato para colgarle una
  /// propiedad o una obra aunque no haya señal (regla 18).
  Future<String> create(CustomerInput input, {DateTime? occurredAt}) async {
    final id = _uuid.v7();
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await _db
          .into(_db.customers)
          .insert(
            CustomersCompanion.insert(
              id: id,
              // Lo pone el servidor al aplicar; en local alcanza para que la fila
              // exista y la pantalla la muestre.
              companyId: '',
              updatedAt: cuando,
              syncStatus: const Value(SyncStatus.pending),
              displayName: input.displayName,
              firstName: Value(input.firstName),
              lastName: Value(input.lastName),
              companyName: Value(input.companyName),
              email: Value(input.email),
              phone: Value(input.phone),
              billingAddress: Value(AddressJson.encode(input.billingAddress)),
              source: Value(input.source),
              notes: Value(input.notes),
            ),
          );
      await _outbox.enqueue(
        type: SyncOp.customerCreate,
        targetId: id,
        payload: input.toPayload(),
        occurredAt: cuando,
      );
    });

    return id;
  }

  /// Corrige un cliente. Última escritura gana, así que se manda la ficha
  /// entera y no un diff: dos correcciones desde dos teléfonos no se mezclan
  /// campo por campo.
  Future<void> update(
    String id,
    CustomerInput input, {
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
        CustomersCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          displayName: Value(input.displayName),
          firstName: Value(input.firstName),
          lastName: Value(input.lastName),
          companyName: Value(input.companyName),
          email: Value(input.email),
          phone: Value(input.phone),
          billingAddress: Value(AddressJson.encode(input.billingAddress)),
          source: Value(input.source),
          notes: Value(input.notes),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.customerUpdate,
        targetId: id,
        payload: input.toPayload(),
        occurredAt: cuando,
      );
    });
  }

  /// Agrega una propiedad y devuelve su id.
  ///
  /// El punto y el radio, si se fijaron en el alta, viajan en el mismo
  /// `site.create`: una sola operación y no un `site.update` detrás.
  Future<String> addSite(
    String customerId,
    AddressDto address, {
    double? lat,
    double? lng,
    int? geofenceRadiusM,
    DateTime? occurredAt,
  }) async {
    final id = _uuid.v7();
    final cuando = occurredAt ?? DateTime.now();
    // Los dos o ninguno: media coordenada no ubica nada.
    final conPunto = lat != null && lng != null;

    await _db.transaction(() async {
      await _db
          .into(_db.sites)
          .insert(
            SitesCompanion.insert(
              id: id,
              companyId: '',
              updatedAt: cuando,
              syncStatus: const Value(SyncStatus.pending),
              customerId: customerId,
              address: AddressJson.encode(address)!,
              lat: Value(conPunto ? lat : null),
              lng: Value(conPunto ? lng : null),
              geofenceRadiusM: Value(conPunto ? geofenceRadiusM : null),
            ),
          );
      await _outbox.enqueue(
        type: SyncOp.siteCreate,
        targetId: id,
        // De qué cliente cuelga viaja en el payload: una propiedad no existe
        // suelta, y `targetId` es el id de la propiedad misma.
        payload: {
          'customerId': customerId,
          'address': address.toJson(),
          if (conPunto) ...{
            'lat': lat,
            'lng': lng,
            // Sin radio elegido no se manda el campo: el servidor lo valida
            // como positivo y rechazaría un nulo explícito.
            'geofenceRadiusM': ?geofenceRadiusM,
          },
        },
        occurredAt: cuando,
      );
    });

    return id;
  }

  /// Fija el punto de una propiedad y el radio de su geocerca.
  ///
  /// Va aparte de [updateSite] porque son dos acciones distintas: corregir una
  /// dirección y ubicarla en el mapa. Manda solo estos campos, así que una
  /// corrección de dirección encolada aparte no se pisa.
  Future<void> setSiteLocation(
    String siteId, {
    required double lat,
    required double lng,
    int? geofenceRadiusM,
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          lat: Value(lat),
          lng: Value(lng),
          geofenceRadiusM: Value(geofenceRadiusM),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.siteUpdate,
        targetId: siteId,
        payload: {
          'lat': lat,
          'lng': lng,
          // Sin radio elegido no se manda el campo: el servidor lo valida como
          // positivo y rechazaría un nulo explícito.
          'geofenceRadiusM': ?geofenceRadiusM,
        },
        occurredAt: cuando,
      );
    });
  }

  /// Corrige la dirección de una propiedad.
  ///
  /// El punto y el radio no se tocan desde acá: los fija [setSiteLocation].
  Future<void> updateSite(
    String siteId,
    AddressDto address, {
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          address: Value(AddressJson.encode(address)!),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.siteUpdate,
        targetId: siteId,
        payload: {'address': address.toJson()},
        occurredAt: cuando,
      );
    });
  }

  // ─── Mapeo ─────────────────────────────────────────────────────────────────

  static CustomerSummary _resumen(LocalCustomer fila) => CustomerSummary(
    id: fila.id,
    displayName: fila.displayName,
    companyName: fila.companyName,
    phone: fila.phone,
    email: fila.email,
    pending: fila.syncStatus != SyncStatus.synced,
  );

  static CustomerDetail _detalle(LocalCustomer fila) => CustomerDetail(
    id: fila.id,
    displayName: fila.displayName,
    firstName: fila.firstName,
    lastName: fila.lastName,
    companyName: fila.companyName,
    email: fila.email,
    phone: fila.phone,
    billingAddress: AddressJson.decode(fila.billingAddress),
    source: fila.source,
    notes: fila.notes,
    pending: fila.syncStatus != SyncStatus.synced,
  );

  static SiteSummary _sitio(LocalSite fila) => SiteSummary.fromLocal(fila);
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(outboxProvider),
    ref.watch(uuidProvider),
  );
});

/// La lista, con el texto del buscador como parámetro. Riverpod cachea por
/// consulta, así que volver a un término ya escrito no vuelve a consultar.
final customersProvider = StreamProvider.family<List<CustomerSummary>, String>((
  ref,
  query,
) {
  return ref.watch(customerRepositoryProvider).watchAll(query: query);
});

final customerByIdProvider = StreamProvider.family<CustomerDetail?, String>((
  ref,
  id,
) {
  return ref.watch(customerRepositoryProvider).watchOne(id);
});

final customerSitesProvider = StreamProvider.family<List<SiteSummary>, String>((
  ref,
  customerId,
) {
  return ref.watch(customerRepositoryProvider).watchSites(customerId);
});
