import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../api/models/project_status.dart';
import '../local/address_json.dart';
import 'customer_repository.dart';
import '../local/app_database.dart';
import '../local/tables.dart';
import '../sync/outbox.dart';

/// Una obra con lo que la pantalla necesita mostrar, ya resuelto.
///
/// El cliente y la dirección viven en otras tablas; juntarlos acá evita que cada
/// widget arme su propia consulta y que la lista dispare una por card.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.customerName,
    required this.site,
    required this.status,
    required this.pending,
  });

  final String id;
  final String name;
  final String? description;
  final String customerName;
  final String site;
  final ProjectStatus status;

  /// Todavía no llegó al servidor. La pantalla lo muestra: guardar y que se vea
  /// como si estuviera sincronizado es lo que después nadie entiende.
  final bool pending;
}

/// La obra completa, para la tab de Detalle y para el formulario de edición.
///
/// `ProjectSummary` tiene lo que entra en una card; esto tiene lo que hay que
/// mostrar y poder corregir.
class ProjectDetail {
  const ProjectDetail({
    required this.id,
    required this.customerId,
    required this.siteId,
    required this.name,
    required this.description,
    required this.serviceType,
    required this.status,
    required this.clientVisibilityMode,
    required this.startDate,
    required this.targetEndDate,
    required this.actualEndDate,
    required this.customerName,
    required this.site,
    required this.siteSummary,
    required this.pending,
  });

  final String id;
  final String customerId;
  final String siteId;
  final String name;
  final String? description;
  final String? serviceType;
  final ProjectStatus status;

  /// `STAGES` o `PROGRESS`: qué ve el cliente final de esta obra.
  final String clientVisibilityMode;

  final DateTime? startDate;
  final DateTime? targetEndDate;
  final DateTime? actualEndDate;
  final String customerName;
  final String site;

  /// La propiedad entera, para saber si tiene punto y abrir el mapa desde la
  /// obra. Nula solo si la fila no bajó todavía.
  final SiteSummary? siteSummary;
  final bool pending;
}

/// Con qué visibilidad nace una obra.
///
/// `etapas` de la ficha del dominio: el cliente ve tres hitos y no el avance
/// detallado. Pasar a `avance` es acción explícita, nunca un default.
const initialVisibilityMode = 'STAGES';

/// Lo que la pantalla de alta y de edición devuelve.
///
/// Un solo tipo para las dos: el alta manda lo mínimo del dominio —cliente, sitio,
/// nombre y estado— y la edición manda lo mismo con los opcionales llenos.
class ProjectInput {
  const ProjectInput({
    required this.customerId,
    required this.siteId,
    required this.name,
    required this.status,
    this.description,
    this.serviceType,
    this.startDate,
    this.targetEndDate,
  });

  final String customerId;
  final String siteId;
  final String name;
  final ProjectStatus status;
  final String? description;
  final String? serviceType;
  final DateTime? startDate;
  final DateTime? targetEndDate;

  /// Lo que viaja al servidor. Los vacíos se omiten, y las fechas van en `date`
  /// y no en `date-time`: el contrato las declara así.
  Map<String, Object?> toPayload() => {
    'customerId': customerId,
    'siteId': siteId,
    'name': name,
    'status': status.json,
    if (description?.isNotEmpty ?? false) 'description': description,
    if (serviceType?.isNotEmpty ?? false) 'serviceType': serviceType,
    if (startDate != null) 'startDate': _fecha(startDate!),
    if (targetEndDate != null) 'targetEndDate': _fecha(targetEndDate!),
  };

  static String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// La puerta de las pantallas a las obras.
///
/// **Devuelve streams de la base local, nunca de la red.** El sincronizador
/// escribe en Drift y la pantalla se entera sola; sin señal no hay una ruta
/// distinta que recorrer.
class ProjectRepository {
  const ProjectRepository(this._db, this._outbox, this._uuid);

  final AppDatabase _db;
  final Outbox _outbox;
  final Uuid _uuid;

  /// Lo que está en obra ahora.
  Stream<List<ProjectSummary>> watchInProgress({String query = ''}) =>
      _watch(status: ProjectStatus.inProgress, query: query);

  /// Toda la cartera, o un estado si se pide.
  Stream<List<ProjectSummary>> watchAll({
    ProjectStatus? status,
    String query = '',
  }) => _watch(status: status, query: query);

