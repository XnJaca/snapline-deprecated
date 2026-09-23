import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:phone_form_field/phone_form_field.dart';

import '../i18n/state_codes.dart';
import '../i18n/supported_countries.dart';

/// Una dirección derivada de un punto, ya en la forma del formulario.
///
/// Todo es opcional: el geocodificador devuelve lo que sabe. `state` viene como
/// código de dos letras donde el país lo exige, y `country` solo si la app lo
/// ofrece; si no, nulo y el selector no se toca.
class GeocodedAddress {
  const GeocodedAddress({
    this.line1,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? line1;
  final String? city;
  final String? state;
  final String? postalCode;
  final IsoCode? country;

  bool get isEmpty =>
      line1 == null &&
      city == null &&
      state == null &&
      postalCode == null &&
      country == null;

  /// Arma la dirección con lo que devuelve la plataforma, campo por campo.
  ///
  /// Separado de la llamada al plugin para poder probarlo sin canal de
  /// plataforma.
  factory GeocodedAddress.fromParts({
    String? street,
    String? subThoroughfare,
    String? thoroughfare,
    String? locality,
    String? administrativeArea,
    String? postalCode,
    String? isoCountryCode,
  }) {
    final pais = _paisOfrecido(isoCountryCode);
    final calle =
        _noVacio(street) ?? _numeroYCalle(subThoroughfare, thoroughfare);
    final estado = _noVacio(administrativeArea);

    return GeocodedAddress(
      line1: calle,
      city: _noVacio(locality),
      state: estado == null
          ? null
          : StateCodes.toCode(pais ?? SupportedCountries.initial, estado),
      postalCode: _noVacio(postalCode),
      country: pais,
    );
  }

  static String? _noVacio(String? valor) {
    final limpio = valor?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  static String? _numeroYCalle(String? numero, String? calle) {
    final partes = [_noVacio(numero), _noVacio(calle)].nonNulls;
    return partes.isEmpty ? null : partes.join(' ');
  }

  static IsoCode? _paisOfrecido(String? iso) {
    final buscado = iso?.trim().toUpperCase();
    if (buscado == null || buscado.isEmpty) return null;
    for (final candidato in SupportedCountries.all) {
      if (candidato.name == buscado) return candidato;
    }
    return null;
  }
}

/// Del punto a la dirección, con el geocodificador **del teléfono**.
///
/// Sin llave y sin Google Cloud: `CLGeocoder` en iOS, `Geocoder` en Android.
/// Necesita red. Ver la adenda de ADR-0012.
abstract class DeviceGeocoder {
  /// La dirección del punto, o nulo si no se pudo: sin red, sin resultado, o
  /// la plataforma falló. Quien llama no distingue los casos porque en todos
  /// hace lo mismo, dejar los campos como estaban.
  Future<GeocodedAddress?> fromCoordinates(double lat, double lng);

  /// Dónde cae una dirección escrita, para **mover la cámara** del mapa.
  ///
  /// Nunca para fijar el punto: una dirección geocodificada cae en el centro
  /// de la manzana o sobre la calle, y acá el punto es la geocerca (ADR-0012).
  Future<({double lat, double lng})?> searchAddress(String address);
}

class PlatformDeviceGeocoder implements DeviceGeocoder {
  const PlatformDeviceGeocoder();

  /// El canal de plataforma no tiene tope propio; sin este, un teléfono con
  /// señal a medias deja la hoja esperando.
  static const espera = Duration(seconds: 8);

  @override
  Future<GeocodedAddress?> fromCoordinates(double lat, double lng) async {
    try {
      final lugares = await Geocoding()
          .placemarkFromCoordinates(lat, lng)
          .timeout(espera);
      if (lugares.isEmpty) return null;
      final lugar = lugares.first;
      final direccion = GeocodedAddress.fromParts(
        street: lugar.street,
        subThoroughfare: lugar.subThoroughfare,
        thoroughfare: lugar.thoroughfare,
        locality: lugar.locality,
        administrativeArea: lugar.administrativeArea,
        postalCode: lugar.postalCode,
        isoCountryCode: lugar.isoCountryCode,
      );
      return direccion.isEmpty ? null : direccion;
    } on Object {
      return null;
    }
  }

  @override
  Future<({double lat, double lng})?> searchAddress(String address) async {
    final texto = address.trim();
    if (texto.isEmpty) return null;
    try {
      final lugares = await Geocoding()
          .locationFromAddress(texto)
          .timeout(espera);
      if (lugares.isEmpty) return null;
      final lugar = lugares.first;
      return (lat: lugar.latitude, lng: lugar.longitude);
    } on Object {
      return null;
    }
  }
}

final deviceGeocoderProvider = Provider<DeviceGeocoder>(
  (ref) => const PlatformDeviceGeocoder(),
);
