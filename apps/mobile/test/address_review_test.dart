import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapline/core/location/map_type_store.dart';
import 'package:snapline/core/widgets/country_field.dart';
import 'package:snapline/data/local/app_database.dart';
import 'package:snapline/features/customers/address_fields.dart';
import 'package:snapline/features/customers/address_review_sheet.dart';
import 'package:snapline/features/customers/site_location_block.dart';

import 'support/fakes.dart';

/// SPEC-0013, tercer tramo: los campos se bloquean mientras se busca, lo
/// rellenado se revisa en una hoja, y el mapa recuerda si se ve en satélite.
void main() {
  late AppDatabase db;

  setUp(() => db = testDatabase());
  tearDown(() => db.close());

  group('la hoja de revisión', () {
    late AddressFormControllers campos;

    setUp(() {
      campos = AddressFormControllers();
      campos.line1.text = '9800 Georgia Ave';
      campos.city.text = 'Silver Spring';
      campos.state.text = 'MD';
    });
    tearDown(() => campos.dispose());

    Widget abridor({required void Function(bool) onResult}) => Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          final ok = await showAddressReviewSheet(
            context,
            controllers: campos,
            filled: const [AddressPart.line1, AddressPart.city],
          );
          onResult(ok);
        },
        child: const Text('abrir'),
      ),
    );

    testWidgets('lista solo lo que se rellenó, con su valor', (tester) async {
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (_) {}),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Revisar la dirección'), findsOne);
      expect(find.text('Calle y número'), findsOne);
      expect(find.text('9800 Georgia Ave'), findsOne);
      expect(find.text('Ciudad'), findsOne);
      expect(find.text('Silver Spring'), findsOne);
      // El estado también tiene valor, pero no se rellenó: no se lista.
      expect(find.text('Estado o provincia'), findsNothing);
      expect(find.text('MD'), findsNothing);
    });

    testWidgets('«Confirmar» devuelve que está bien', (tester) async {
      bool? resultado;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (ok) => resultado = ok),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(resultado, isTrue);
      expect(find.text('Revisar la dirección'), findsNothing);
    });

    testWidgets('«Corregir» devuelve que hay que corregir', (tester) async {
      bool? resultado;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (ok) => resultado = ok),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corregir'));
      await tester.pumpAndSettle();

      expect(resultado, isFalse);
    });
  });

  group('la hoja de comparación', () {
    const cambios = [
      AddressChange(
        part: AddressPart.line1,
        before: 'San Ramon',
        after: '1802 Pennsylvania Ave',
      ),
      AddressChange(
        part: AddressPart.country,
        before: 'Costa Rica',
        after: 'US',
      ),
    ];

    Widget abridor({required void Function(bool) onResult}) => Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          final ok = await showAddressUpdateSheet(context, changes: cambios);
          onResult(ok);
        },
        child: const Text('abrir'),
      ),
    );

    testWidgets('muestra lo que había y lo que queda', (tester) async {
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (_) {}),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Revisar la dirección'), findsOne);
      expect(
        find.text(
          'El punto se movió. La dirección guardada no coincide con la '
          'ubicación nueva.',
        ),
        findsOne,
      );
      expect(find.text('antes: San Ramon'), findsOne);
      expect(find.text('ahora: 1802 Pennsylvania Ave'), findsOne);
      expect(find.text('antes: Costa Rica'), findsOne);
      expect(find.text('Actualizar la dirección'), findsOne);
      expect(find.text('Dejarla como está'), findsOne);
    });

    testWidgets('«Actualizar la dirección» pide reemplazar', (tester) async {
      bool? resultado;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (ok) => resultado = ok),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar la dirección'));
      await tester.pumpAndSettle();

      expect(resultado, isTrue);
    });

    testWidgets('«Dejarla como está» no reemplaza', (tester) async {
      bool? resultado;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (ok) => resultado = ok),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dejarla como está'));
      await tester.pumpAndSettle();

      expect(resultado, isFalse);
    });

    testWidgets('cerrarla deslizando deja la dirección como estaba', (
      tester,
    ) async {
      bool? resultado;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: abridor(onResult: (ok) => resultado = ok),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      // A diferencia del alta, acá hay algo que perder: sin confirmar, no se
      // reemplaza.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(resultado, isFalse);
    });
  });

  group('los campos bloqueados', () {
    testWidgets('con enabled en false ningún campo acepta texto', (
      tester,
    ) async {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      await tester.pumpWidget(
        testWidget(
          db: db,
          child: SingleChildScrollView(
            child: AddressFields(controllers: campos, enabled: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textos = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );
      expect(textos, hasLength(5));
      expect(textos.every((t) => t.enabled == false), isTrue);

      // El país tampoco: su toque queda apagado.
      final pais = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(CountryField),
          matching: find.byType(InkWell),
        ),
      );
      expect(pais.onTap, isNull);
    });
  });

  group('el bloque de ubicación', () {
    testWidgets('sin acción, el botón del mapa no se puede tocar', (
      tester,
    ) async {
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: const SiteLocationBlock(lat: null, lng: null, onSet: null),
        ),
      );
      await tester.pumpAndSettle();

      // Mientras se busca la dirección del punto anterior, elegir otro dejaría
      // dos búsquedas escribiendo sobre los mismos campos.
      final boton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Fijar en el mapa'),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('con acción, se puede tocar', (tester) async {
      var toques = 0;
      await tester.pumpWidget(
        testWidget(
          db: db,
          child: SiteLocationBlock(lat: null, lng: null, onSet: () => toques++),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fijar en el mapa'));

      expect(toques, 1);
    });
  });

  group('el modo satélite', () {
    test('arranca en mapa y carga lo guardado apenas puede', () async {
      final container = ProviderContainer(
        overrides: [
          mapTypeStoreProvider.overrideWithValue(FakeMapTypeStore(true)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(satelliteMapProvider), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(satelliteMapProvider), isTrue);
    });

    test('alternar cambia en pantalla y se guarda', () async {
      final store = FakeMapTypeStore();
      final container = ProviderContainer(
        overrides: [mapTypeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(satelliteMapProvider.notifier).toggle();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(satelliteMapProvider), isTrue);
      expect(store.satellite, isTrue);
    });

    test('un toque gana sobre la lectura que llega tarde', () async {
      // Guardado en satélite, pero la lectura tarda: si alguien toca el botón
      // antes de que resuelva, su elección no puede quedar pisada.
      final store = FakeMapTypeStore(true, const Duration(milliseconds: 40));
      final container = ProviderContainer(
        overrides: [mapTypeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(container.read(satelliteMapProvider), isFalse);
      container.read(satelliteMapProvider.notifier).toggle();
      expect(container.read(satelliteMapProvider), isTrue);
      container.read(satelliteMapProvider.notifier).toggle();
      expect(container.read(satelliteMapProvider), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(container.read(satelliteMapProvider), isFalse);
      expect(store.satellite, isFalse);
    });

    test('sin nada guardado se queda en mapa', () async {
      final container = ProviderContainer(
        overrides: [mapTypeStoreProvider.overrideWithValue(FakeMapTypeStore())],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(satelliteMapProvider), isFalse);
    });
  });
}
