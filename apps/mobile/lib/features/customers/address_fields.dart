import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';

import '../../api/models/address_dto.dart';
import '../../core/i18n/supported_countries.dart';
import '../../core/location/device_geocoder.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/country_field.dart';
import '../../l10n/app_localizations.dart';

/// Los campos que el geocodificador puede escribir. La línea 2 no está: el
/// teléfono no sabe de apartamentos.
///
/// El país solo aparece al comparar una dirección guardada contra la del punto
/// nuevo, nunca al rellenar: ahí no tiene vacío que distinga elegido de default.
enum AddressPart { line1, city, state, postalCode, country }

/// Un campo que cambiaría si se tomara la dirección del punto.
class AddressChange {
  const AddressChange({
    required this.part,
    required this.before,
    required this.after,
  });

  final AddressPart part;

  /// Lo que hay hoy. Vacío si el campo estaba en blanco.
  final String before;
  final String after;
}

/// Los seis campos de una dirección, con su estado.
///
/// Vive acá y no dentro de un formulario en particular porque la misma dirección
/// es la de facturación del cliente y la de la propiedad. Un segundo juego de
/// campos divergiría del primero.
class AddressFormControllers {
  AddressFormControllers({AddressDto? initial})
    : line1 = TextEditingController(text: initial?.line1 ?? ''),
      line2 = TextEditingController(text: initial?.line2 ?? ''),
      city = TextEditingController(text: initial?.city ?? ''),
      state = TextEditingController(text: initial?.state ?? ''),
      postalCode = TextEditingController(text: initial?.postalCode ?? ''),
      country = ValueNotifier<IsoCode>(_pais(initial?.country));

  final TextEditingController line1;

  /// Para devolverle el cursor a la calle cuando se pide corregir lo rellenado.
  final FocusNode line1Focus = FocusNode();
  final TextEditingController line2;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController postalCode;

  /// El país se elige de una lista, no se teclea: el contrato lo quiere en ISO
  /// de dos letras y "Mexico" escrito a mano no lo es.
  final ValueNotifier<IsoCode> country;

  /// Ningún campo tocado. Una dirección opcional en blanco no se manda.
  bool get isEmpty =>
      line1.text.trim().isEmpty &&
      line2.text.trim().isEmpty &&
      city.text.trim().isEmpty &&
      state.text.trim().isEmpty &&
      postalCode.text.trim().isEmpty;

  /// Lo que el geocodificador escribió en cada campo, para saber después qué
  /// es suyo y qué lo escribió una persona.
  final Map<AddressPart, String> _puestoPorGeocoder = {};

  /// Escribe lo que trajo el geocodificador y devuelve qué campos tocó.
  ///
  /// Tres estados por campo —vacío, puesto por el geocodificador, escrito a
  /// mano—, y el país nunca se rellena. La regla está en SPEC-0013.
  List<AddressPart> fillMissing(GeocodedAddress origen) {
    final rellenados = <AddressPart>[];
    void poner(AddressPart parte, TextEditingController campo, String? valor) {
      if (valor == null) return;
      final actual = campo.text.trim();
      final mio = _puestoPorGeocoder[parte];
      if (actual.isNotEmpty && actual != mio) return;
      if (actual == valor) return;
      campo.text = valor;
      _puestoPorGeocoder[parte] = valor;
      rellenados.add(parte);
    }

    // El país nunca entra acá: ver [AddressPart].
    poner(AddressPart.line1, line1, origen.line1);
    poner(AddressPart.city, city, origen.city);
    poner(AddressPart.postalCode, postalCode, origen.postalCode);
    final pais = origen.country;
    if (pais == null || pais == country.value) {
      poner(AddressPart.state, state, origen.state);
    }
    return rellenados;
  }

  TextEditingController? controllerOf(AddressPart parte) => switch (parte) {
    AddressPart.line1 => line1,
    AddressPart.city => city,
    AddressPart.state => state,
    AddressPart.postalCode => postalCode,
    AddressPart.country => null,
  };

  /// Qué campos cambiarían si se tomara [origen], **sin tocar nada**.
  ///
  /// Para una dirección ya guardada: se compara todo, el país incluido, y
  /// decide quien mire la comparación.
  List<AddressChange> diff(
    GeocodedAddress origen, {
    String Function(IsoCode)? countryName,
  }) {
    final cambios = <AddressChange>[];
    void comparar(AddressPart parte, String actual, String? nuevo) {
      if (nuevo == null || nuevo.trim() == actual.trim()) return;
      cambios.add(
        AddressChange(part: parte, before: actual.trim(), after: nuevo.trim()),
      );
    }

    comparar(AddressPart.line1, line1.text, origen.line1);
    comparar(AddressPart.city, city.text, origen.city);
    comparar(AddressPart.state, state.text, origen.state);
    comparar(AddressPart.postalCode, postalCode.text, origen.postalCode);
    final pais = origen.country;
    if (pais != null && pais != country.value) {
      cambios.add(
        AddressChange(
          part: AddressPart.country,
          before: countryName?.call(country.value) ?? country.value.name,
          after: countryName?.call(pais) ?? pais.name,
        ),
      );
    }
    return cambios;
  }