  /// Las obras de un cliente, en cualquier estado: la ficha del cliente las
  /// muestra todas, incluidas las cerradas.
  Stream<List<ProjectSummary>> watchByCustomer(String customerId) =>
      _watch(customerId: customerId);

  Stream<List<ProjectSummary>> _watch({
    ProjectStatus? status,
    String? customerId,
    String query = '',
  }) {
    final consulta = _db.select(_db.projects).join([
      leftOuterJoin(
        _db.customers,
        _db.customers.id.equalsExp(_db.projects.customerId),
      ),
      leftOuterJoin(_db.sites, _db.sites.id.equalsExp(_db.projects.siteId)),
    ]);

    // Borrado suave: la fila sigue en la base para poder propagarse, pero no se
    // lista (regla 20).
    consulta.where(_db.projects.deletedAt.isNull());
    if (status != null) {
      consulta.where(_db.projects.status.equals(status.json!));
    }
    if (customerId != null) {
      consulta.where(_db.projects.customerId.equals(customerId));
    }

    // Por nombre de obra **o** de cliente: quien busca se acuerda de uno de los
    // dos, y no del mismo siempre.
    final buscado = query.trim().toLowerCase();
    if (buscado.isNotEmpty) {
      final patron = '%$buscado%';
      consulta.where(
        _db.projects.name.lower().like(patron) |
            _db.customers.displayName.lower().like(patron),
      );
    }
    consulta.orderBy([OrderingTerm.desc(_db.projects.updatedAt)]);

    return consulta.watch().map(
      (filas) => filas.map((fila) {
        final proyecto = fila.readTable(_db.projects);
        final cliente = fila.readTableOrNull(_db.customers);
        final sitio = fila.readTableOrNull(_db.sites);

        return ProjectSummary(
          id: proyecto.id,
          name: proyecto.name,
          description: proyecto.description,
          customerName: cliente?.displayName ?? '',
          site: AddressJson.oneLine(AddressJson.decode(sitio?.address)),
          status: ProjectStatus.fromJson(proyecto.status),
          pending: proyecto.syncStatus != SyncStatus.synced,
        );
      }).toList(),
    );
  }

  Stream<ProjectSummary?> watchOne(String id) =>
      _watch().map((todos) => todos.where((p) => p.id == id).firstOrNull);

  /// La obra completa. Para la tab de Detalle y para poder corregirla.
  Stream<ProjectDetail?> watchDetail(String id) {
    final consulta = _db.select(_db.projects).join([
      leftOuterJoin(
        _db.customers,
        _db.customers.id.equalsExp(_db.projects.customerId),
      ),
      leftOuterJoin(_db.sites, _db.sites.id.equalsExp(_db.projects.siteId)),
    ])..where(_db.projects.id.equals(id) & _db.projects.deletedAt.isNull());

    return consulta.watchSingleOrNull().map((fila) {
      if (fila == null) return null;
      final proyecto = fila.readTable(_db.projects);
      final cliente = fila.readTableOrNull(_db.customers);
      final sitio = fila.readTableOrNull(_db.sites);

      return ProjectDetail(
        id: proyecto.id,
        customerId: proyecto.customerId,
        siteId: proyecto.siteId,
        name: proyecto.name,
        description: proyecto.description,
        serviceType: proyecto.serviceType,
        status: ProjectStatus.fromJson(proyecto.status),
        clientVisibilityMode: proyecto.clientVisibilityMode,
        startDate: proyecto.startDate,
        targetEndDate: proyecto.targetEndDate,
        actualEndDate: proyecto.actualEndDate,
        customerName: cliente?.displayName ?? '',
        site: AddressJson.oneLine(AddressJson.decode(sitio?.address)),
        siteSummary: sitio == null ? null : SiteSummary.fromLocal(sitio),
        pending: proyecto.syncStatus != SyncStatus.synced,
      );
    });
  }

  // ─── Escritura ─────────────────────────────────────────────────────────────

