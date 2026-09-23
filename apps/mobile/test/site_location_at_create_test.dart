import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapline/api/models/address_dto.dart';
import 'package:snapline/core/navigation/app_destination.dart';
import 'package:snapline/data/local/app_database.dart';
import 'package:snapline/data/repositories/customer_repository.dart';
import 'package:snapline/data/sync/outbox.dart';
import 'package:uuid/uuid.dart';

import 'support/fakes.dart';

/// SPEC-0013: el punto se fija al crear la propiedad, y una obra cuya propiedad
/// no tiene punto lo dice —en el alta y en Detalle— y ofrece fijarlo ahí mismo.
void main() {
  late AppDatabase db;
  late Outbox outbox;
  late CustomerRepository repo;

  const direccion = AddressDto(
    line1: '412 Ellsworth Dr',
    city: 'Silver Spring',
    state: 'MD',
    postalCode: '20910',
  );

  setUp(() {
    db = testDatabase();
    outbox = Outbox(db, const Uuid());
    repo = CustomerRepository(db, outbox, const Uuid());
  });

  tearDown(() => db.close());

  group('el repositorio: el punto viaja en el alta', () {
    Future<String> unCliente() =>
        repo.create(const CustomerInput(displayName: 'Martínez'));

    Future<SiteSummary> buscar(String clienteId, String siteId) async {
      final sitios = await repo.watchSites(clienteId).first;
      return sitios.firstWhere((s) => s.id == siteId);
    }

    test('la propiedad nace con su punto y su radio', () async {
      final clienteId = await unCliente();

      final siteId = await repo.addSite(
        clienteId,
        direccion,
        lat: 39.0042,
        lng: -77.0261,
        geofenceRadiusM: 120,
      );

      final sitio = await buscar(clienteId, siteId);
      expect(sitio.hasLocation, isTrue);
      expect(sitio.lat, 39.0042);
      expect(sitio.lng, -77.0261);
      expect(sitio.geofenceRadiusM, 120);
    });

    test('es un solo site.create con el punto adentro', () async {
      final clienteId = await unCliente();
      final siteId = await repo.addSite(
        clienteId,
        direccion,
        lat: 39.0042,
        lng: -77.0261,
        geofenceRadiusM: 120,
      );

      final ops = await outbox.pending();
      final deLaPropiedad = ops.where((op) => op.targetId == siteId).toList();
      expect(deLaPropiedad, hasLength(1));
      expect(deLaPropiedad.single.type, SyncOp.siteCreate);

      final payload =
          jsonDecode(deLaPropiedad.single.payload) as Map<String, Object?>;
      expect(payload['lat'], 39.0042);
      expect(payload['lng'], -77.0261);
      expect(payload['geofenceRadiusM'], 120);
      // Y la dirección sigue viajando: es la misma operación de siempre, con
      // más campos, no otra.
      expect(payload['address'], isNotNull);
      expect(payload['customerId'], clienteId);
    });

    test('sin radio, la clave no viaja: el servidor rechaza un nulo', () async {
      final clienteId = await unCliente();
      final siteId = await repo.addSite(
        clienteId,
        direccion,
        lat: 39.0042,
        lng: -77.0261,
      );

      final op = (await outbox.pending()).firstWhere(
        (o) => o.targetId == siteId,
      );
      final payload = jsonDecode(op.payload) as Map<String, Object?>;
      expect(payload.containsKey('geofenceRadiusM'), isFalse);
      expect(payload['lat'], 39.0042);
    });

    test('sin punto, el alta es la de siempre', () async {
      final clienteId = await unCliente();
      final siteId = await repo.addSite(clienteId, direccion);

      final sitio = await buscar(clienteId, siteId);
      expect(sitio.hasLocation, isFalse);

      final op = (await outbox.pending()).firstWhere(
        (o) => o.targetId == siteId,
      );
      final payload = jsonDecode(op.payload) as Map<String, Object?>;
      expect(payload.containsKey('lat'), isFalse);
      expect(payload.containsKey('lng'), isFalse);
    });

    test('media coordenada no cuenta: ni se guarda ni viaja', () async {
      final clienteId = await unCliente();
      final siteId = await repo.addSite(clienteId, direccion, lat: 39.0042);

      final sitio = await buscar(clienteId, siteId);
      expect(sitio.lat, isNull);
      expect(sitio.hasLocation, isFalse);

      final op = (await outbox.pending()).firstWhere(
        (o) => o.targetId == siteId,
      );
      final payload = jsonDecode(op.payload) as Map<String, Object?>;
      expect(payload.containsKey('lat'), isFalse);
    });
  });

  group('actualizar la dirección de una propiedad guardada', () {
    test('encola site.update con la dirección, no solo con el punto', () async {
      // El GRAVE que encontró la revisión: aceptar la comparación tiene que
      // escribir en el acto. El punto ya se guardó solo al volver del mapa, y
      // una dirección esperando un toque más deja el mismo desacuerdo que esto
      // viene a resolver.
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Jonathan Cruz',
        siteLine1: 'San Ramon',
      );

      await repo.updateSite(
        's-c1',
        const AddressDto(
          line1: '1802 Pennsylvania Ave',
          city: 'Ocoee',
          state: 'FL',
          postalCode: '34761',
        ),
      );

      final op = (await outbox.pending()).single;
      expect(op.type, SyncOp.siteUpdate);
      expect(op.targetId, 's-c1');
      final payload = jsonDecode(op.payload) as Map<String, Object?>;
      final direccionNueva = payload['address'] as Map<String, Object?>;
      expect(direccionNueva['line1'], '1802 Pennsylvania Ave');
      expect(direccionNueva['state'], 'FL');

      final sitios = await repo.watchSites('c1').first;
      expect(sitios.single.oneLine, '1802 Pennsylvania Ave, Ocoee, FL');
    });
  });

  group('la hoja de propiedad', () {
    Widget app() => testApp(
      db: db,
      session: buildSession(),
      lastDestination: AppDestination.customers,
    );

    Future<void> abrirCliente(WidgetTester tester, String nombre) async {
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text(nombre));
      await tester.pumpAndSettle();
    }

    testWithApp('el alta ofrece fijar el punto antes de guardar nada', (
      tester,
    ) async {
      await seedCustomer(db, id: 'c2', displayName: 'Bob Smith');
      await abrirCliente(tester, 'Bob Smith');

      await tester.tap(find.text('Agregar propiedad'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva propiedad'), findsOne);
      expect(find.text('Ubicación en el mapa'), findsOne);
      expect(find.text('Fijar en el mapa'), findsOne);
      // Nada se creó por abrir la hoja.
      expect(await db.select(db.sites).get(), isEmpty);
      expect(await outbox.pending(), isEmpty);
    });

    testWithApp('en el alta el mapa va arriba de la dirección', (tester) async {
      await seedCustomer(db, id: 'c2', displayName: 'Bob Smith');
      await abrirCliente(tester, 'Bob Smith');
      await tester.tap(find.text('Agregar propiedad'));
      await tester.pumpAndSettle();

      final mapa = tester.getTopLeft(find.text('Ubicación en el mapa'));
      final calle = tester.getTopLeft(
        find.text('Calle y número (obligatorio)'),
      );
      expect(mapa.dy, lessThan(calle.dy));
    });

    testWithApp('en corrección la dirección sigue arriba', (tester) async {
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Ana Martínez',
        siteLine1: '412 Ellsworth Dr',
      );
      await abrirCliente(tester, 'Ana Martínez');
      await tester.tap(find.text('412 Ellsworth Dr, Silver Spring, MD'));
      await tester.pumpAndSettle();

      final mapa = tester.getTopLeft(find.text('Ubicación en el mapa'));
      final calle = tester.getTopLeft(
        find.text('Calle y número (obligatorio)'),
      );
      expect(calle.dy, lessThan(mapa.dy));
    });

    testWithApp(
      'una propiedad existente muestra el punto nuevo sin reabrir la hoja',
      (tester) async {
        await seedCustomer(
          db,
          id: 'c1',
          displayName: 'Ana Martínez',
          siteLine1: '412 Ellsworth Dr',
        );
        await abrirCliente(tester, 'Ana Martínez');

        await tester.tap(find.text('412 Ellsworth Dr, Silver Spring, MD'));
        await tester.pumpAndSettle();
        expect(find.text('Editar propiedad'), findsOne);
        expect(find.text('Fijar en el mapa'), findsOne);

        // Lo que la pantalla del mapa escribe al guardar, sin abrirla: el mapa
        // no se dibuja en tests. Lo que se prueba es que la hoja lo ve llegar.
        await repo.setSiteLocation('s-c1', lat: 39.0042, lng: -77.0261);
        await tester.pumpAndSettle();

        expect(find.text('39.00420, -77.02610'), findsOne);
        expect(find.text('Mover el punto'), findsOne);
        expect(find.text('Fijar en el mapa'), findsNothing);
      },
    );
  });

  group('el alta de cliente', () {
    Widget app() => testApp(
      db: db,
      session: buildSession(),
      lastDestination: AppDestination.customers,
    );

    Future<void> abrirAlta(WidgetTester tester) async {
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();
    }

    Future<void> verElMapa(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Ubicación en el mapa'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWithApp('la primera propiedad también ofrece fijar el punto', (
      tester,
    ) async {
      // El hueco que quedó al implementar SPEC-0013: esta pantalla crea una
      // propiedad y no mostraba el mapa.
      await abrirAlta(tester);
      await verElMapa(tester);

      expect(find.text('Ubicación en el mapa'), findsOne);
      expect(find.text('Fijar en el mapa'), findsOne);
    });

    testWithApp('el mapa vive en la sección de la propiedad', (tester) async {
      await abrirAlta(tester);
      await verElMapa(tester);

      // Y no en la dirección de facturación, que está más arriba y no tiene
      // geocerca que fijar.
      final seccion = tester.getTopLeft(find.text('Propiedad'));
      final mapa = tester.getTopLeft(find.text('Ubicación en el mapa'));
      expect(seccion.dy, lessThan(mapa.dy));
      expect(find.text('Ubicación en el mapa'), findsOne);
    });

    testWithApp('sin punto, el alta guarda como siempre', (tester) async {
      await abrirAlta(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre (obligatorio)').first,
        'Jonathan Cruz',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      final clientes = await db.select(db.customers).get();
      expect(clientes.single.displayName, 'Jonathan Cruz');
      // Sin dirección escrita no hay propiedad: la primera es opcional, y eso
      // no cambia.
      expect(await db.select(db.sites).get(), isEmpty);
    });
  });

  group('el alta de obra', () {
    Widget app() => testApp(
      db: db,
      session: buildSession(),
      lastDestination: AppDestination.projects,
    );

    const aviso =
        'Esta propiedad no tiene ubicación en el mapa. Sin ella no se puede '
        'verificar la asistencia en la obra.';

    Future<void> abrirAltaYElegir(WidgetTester tester, String cliente) async {
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva obra').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cliente));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('412 Ellsworth Dr, Silver Spring, MD').last);
      await tester.pumpAndSettle();
    }

    testWithApp('una propiedad sin punto lo dice y ofrece fijarlo', (
      tester,
    ) async {
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Ana Martínez',
        siteLine1: '412 Ellsworth Dr',
      );
      await abrirAltaYElegir(tester, 'Ana Martínez');

      expect(find.text(aviso), findsOne);
      expect(find.text('Fijar en el mapa'), findsOne);
    });

    testWithApp('con punto no hay aviso', (tester) async {
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Ana Martínez',
        siteLine1: '412 Ellsworth Dr',
        siteLat: 39.0042,
        siteLng: -77.0261,
      );
      await abrirAltaYElegir(tester, 'Ana Martínez');

      expect(find.text(aviso), findsNothing);
      expect(find.text('Fijar en el mapa'), findsNothing);
    });

    testWithApp('fijar el punto y volver hace desaparecer el aviso', (
      tester,
    ) async {
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Ana Martínez',
        siteLine1: '412 Ellsworth Dr',
      );
      await abrirAltaYElegir(tester, 'Ana Martínez');
      expect(find.text(aviso), findsOne);

      await repo.setSiteLocation('s-c1', lat: 39.0042, lng: -77.0261);
      await tester.pumpAndSettle();

      expect(find.text(aviso), findsNothing);
      // Y la obra sigue en el formulario, con la propiedad elegida.
      expect(find.text('412 Ellsworth Dr, Silver Spring, MD'), findsOne);
      final op = (await outbox.pending()).single;
      expect(op.type, SyncOp.siteUpdate);
      expect(op.targetId, 's-c1');
    });

    testWithApp('se puede guardar la obra sin punto', (tester) async {
      await seedCustomer(
        db,
        id: 'c1',
        displayName: 'Ana Martínez',
        siteLine1: '412 Ellsworth Dr',
      );
      await abrirAltaYElegir(tester, 'Ana Martínez');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la obra (obligatorio)'),
        'Techo sin punto',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      final obras = await db.select(db.projects).get();
      expect(obras, hasLength(1));
      expect(obras.single.name, 'Techo sin punto');
    });
  });

  group('la tab Detalle', () {
    const aviso =
        'Esta propiedad no tiene ubicación en el mapa. Sin ella no se puede '
        'verificar la asistencia en la obra.';

    Widget app({List<String>? permissions}) => testApp(
      db: db,
      session: buildSession(permissions: permissions),
      lastDestination: AppDestination.projects,
    );

    Future<void> abrirDetalle(
      WidgetTester tester, {
      List<String>? permissions,
    }) async {
      await pumpApp(tester, app(permissions: permissions));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Techo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();
    }

    testWithApp('sin punto, lo dice y ofrece fijarlo', (tester) async {
      await seedProject(db, id: 'p1', name: 'Techo', customerName: 'Ana');
      await abrirDetalle(tester);

      expect(find.text('Ubicación en el mapa'), findsOne);
      expect(find.text(aviso), findsOne);
      expect(find.text('Fijar en el mapa'), findsOne);
    });

    testWithApp('con punto, muestra las coordenadas', (tester) async {
      await seedProject(
        db,
        id: 'p1',
        name: 'Techo',
        customerName: 'Ana',
        siteLat: 39.0042,
        siteLng: -77.0261,
      );
      await abrirDetalle(tester);

      expect(find.text('39.00420, -77.02610'), findsOne);
      expect(find.text(aviso), findsNothing);
      expect(find.text('Fijar en el mapa'), findsNothing);
    });

    testWithApp('fijar el punto y volver muestra las coordenadas sin salir', (
      tester,
    ) async {
      await seedProject(db, id: 'p1', name: 'Techo', customerName: 'Ana');
      await abrirDetalle(tester);
      expect(find.text(aviso), findsOne);

      await repo.setSiteLocation('s-p1', lat: 39.0042, lng: -77.0261);
      await tester.pumpAndSettle();

      expect(find.text(aviso), findsNothing);
      expect(find.text('39.00420, -77.02610'), findsOne);
      final op = (await outbox.pending()).single;
      expect(op.type, SyncOp.siteUpdate);
      expect(op.targetId, 's-p1');
    });

    testWithApp('sin customers.write se dice que falta, sin acción', (
      tester,
    ) async {
      await seedProject(db, id: 'p1', name: 'Techo', customerName: 'Ana');
      await abrirDetalle(
        tester,
        permissions: permisosOwner
            .where((p) => p != 'customers.write')
            .toList(),
      );

      expect(find.text('Sin ubicación en el mapa'), findsOne);
      expect(find.text('Fijar en el mapa'), findsNothing);
    });
  });
}