  /// Aplica lo que la comparación ofreció y lo marca como del geocodificador.
  void applyChanges(List<AddressChange> cambios, GeocodedAddress origen) {
    for (final cambio in cambios) {
      if (cambio.part == AddressPart.country) {
        final pais = origen.country;
        if (pais != null) country.value = pais;
        continue;
      }
      controllerOf(cambio.part)!.text = cambio.after;
      _puestoPorGeocoder[cambio.part] = cambio.after;
    }
  }

  AddressDto? toDto() {
    if (isEmpty) return null;
    return AddressDto(
      line1: line1.text.trim(),
      line2: line2.text.trim().isEmpty ? null : line2.text.trim(),
      city: city.text.trim(),
      // Mayúsculas solo donde el estado es un código: `md` y `MD` son el mismo
      // estado. Pasar «San José» a mayúsculas rompe el dato, no lo normaliza.
      state: SupportedCountries.esCodigoDeDosLetras(country.value)
          ? state.text.trim().toUpperCase()
          : state.text.trim(),
      postalCode: postalCode.text.trim(),
      country: country.value.name,
    );
  }

  void dispose() {
    line1.dispose();
    line1Focus.dispose();
    line2.dispose();
    city.dispose();
    state.dispose();
    postalCode.dispose();
    country.dispose();
  }

  /// Lo guardado llega como ISO de dos letras. Un país que la lista no ofrece
  /// —o basura— cae en el por defecto: el selector no puede quedarse sin valor.
  static IsoCode _pais(String? guardado) {
    if (guardado == null) return SupportedCountries.initial;
    for (final iso in IsoCode.values) {
      if (iso.name == guardado.toUpperCase()) return iso;
    }
    return SupportedCountries.initial;
  }
}

/// Los campos de una dirección.
///
/// Con `optional` en `true` —la de facturación— no exige nada si está vacía,
/// pero sí completa el resto en cuanto se escribió la calle: media dirección no
/// imprime una factura.
class AddressFields extends StatelessWidget {
  const AddressFields({
    super.key,
    required this.controllers,
    this.optional = false,
    this.enabled = true,
  });

  final AddressFormControllers controllers;
  final bool optional;

  /// En `false` mientras el geocodificador rellena: lo que aparece no se mezcla
  /// con lo que se estaba tipeando.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;

    // Con la dirección opcional y en blanco no se valida nada; en cuanto hay
    // algo escrito, los obligatorios vuelven a serlo.
    String? exigir(String? valor, String mensaje) {
      if (optional && controllers.isEmpty) return null;
      return (valor == null || valor.trim().isEmpty) ? mensaje : null;
    }

    // Con la dirección obligatoria se dice en el label; con la opcional no, o
    // marcaría como obligatorio algo que se puede dejar entero en blanco.
    String etiqueta(String texto) =>
        optional ? texto : l10n.fieldRequiredLabel(texto);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controllers.line1,
          focusNode: controllers.line1Focus,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: etiqueta(l10n.addressLine1)),
          validator: (v) => exigir(v, l10n.addressLine1Required),
        ),
        SizedBox(height: spacing.md),
        TextFormField(
          controller: controllers.line2,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.addressLine2),
        ),
        SizedBox(height: spacing.md),
        TextFormField(
          controller: controllers.city,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: etiqueta(l10n.addressCity)),
          validator: (v) => exigir(v, l10n.addressCityRequired),
        ),
        SizedBox(height: spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // La regla del estado depende del país, así que el campo lo
              // escucha: en Estados Unidos y Canadá es un código de dos letras;
              // en el resto, el nombre entero de la provincia. El servidor
              // valida lo mismo, y sin esto el rechazo llegaría al sincronizar.
              child: ValueListenableBuilder<IsoCode>(
                valueListenable: controllers.country,
                builder: (context, iso, _) {
                  final dosLetras = SupportedCountries.esCodigoDeDosLetras(iso);
                  return TextFormField(
                    controller: controllers.state,
                    enabled: enabled,
                    textCapitalization: dosLetras
                        ? TextCapitalization.characters
                        : TextCapitalization.words,
                    maxLength: dosLetras ? 2 : 100,
                    buildCounter: _sinContador,
                    decoration: InputDecoration(
                      labelText: etiqueta(l10n.addressState),
                    ),
                    validator: (v) {
                      if (optional && controllers.isEmpty) return null;
                      final valor = v?.trim() ?? '';
                      if (valor.isEmpty) return l10n.addressStateRequired;
                      return dosLetras && valor.length != 2
                          ? l10n.addressStateTwoLetters
                          : null;
                    },
                  );
                },
              ),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: TextFormField(
                controller: controllers.postalCode,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: etiqueta(l10n.addressPostalCode),
                ),
                validator: (v) => exigir(v, l10n.addressPostalCodeRequired),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        ValueListenableBuilder<IsoCode>(
          valueListenable: controllers.country,
          builder: (context, seleccionado, _) => CountryField(
            selected: seleccionado,
            label: l10n.addressCountry,
            enabled: enabled,
            onChanged: (iso) => controllers.country.value = iso,
          ),
        ),
      ],
    );
  }

  /// `maxLength` dibuja "1/2" debajo del campo y desalinea la fila. El límite
  /// sigue aplicando.
  static Widget? _sinContador(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}