  /// Da de alta una obra y devuelve su id.
  ///
  /// El id es UUIDv7 del dispositivo y es el definitivo (regla 18). Nace
  /// `PENDING`: aparece en la cartera al instante, marcada como sin subir.
  Future<String> create(ProjectInput input, {DateTime? occurredAt}) async {
    final id = _uuid.v7();
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: id,
              // Lo pone el servidor al aplicar.
              companyId: '',
              updatedAt: cuando,
              syncStatus: const Value(SyncStatus.pending),
              customerId: input.customerId,
              siteId: input.siteId,
              name: input.name,
              description: Value(input.description),
              serviceType: Value(input.serviceType),
              status: input.status.json!,
              // Arranca en etapas, y pasar a avance es acción explícita: es lo que el
              // cliente final ve de la obra, no un default de formulario.
              clientVisibilityMode: initialVisibilityMode,
              startDate: Value(input.startDate),
              targetEndDate: Value(input.targetEndDate),
            ),
          );
      await _outbox.enqueue(
        type: SyncOp.projectCreate,
        targetId: id,
        payload: input.toPayload(),
        occurredAt: cuando,
      );
    });

    return id;
  }

  /// Corrige una obra. Se manda la ficha entera y no un diff: última escritura
  /// gana, así que dos correcciones desde dos teléfonos no se mezclan campo por
  /// campo.
  ///
  /// **El estado no se toca acá** — va por [changeStatus], porque es lo único de
  /// `project` que no es última escritura gana.
  Future<void> update(
    String id,
    ProjectInput input, {
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();
    final payload = input.toPayload()
      ..remove('status')
      // `customer_id` y `site_id` se fijan al crear (ficha de `proyecto`), y
      // `UpdateProjectDto` no los declara: mandarlos los descartaba `whitelist`
      // sin decir nada. Se quitan acá para que el payload sea lo que de verdad se
      // va a aplicar.
      ..remove('customerId')
      ..remove('siteId');

    await _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          name: Value(input.name),
          description: Value(input.description),
          serviceType: Value(input.serviceType),
          startDate: Value(input.startDate),
          targetEndDate: Value(input.targetEndDate),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.projectUpdate,
        targetId: id,
        payload: payload,
        occurredAt: cuando,
      );
    });
  }

  /// Cambia el estado de una obra.
  ///
  /// Va en su propia operación y no junto a una corrección de campos porque el
  /// servidor puede **descartar el estado y aplicar el resto**: una transición
  /// retrocedente que llega tarde se ignora. Mezclarlos dejaría al dispositivo sin
  /// saber qué parte se aplicó.
  ///
  /// Quien llama ofrece solo transiciones válidas —`nextStatusesFor`— y el
  /// servidor las valida igual.
  Future<void> changeStatus(
    String id,
    ProjectStatus nuevo, {
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          status: Value(nuevo.json!),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.projectUpdate,
        targetId: id,
        payload: {'status': nuevo.json},
        occurredAt: cuando,
      );
    });
  }

  /// Qué ve el cliente de esta obra: solo las etapas, o las notas y las fotos.
  ///
  /// Es lo único que hace que marcar una nota para el cliente signifique algo:
  /// en `STAGES` el portal devuelve la lista vacía por aprobada que esté.
  /// Viaja por `project.update`, que ya existe.
  Future<void> cambiarModoDeCliente(
    String id,
    String modo, {
    DateTime? occurredAt,
  }) async {
    final cuando = occurredAt ?? DateTime.now();

    await _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          updatedAt: Value(cuando),
          syncStatus: const Value(SyncStatus.pending),
          clientVisibilityMode: Value(modo),
        ),
      );
      await _outbox.enqueue(
        type: SyncOp.projectUpdate,
        targetId: id,
        payload: {'clientVisibilityMode': modo},
        occurredAt: cuando,
      );
    });
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(outboxProvider),
    ref.watch(uuidProvider),
  );
});

/// La cartera, con el texto del buscador como parámetro.
final inProgressProjectsProvider =
    StreamProvider.family<List<ProjectSummary>, String>((ref, query) {
      return ref.watch(projectRepositoryProvider).watchInProgress(query: query);
    });

final projectByIdProvider = StreamProvider.family<ProjectSummary?, String>((
  ref,
  id,
) {
  return ref.watch(projectRepositoryProvider).watchOne(id);
});

final allProjectsProvider =
    StreamProvider.family<List<ProjectSummary>, ProjectStatus?>((ref, status) {
      return ref.watch(projectRepositoryProvider).watchAll(status: status);
    });

/// La obra completa. La usan la tab de Detalle y el formulario de edición.
final projectDetailProvider = StreamProvider.family<ProjectDetail?, String>((
  ref,
  id,
) {
  return ref.watch(projectRepositoryProvider).watchDetail(id);
});

/// Las obras de un cliente. Las usa su ficha.
final projectsByCustomerProvider =
    StreamProvider.family<List<ProjectSummary>, String>((ref, customerId) {
      return ref.watch(projectRepositoryProvider).watchByCustomer(customerId);
    });
