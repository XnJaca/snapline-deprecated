import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapline/api/models/auth_user_dto_locale.dart';
import 'package:snapline/api/models/project_status.dart';
import 'package:snapline/core/navigation/app_destination.dart';
import 'package:snapline/data/local/app_database.dart';
import 'package:snapline/data/sync/outbox.dart';
import 'package:snapline/features/projects/project_details_tab.dart';
import 'package:snapline/core/widgets/help_sheet.dart';
import 'package:snapline/core/widgets/status_chip.dart';
import 'package:snapline/features/projects/project_form_screen.dart';
import 'package:snapline/features/projects/project_transitions.dart';

import 'package:uuid/uuid.dart';

import 'support/fakes.dart';

/// SPEC-0005: el alta y la corrección de una obra.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = testDatabase();
    await seedCustomer(
      db,
      id: 'c1',
      displayName: 'Ana Martínez',
      siteLine1: '412 Ellsworth Dr',
    );
    await seedCustomer(db, id: 'c2', displayName: 'Bob Smith');
  });

  tearDown(() => db.close());

  Widget app({AuthUserDtoLocale locale = AuthUserDtoLocale.es}) => testApp(
    db: db,
    session: buildSession(locale: locale),
    lastDestination: AppDestination.projects,
  );

  Future<void> abrirAlta(WidgetTester tester) async {
    await pumpApp(tester, app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva obra').first);
    await tester.pumpAndSettle();
  }

  group('el alta', () {
    testWithApp('la acción primaria de la cartera abre el formulario', (
      tester,
    ) async {
      await abrirAlta(tester);

      expect(find.byType(ProjectFormScreen), findsOne);
      expect(find.text('Nombre de la obra (obligatorio)'), findsOne);
    });

    testWithApp('no guarda sin cliente ni propiedad', (tester) async {
      await abrirAlta(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la obra (obligatorio)'),
        'Sin cliente',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Los selectores no son campos de texto, así que su falta no la caza el
      // `Form`: se muestra igual y no se guarda nada.
      expect(find.text('Falta elegir el cliente'), findsOne);
      expect(find.byType(ProjectFormScreen), findsOne);
      expect(await db.select(db.projects).get(), isEmpty);
    });

    testWithApp('la propiedad espera a que haya cliente', (tester) async {
      await abrirAlta(tester);

      // El `site_id` tiene que pertenecer al `customer_id`, así que sin cliente
      // no hay de dónde elegir — y decirlo es más útil que un campo muerto.
      expect(find.text('Elija primero el cliente'), findsOne);
    });
  });

  group('el selector de propiedad', () {
    Future<void> elegirCliente(WidgetTester tester, String nombre) async {
      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(nombre));
      await tester.pumpAndSettle();
    }

    testWithApp('ofrece solo las propiedades del cliente elegido', (
      tester,
    ) async {
      await abrirAlta(tester);
      await elegirCliente(tester, 'Ana Martínez');

      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();

      // La única del cliente elegido, y la del otro cliente no aparece.
      expect(find.text('412 Ellsworth Dr, Silver Spring, MD'), findsWidgets);
      expect(
        find.text('Elija una propiedad'),
        findsOne,
      ); // el título de la hoja
    });

    testWithApp('un cliente sin propiedades lo dice', (tester) async {
      await abrirAlta(tester);
      await elegirCliente(tester, 'Bob Smith');

      expect(
        find.text('Este cliente todavía no tiene propiedades. Agregue una.'),
        findsOne,
      );
    });

    testWithApp('cambiar de cliente vacía la propiedad', (tester) async {
      await abrirAlta(tester);
      await elegirCliente(tester, 'Ana Martínez');

      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('412 Ellsworth Dr, Silver Spring, MD'));
      await tester.pumpAndSettle();
      expect(find.text('412 Ellsworth Dr, Silver Spring, MD'), findsOne);

      // Dejarla puesta crearía la obra en la casa de otra persona.
      await elegirCliente(tester, 'Bob Smith');
      expect(find.text('412 Ellsworth Dr, Silver Spring, MD'), findsNothing);
    });
  });

  group('crear sin salir del alta', () {
    testWithApp('el cliente nuevo se crea y queda elegido', (tester) async {
      await abrirAlta(tester);

      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      // El "＋ nuevo" abre el formulario de SPEC-0006, no una copia.
      await tester.tap(find.text('Nuevo cliente').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre (obligatorio)').first,
        'Cliente en la obra',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await tester.pumpAndSettle();

      // Vuelve al alta con el cliente ya puesto: sin pasar por otra pantalla.
      expect(find.byType(ProjectFormScreen), findsOne);
      expect(find.text('Cliente en la obra'), findsOne);
    });

    testWithApp('la propiedad nueva se crea y queda elegida', (tester) async {
      await abrirAlta(tester);
      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob Smith'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva propiedad').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calle y número (obligatorio)'),
        '9800 Georgia Ave',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ciudad (obligatorio)'),
        'Silver Spring',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estado o provincia (obligatorio)'),
        // La propiedad es de Maryland y el país por defecto es Estados Unidos:
        // ahí el estado sí es un código de dos letras. Que fuera de ahí sea el
        // nombre entero lo cubre `address_state_test.dart`.
        'MD',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código postal (obligatorio)'),
        '20902',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await tester.pumpAndSettle();

      expect(find.byType(ProjectFormScreen), findsOne);
      expect(find.textContaining('9800 Georgia Ave'), findsWidgets);
      expect(find.textContaining('MD'), findsWidgets);
    });

    testWithApp('el trío completo deja la obra guardada y pendiente', (
      tester,
    ) async {
      await abrirAlta(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la obra (obligatorio)'),
        'Obra del trío',
      );
      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Martínez'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('412 Ellsworth Dr, Silver Spring, MD'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // El formulario se reemplaza por la obra: el back vuelve a la cartera.
      expect(find.byType(ProjectFormScreen), findsNothing);
      final obras = await db.select(db.projects).get();
      expect(obras, hasLength(1));
      expect(obras.first.name, 'Obra del trío');
      expect(obras.first.clientVisibilityMode, 'STAGES');
    });
  });

  // El criterio estrella del spec: los tres, en una sola pasada, sin salir.
  group('cliente, propiedad y obra sin salir del alta', () {
    testWithApp('los tres se crean en el mismo formulario', (tester) async {
      await abrirAlta(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la obra (obligatorio)'),
        'Obra de punta a punta',
      );

      // 1) El cliente, en línea.
      await tester.tap(find.text('Cliente (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo cliente').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre (obligatorio)').first,
        'Cliente al lado',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await tester.pumpAndSettle();

      // 2) Su propiedad, también en línea y sin volver a elegir cliente.
      await tester.tap(find.text('Propiedad (obligatorio)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva propiedad').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calle y número (obligatorio)'),
        '100 Main St',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ciudad (obligatorio)'),
        'Baltimore',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estado o provincia (obligatorio)'),
        'MD',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código postal (obligatorio)'),
        '21201',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await tester.pumpAndSettle();

      // 3) Y la obra.
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      final cliente = await db.select(db.customers).get();
      final obra = await db.select(db.projects).get();
      final sitio = await db.select(db.sites).get();

      final nuevo = cliente
          .where((c) => c.displayName == 'Cliente al lado')
          .single;
      final suSitio = sitio.where((s) => s.customerId == nuevo.id).single;
      expect(obra, hasLength(1));
      expect(obra.first.customerId, nuevo.id);
      expect(obra.first.siteId, suSitio.id);

      // Las tres en la bandeja, y en el orden en que se crearon: la obra no puede
      // aplicarse antes que el cliente del que cuelga.
      final pendientes = await Outbox(db, const Uuid()).pending();
      final tipos = pendientes.map((o) => o.type).toList();
      expect(
        tipos.indexOf('customer.create'),
        lessThan(tipos.indexOf('site.create')),
      );
      expect(
        tipos.indexOf('site.create'),
        lessThan(tipos.indexOf('project.create')),
      );
    });
  });

  group('el selector de estado', () {
    testWithApp('dibuja solo las transiciones válidas', (tester) async {
      await seedProject(
        db,
        id: 'p1',
        name: 'Obra agendada',
        customerName: 'Ana Martínez',
        status: ProjectStatus.scheduled,
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();

      // La obra agendada no está en la cartera: se llega por "ver todos".
      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obra agendada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();

      // Desde agendada: en proceso, en pausa y cancelado. Nada más.
      expect(find.widgetWithText(OutlinedButton, 'En proceso'), findsOne);
      expect(find.widgetWithText(OutlinedButton, 'En pausa'), findsOne);
      expect(find.widgetWithText(OutlinedButton, 'Cancelado'), findsOne);
      // Un botón que el servidor va a rechazar no debería estar dibujado.
      expect(find.widgetWithText(OutlinedButton, 'Terminado'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Prospecto'), findsNothing);
    });

    testWithApp('una obra terminada no ofrece ninguna', (tester) async {
      await seedProject(
        db,
        id: 'p2',
        name: 'Obra terminada',
        customerName: 'Ana Martínez',
        status: ProjectStatus.completed,
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obra terminada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();

      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        find.text(
          'Una obra terminada o cancelada no vuelve a cambiar de estado',
        ),
        findsOne,
      );
    });
  });

  group('la edición', () {
    Future<void> abrirEdicion(WidgetTester tester) async {
      await seedProject(
        db,
        id: 'p9',
        name: 'Obra a corregir',
        customerName: 'no se usa',
      );
      await db.customStatement(
        'UPDATE projects SET customer_id = ?, site_id = ? WHERE id = ?',
        ['c1', 's-c1', 'p9'],
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obra a corregir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
    }

    testWithApp('el cliente y la propiedad no se pueden cambiar', (
      tester,
    ) async {
      await abrirEdicion(tester);

      expect(find.byType(ProjectFormScreen), findsOne);
      // Se fijan al crear: ofrecerlos y descartarlos en silencio era peor que no
      // ofrecerlos. Se muestran como dato, con el motivo.
      expect(find.text('Cliente (obligatorio)'), findsNothing);
      expect(find.text('Propiedad (obligatorio)'), findsNothing);
      expect(find.text('Ana Martínez'), findsOne);
      expect(
        find.text(
          'El cliente y la propiedad se fijan al crear la obra. Para cambiarlos, '
          'cancele esta obra y cree una nueva.',
        ),
        findsOne,
      );
    });

    testWithApp('el estado tampoco se edita desde el formulario', (
      tester,
    ) async {
      await abrirEdicion(tester);

      // Va por el detalle, con solo las transiciones válidas: el servidor puede
      // descartarlo y mezclarlo con una corrección dejaría al dispositivo sin
      // saber qué parte se aplicó.
      expect(find.text('Estado (obligatorio)'), findsNothing);
    });

    testWithApp('corregir el nombre sí se aplica', (tester) async {
      await abrirEdicion(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la obra (obligatorio)'),
        'Nombre corregido',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      final obra = await (db.select(
        db.projects,
      )..where((p) => p.id.equals('p9'))).getSingle();
      expect(obra.name, 'Nombre corregido');
      expect(obra.customerId, 'c1');
    });
  });

  group('terminar y cancelar piden confirmación', () {
    Future<void> abrirDetalle(WidgetTester tester, ProjectStatus estado) async {
      await seedProject(
        db,
        id: 'pc',
        name: 'Obra a cerrar',
        customerName: 'Ana Martínez',
        status: estado,
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      if (estado != ProjectStatus.inProgress) {
        await tester.tap(find.text('Ver todos'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Obra a cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();
    }

    Future<String> estadoEnBase() async {
      final fila = await (db.select(
        db.projects,
      )..where((p) => p.id.equals('pc'))).getSingle();
      return fila.status;
    }

    testWithApp('cancelar la confirmación no cambia nada', (tester) async {
      await abrirDetalle(tester, ProjectStatus.inProgress);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Terminado'));
      await tester.pumpAndSettle();

      // Un toque por error en algo irreversible tiene que poder deshacerse antes
      // de que pase.
      expect(find.text('¿Marcar la obra como Terminado?'), findsOne);
      // La salida es un botón de ancho completo y no un texto suelto: en la
      // hoja las dos opciones se ven como opciones.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar').last);
      await tester.pumpAndSettle();

      expect(await estadoEnBase(), 'IN_PROGRESS');
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    testWithApp('confirmar sí lo aplica', (tester) async {
      await abrirDetalle(tester, ProjectStatus.inProgress);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Terminado'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sí, marcar'));
      await tester.pumpAndSettle();

      expect(await estadoEnBase(), 'COMPLETED');
    });

    testWithApp('cancelar la obra también confirma, y dice que no borra nada', (
      tester,
    ) async {
      await abrirDetalle(tester, ProjectStatus.inProgress);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelado'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No se borra nada'), findsOne);
    });

    testWithApp('solo cancelar avisa en rojo', (tester) async {
      await abrirDetalle(tester, ProjectStatus.inProgress);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Terminado'));
      await tester.pumpAndSettle();
      final terminar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sí, marcar'),
      );
      // Terminar es el cierre bueno del trabajo: no lleva el rojo, que está
      // reservado para lo que se lee como advertencia.
      expect(terminar.style?.backgroundColor, isNull);
    });

    testWithApp('pausar no pregunta: se hace a cada rato', (tester) async {
      await abrirDetalle(tester, ProjectStatus.inProgress);

      await tester.tap(find.widgetWithText(OutlinedButton, 'En pausa'));
      await tester.pumpAndSettle();

      expect(find.text('¿Marcar la obra como En pausa?'), findsNothing);
      expect(await estadoEnBase(), 'ON_HOLD');
    });
  });

  group('la tab en la que abre la obra', () {
    Future<void> abrirObra(WidgetTester tester, ProjectStatus estado) async {
      await seedProject(
        db,
        id: 'pt',
        name: 'Obra por estado',
        customerName: 'Ana Martínez',
        status: estado,
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      if (estado != ProjectStatus.inProgress) {
        await tester.tap(find.text('Ver todos'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Obra por estado'));
      await tester.pumpAndSettle();
    }

    testWithApp('en proceso abre en Avance', (tester) async {
      await abrirObra(tester, ProjectStatus.inProgress);

      // El caso de todos los días: la obra que se está trabajando.
      expect(find.byType(ProjectDetailsTab), findsNothing);
    });

    testWithApp('terminada abre directo en Detalle', (tester) async {
      await abrirObra(tester, ProjectStatus.completed);

      // El timeline de algo que no se mueve no es lo que se viene a ver.
      expect(find.byType(ProjectDetailsTab), findsOne);
      expect(find.text('El trabajo'), findsOne);
    });

    testWithApp('agendada también', (tester) async {
      await abrirObra(tester, ProjectStatus.scheduled);

      expect(find.byType(ProjectDetailsTab), findsOne);
    });
  });

  group('la ficha del detalle', () {
    testWithApp('las etiquetas no se cortan ni se apilan en tres líneas', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await seedProject(
        db,
        id: 'pf',
        name: 'Obra de la ficha',
        customerName: 'Ana Martínez',
      );
      await pumpApp(tester, app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obra de la ficha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detalle'));
      await tester.pumpAndSettle();

      // Con la etiqueta en una columna de ancho fijo, "Nombre de la obra" se
      // partía en tres líneas y "Propiedad" se cortaba en "Propieda / d".
      // Apilada, cada texto entra en una sola línea.
      //
      // El `ListView` no construye lo que está fuera de la vista, así que primero
      // se baja hasta la sección del cliente.
      // Se mide una por una, bajando hasta cada etiqueta justo antes: las tres
      // ya no entran juntas en el viewport, y el `ListView` no construye lo que
      // queda afuera. Van en el orden en que aparecen, así que alcanza con
      // bajar.
      final scrollable = find
          .descendant(
            of: find.byType(ProjectDetailsTab),
            matching: find.byType(Scrollable),
          )
          .first;

      Future<double> alturaDe(String etiqueta) async {
        await tester.scrollUntilVisible(
          find.text(etiqueta).first,
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.text(etiqueta).first).height;
      }

      // "Cliente" es una palabra corta que entra siempre: sirve de referencia de
      // cuánto mide una línea, sin depender de la métrica interna del render.
      final nombre = await alturaDe('Nombre de la obra');
      final unaLinea = await alturaDe('Cliente');
      final propiedad = await alturaDe('Propiedad');

      expect(
        nombre,
        unaLinea,
        reason: '"Nombre de la obra" tendría que entrar en una línea',
      );
      expect(
        propiedad,
        unaLinea,
        reason: '"Propiedad" tendría que entrar en una línea',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('los dos temas', () {
    for (final (nombre, oscuro) in [('claro', false), ('oscuro', true)]) {
      testWidgets('$nombre: el alta se dibuja sin desbordes', (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.platformBrightnessTestValue = oscuro
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        try {
          await abrirAlta(tester);
          expect(find.byType(ProjectFormScreen), findsOne);
          expect(tester.takeException(), isNull);
        } finally {
          await disposeApp(tester);
        }
      });
    }

    testWithApp('la cartera tiene un solo naranja sólido', (tester) async {
      await pumpApp(tester, app());
      await tester.pumpAndSettle();

      // "Ver todos" se queda en texto: si dos cosas son naranjas, ninguna es la
      // acción.
      expect(find.byType(FloatingActionButton), findsOne);
      expect(find.widgetWithText(FloatingActionButton, 'Nueva obra'), findsOne);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('el estado inicial', () {
    testWithApp('nace en proceso, para que aparezca en la cartera', (
      tester,
    ) async {
      await abrirAlta(tester);

      // Con `LEAD` la obra recién creada no aparecería en la cartera —que muestra
      // solo lo que está en proceso— y se leería como que no se guardó.
      expect(find.text('En proceso'), findsWidgets);
    });

    testWithApp('lo que ve el cliente se avisa, no se pregunta', (
      tester,
    ) async {
      // Es un aviso y no un campo: la obra nace en etapas y el modo se cambia
      // después, en la ficha. Suelto entre campos se leía como un selector al
      // que le faltan las opciones, así que va con su fondo y su ayuda.
      await abrirAlta(tester);
      await tester.scrollUntilVisible(
        find.text('El cliente verá esta obra por etapas'),
        200,
        // El formulario anida scrollables: sin `.first` el finder devuelve
        // varios y `scrollUntilVisible` revienta pidiendo uno solo.
        scrollable: find
            .descendant(
              of: find.byType(ProjectFormScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );

      final aviso = find.ancestor(
        of: find.text('El cliente verá esta obra por etapas'),
        matching: find.byType(StatusChip),
      );
      expect(aviso, findsOne);
      expect(
        find.descendant(of: aviso, matching: find.byType(HelpButton)),
        findsOne,
      );
    });

    testWithApp('no se puede crear una obra ya cancelada', (tester) async {
      await abrirAlta(tester);

      await tester.tap(find.text('Estado (obligatorio)'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelado'), findsNothing);
      expect(find.text('Prospecto').hitTestable(), findsWidgets);
    });
  });

  group('la escalera de estados', () {
    test('desde prospecto no se salta a terminada', () {
      // Criterio del spec, verificado sobre la tabla que el selector consume.
      expect(
        nextStatusesFor(ProjectStatus.lead),
        isNot(contains(ProjectStatus.completed)),
      );
      expect(nextStatusesFor(ProjectStatus.lead), [
        ProjectStatus.estimated,
        ProjectStatus.cancelled,
      ]);
    });

    test('una obra terminada no ofrece cambios', () {
      expect(nextStatusesFor(ProjectStatus.completed), isEmpty);
    });
  });

  group('nada quemado', () {
    testWithApp('el formulario de un usuario en inglés sale en inglés', (
      tester,
    ) async {
      await pumpApp(tester, app(locale: AuthUserDtoLocale.en));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New project').first);
      await tester.pumpAndSettle();

      expect(find.text('Project name (required)'), findsOne);
      expect(find.text('Customer (required)'), findsOne);
      expect(find.text('Choose the customer first'), findsOne);
      expect(find.text('Nombre de la obra (obligatorio)'), findsNothing);
    });
  });
}
