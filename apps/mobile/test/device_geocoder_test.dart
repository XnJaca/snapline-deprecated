import 'package:flutter_test/flutter_test.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:snapline/api/models/address_dto.dart';
import 'package:snapline/core/i18n/state_codes.dart';
import 'package:snapline/core/location/device_geocoder.dart';
import 'package:snapline/features/customers/address_fields.dart';

/// SPEC-0013: del punto a la dirección. Se prueba lo que se puede sin canal de
/// plataforma: cómo se arma la dirección con lo que devuelve el teléfono, cómo
/// se rellenan los campos del formulario, y cómo se compara contra una
/// dirección ya guardada.
void main() {
  group('la dirección que devuelve el teléfono', () {
    test('Android: nombre del estado entero, y sale como código', () {
      final direccion = GeocodedAddress.fromParts(
        street: '9800 Georgia Ave',
        locality: 'Silver Spring',
        administrativeArea: 'Maryland',
        postalCode: '20902',
        isoCountryCode: 'US',
      );

      expect(direccion.line1, '9800 Georgia Ave');
      expect(direccion.city, 'Silver Spring');
      expect(direccion.state, 'MD');
      expect(direccion.postalCode, '20902');
      expect(direccion.country, IsoCode.US);
    });

    test('iOS: el código ya viene, y se respeta', () {
      final direccion = GeocodedAddress.fromParts(
        subThoroughfare: '9800',
        thoroughfare: 'Georgia Ave',
        locality: 'Silver Spring',
        administrativeArea: 'MD',
        postalCode: '20902',
        isoCountryCode: 'US',
      );

      expect(direccion.line1, '9800 Georgia Ave');
      expect(direccion.state, 'MD');
    });

    test('fuera de Estados Unidos y Canadá la provincia va con su nombre', () {
      final direccion = GeocodedAddress.fromParts(
        street: 'Calle 5',
        locality: 'Alajuela',
        administrativeArea: 'Alajuela',
        isoCountryCode: 'CR',
      );

      expect(direccion.state, 'Alajuela');
      expect(direccion.country, IsoCode.CR);
    });

    test('un país que la app no ofrece no llega al selector', () {
      final direccion = GeocodedAddress.fromParts(
        street: 'Rue de Rivoli',
        locality: 'Paris',
        isoCountryCode: 'FR',
      );

      expect(direccion.country, isNull);
      expect(direccion.line1, 'Rue de Rivoli');
    });

    test('lo vacío no cuenta como dato', () {
      final direccion = GeocodedAddress.fromParts(
        street: '   ',
        locality: '',
        administrativeArea: null,
      );

      expect(direccion.isEmpty, isTrue);
    });
  });

  group('el código del estado', () {
    test('traduce el nombre en Estados Unidos, sin importar mayúsculas', () {
      expect(StateCodes.toCode(IsoCode.US, 'maryland'), 'MD');
      expect(StateCodes.toCode(IsoCode.US, 'New York'), 'NY');
      expect(StateCodes.toCode(IsoCode.CA, 'Québec'), 'QC');
    });

    test('un nombre que no reconoce lo deja como vino', () {
      expect(StateCodes.toCode(IsoCode.US, 'Nowhere'), 'Nowhere');
    });

    test('donde el estado es un nombre no toca nada', () {
      expect(StateCodes.toCode(IsoCode.MX, 'Jalisco'), 'Jalisco');
    });
  });

  group('buscar una dirección', () {
    test('el texto vacío no consulta nada', () async {
      final geocoder = _GeocoderDeMentira();

      expect(await geocoder.searchAddress('   '), isNull);
      expect(geocoder.consultas, isEmpty);
    });

    test('devuelve dónde cae, para mover la cámara', () async {
      final geocoder = _GeocoderDeMentira(
        resultado: (lat: 39.0042, lng: -77.0261),
      );

      final donde = await geocoder.searchAddress('9800 Georgia Ave');

      expect(donde?.lat, 39.0042);
      expect(donde?.lng, -77.0261);
      expect(geocoder.consultas, ['9800 Georgia Ave']);
    });

    test('sin resultado devuelve nulo', () async {
      final geocoder = _GeocoderDeMentira();

      expect(await geocoder.searchAddress('Nowhere'), isNull);
    });
  });

  group('comparar contra una dirección guardada', () {
    // Lo que la captura del 2026-09-22 mostraba: punto en Florida, dirección
    // diciendo San Ramón, Costa Rica.
    AddressFormControllers guardada() => AddressFormControllers(
      initial: const AddressDto(
        line1: 'San Ramon',
        city: 'San Ramón',
        state: 'AL',
        postalCode: '20201',
        country: 'CR',
      ),
    );

    const enFlorida = GeocodedAddress(
      line1: '1802 Pennsylvania Ave',
      city: 'Ocoee',
      state: 'FL',
      postalCode: '34761',
      country: IsoCode.US,
    );

    test('lista cada campo que cambiaría, con lo que había', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      final cambios = campos.diff(enFlorida);

      expect(cambios.map((c) => c.part), [
        AddressPart.line1,
        AddressPart.city,
        AddressPart.state,
        AddressPart.postalCode,
        AddressPart.country,
      ]);
      expect(cambios.first.before, 'San Ramon');
      expect(cambios.first.after, '1802 Pennsylvania Ave');
    });

    test('comparar no toca nada', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      campos.diff(enFlorida);

      expect(campos.line1.text, 'San Ramon');
      expect(campos.country.value, IsoCode.CR);
    });

    test('aplicar reemplaza los campos y el país', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      campos.applyChanges(campos.diff(enFlorida), enFlorida);

      expect(campos.line1.text, '1802 Pennsylvania Ave');
      expect(campos.city.text, 'Ocoee');
      expect(campos.state.text, 'FL');
      expect(campos.postalCode.text, '34761');
      expect(campos.country.value, IsoCode.US);
    });

    test('el país se muestra con su nombre, no con el código', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      final cambios = campos.diff(
        enFlorida,
        countryName: (iso) => switch (iso) {
          IsoCode.CR => 'Costa Rica',
          IsoCode.US => 'Estados Unidos',
          _ => iso.name,
        },
      );

      final pais = cambios.last;
      expect(pais.before, 'Costa Rica');
      expect(pais.after, 'Estados Unidos');
    });

    test('lo aplicado arma la dirección que se encola', () {
      // Lo que persiste al aceptar: de acá sale el DTO que `updateSite` manda,
      // sin esperar a «Guardar».
      final campos = guardada();
      addTearDown(campos.dispose);
      campos.applyChanges(campos.diff(enFlorida), enFlorida);

      final dto = campos.toDto();

      expect(dto?.line1, '1802 Pennsylvania Ave');
      expect(dto?.city, 'Ocoee');
      expect(dto?.state, 'FL');
      expect(dto?.postalCode, '34761');
      expect(dto?.country, 'US');
    });

    test('una dirección igual a la guardada no ofrece nada', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      final cambios = campos.diff(
        const GeocodedAddress(
          line1: 'San Ramon',
          city: 'San Ramón',
          state: 'AL',
          postalCode: '20201',
          country: IsoCode.CR,
        ),
      );

      expect(cambios, isEmpty);
    });

    test('un campo que el teléfono no sabe no se ofrece cambiar', () {
      final campos = guardada();
      addTearDown(campos.dispose);

      final cambios = campos.diff(const GeocodedAddress(city: 'Ocoee'));

      expect(cambios.map((c) => c.part), [AddressPart.city]);
    });
  });

  group('rellenar solo lo vacío', () {
    const completa = GeocodedAddress(
      line1: '9800 Georgia Ave',
      city: 'Silver Spring',
      state: 'MD',
      postalCode: '20902',
      country: IsoCode.US,
    );

    test('con el formulario vacío llena los cuatro campos', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      final rellenados = campos.fillMissing(completa);

      expect(rellenados, hasLength(4));
      expect(campos.line1.text, '9800 Georgia Ave');
      expect(campos.city.text, 'Silver Spring');
      expect(campos.state.text, 'MD');
      expect(campos.postalCode.text, '20902');
    });

    test('el país nunca se rellena: el selector no tiene vacío', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(
        const GeocodedAddress(line1: 'Calle 5', country: IsoCode.CR),
      );

      expect(campos.country.value, IsoCode.US);
      expect(campos.line1.text, 'Calle 5');
    });

    test('el estado no entra si el teléfono dijo otro país', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      final rellenados = campos.fillMissing(
        const GeocodedAddress(
          line1: 'Calle 5',
          city: 'Alajuela',
          state: 'Alajuela',
          country: IsoCode.CR,
        ),
      );

      // Calle y ciudad sí; «Alajuela» no cabe en el campo de dos letras que
      // exige el selector en Estados Unidos.
      expect(rellenados, [AddressPart.line1, AddressPart.city]);
      expect(campos.state.text, isEmpty);
    });

    test('sin país del teléfono, el estado se rellena igual', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(const GeocodedAddress(state: 'MD'));

      expect(campos.state.text, 'MD');
    });

    test('mover el punto reemplaza lo que el geocodificador había puesto', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(completa);
      expect(campos.line1.text, '9800 Georgia Ave');

      // Se corrige el punto y el teléfono devuelve otra dirección: la anterior
      // era la del punto descartado, así que se reemplaza.
      final segundos = campos.fillMissing(
        const GeocodedAddress(
          line1: '412 Ellsworth Dr',
          city: 'Silver Spring',
          state: 'MD',
          postalCode: '20910',
          country: IsoCode.US,
        ),
      );

      expect(campos.line1.text, '412 Ellsworth Dr');
      expect(campos.postalCode.text, '20910');
      // La ciudad y el estado no cambiaron de valor: no se cuentan como
      // rellenados y la hoja no los lista de nuevo.
      expect(segundos, [AddressPart.line1, AddressPart.postalCode]);
    });

    test('lo corregido a mano sobrevive al segundo punto', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(completa);
      // La persona arregla el número, que había venido del vecino.
      campos.line1.text = '9802 Georgia Ave';

      campos.fillMissing(
        const GeocodedAddress(line1: '412 Ellsworth Dr', city: 'Rockville'),
      );

      expect(campos.line1.text, '9802 Georgia Ave');
      // Lo que sigue siendo del geocodificador sí se reemplaza.
      expect(campos.city.text, 'Rockville');
    });

    test('un campo vaciado a mano se vuelve a rellenar', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(completa);
      // Se borra la ciudad para escribirla de nuevo, y en vez de eso se mueve
      // el punto. En blanco no hay nada que proteger, y el formulario la exige.
      campos.city.text = '';

      final segundos = campos.fillMissing(
        const GeocodedAddress(city: 'Rockville'),
      );

      expect(campos.city.text, 'Rockville');
      expect(segundos, [AddressPart.city]);
    });

    test('el mismo punto dos veces no cuenta como relleno nuevo', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);

      campos.fillMissing(completa);

      expect(campos.fillMissing(completa), isEmpty);
    });

    test('lo que ya estaba escrito no se pisa', () {
      final campos = AddressFormControllers();
      addTearDown(campos.dispose);
      campos.line1.text = '9802 Georgia Ave';
      campos.postalCode.text = '20910';

      final rellenados = campos.fillMissing(completa);

      expect(rellenados, [AddressPart.city, AddressPart.state]);
      expect(campos.line1.text, '9802 Georgia Ave');
      expect(campos.postalCode.text, '20910');
      expect(campos.city.text, 'Silver Spring');
      expect(campos.state.text, 'MD');
    });

    test('sin nada vacío no toca nada y lo dice con cero', () {
      final campos = AddressFormControllers(
        initial: const AddressDto(
          line1: 'Otra',
          city: 'Otra',
          state: 'VA',
          postalCode: '22000',
        ),
      );
      addTearDown(campos.dispose);

      expect(campos.fillMissing(completa), isEmpty);
      expect(campos.state.text, 'VA');
    });

    test(
      'con el selector en el país que dijo el teléfono, el estado entra',
      () {
        final campos = AddressFormControllers();
        addTearDown(campos.dispose);
        campos.country.value = IsoCode.CR;

        campos.fillMissing(
          const GeocodedAddress(state: 'Alajuela', country: IsoCode.CR),
        );

        expect(campos.state.text, 'Alajuela');
      },
    );
  });
}

/// Un geocodificador que responde lo que se le diga, para probar el contrato
/// que usa la pantalla del mapa sin canal de plataforma.
class _GeocoderDeMentira implements DeviceGeocoder {
  _GeocoderDeMentira({this.resultado});

  final ({double lat, double lng})? resultado;
  final List<String> consultas = [];

  @override
  Future<GeocodedAddress?> fromCoordinates(double lat, double lng) async =>
      null;

  @override
  Future<({double lat, double lng})?> searchAddress(String address) async {
    if (address.trim().isEmpty) return null;
    consultas.add(address.trim());
    return resultado;
  }
}
