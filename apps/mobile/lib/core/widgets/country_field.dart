import 'package:flutter/material.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';

import '../i18n/supported_countries.dart';
import '../theme/theme_extensions.dart';

/// El país de una dirección.
///
/// Se elige de una lista y no se teclea: el contrato lo quiere en ISO de dos
/// letras, y quien escribe "Mexico" a mano manda algo que el servidor rechaza al
/// sincronizar —o peor, guarda mal—. El nombre sale traducido del mismo paquete
/// que el selector del teléfono, así que no hay una segunda lista de países que
/// mantener.
class CountryField extends StatelessWidget {
  const CountryField({
    super.key,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final IsoCode selected;
  final String label;
  final ValueChanged<IsoCode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    // Sin el delegate registrado cae al código ISO: preferible a un campo en
    // blanco que no dice qué país está elegido.
    final nombre =
        CountrySelectorLocalization.of(context)?.countryName(selected) ??
        selected.name;

    // `InputDecorator` y no un botón suelto: así toma el relleno, el borde y el
    // label del tema, y se ve como los campos de arriba en vez de un control
    // aparte.
    return InkWell(
      borderRadius: BorderRadius.circular(spacing.radiusMd),
      onTap: enabled ? () => _elegir(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
        child: Row(
          children: [
            // El nombre traducido y no la bandera: a este tamaño una bandera se
            // confunde con otra, y las banderas ya están en la hoja al elegir.
            Expanded(child: Text(nombre, style: context.texts.bodyLarge)),
            SizedBox(width: spacing.sm),
            Icon(Icons.arrow_drop_down, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _elegir(BuildContext context) async {
    // El teclado queda abajo al abrir: el foco lo tenía el campo anterior y sin
    // esto la hoja se abre con media lista tapada.
    FocusManager.instance.primaryFocus?.unfocus();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (hoja) => SizedBox(
        height: MediaQuery.sizeOf(hoja).height * 0.7,
        child: CountrySelector.sheet(
          countries: SupportedCountries.all,
          favoriteCountries: SupportedCountries.favorites,
          searchAutofocus: false,
          showDialCode: false,
          onCountrySelected: (iso) {
            onChanged(iso);
            Navigator.of(hoja).pop();
          },
        ),
      ),
    );
  }
}
