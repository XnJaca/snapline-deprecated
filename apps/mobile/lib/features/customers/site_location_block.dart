import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/open_in_maps.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/customer_repository.dart';
import '../../l10n/app_localizations.dart';
import 'site_location_screen.dart';

/// El bloque de ubicación dentro de la hoja de una propiedad.
///
/// Sin punto invita a fijarlo; con punto muestra las coordenadas y deja
/// corregirlo. **No dibuja un mapa acá**: la propiedad se ubica en la pantalla
/// completa, y un mapa de 200px que además tiene que cargar tiles sería un
/// costo por cada vez que alguien abre la ficha a corregir un teléfono.
///
/// Recibe valores, no la propiedad: en el alta la propiedad no existe todavía y
/// el punto vive en la hoja. Para una propiedad guardada, [SavedSiteLocationBlock]
/// lo alimenta desde el stream.
class SiteLocationBlock extends StatelessWidget {
  const SiteLocationBlock({
    super.key,
    required this.lat,
    required this.lng,
    required this.onSet,
    this.chosen = false,
  });

  final double? lat;
  final double? lng;

  /// `null` deshabilita: mientras se busca la dirección del punto anterior,
  /// elegir otro dejaría dos búsquedas escribiendo sobre los mismos campos.
  final VoidCallback? onSet;

  /// Elegido en el alta y todavía sin guardar: se dice, para que no parezca que
  /// ya quedó.
  final bool chosen;

  bool get _hasLocation => lat != null && lng != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.siteLocationSection, style: context.texts.labelLarge),
        SizedBox(height: context.spacing.sm),
        if (!_hasLocation)
          Text(
            l10n.siteLocationEmpty,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          )
        else ...[
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: context.spacing.xl,
                color: context.colors.onSurfaceVariant,
              ),
              SizedBox(width: context.spacing.sm),
              Expanded(
                child: Text(
                  l10n.siteLocationCoords(
                    lat!.toStringAsFixed(5),
                    lng!.toStringAsFixed(5),
                  ),
                  style: context.texts.bodyMedium,
                ),
              ),
              if (!chosen)
                TextButton.icon(
                  onPressed: () => openInMaps(lat: lat, lng: lng),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.siteLocationOpenInMaps),
                ),
            ],
          ),
          if (chosen) ...[
            SizedBox(height: context.spacing.xs),
            Text(
              l10n.siteLocationChosen,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
        SizedBox(height: context.spacing.sm),
        OutlinedButton.icon(
          onPressed: onSet,
          icon: const Icon(Icons.map_outlined),
          label: Text(
            _hasLocation ? l10n.siteLocationEdit : l10n.siteLocationSet,
          ),
        ),
      ],
    );
  }
}

/// El bloque para una propiedad que ya existe.
///
/// Lee el stream de Drift, así que al volver de la pantalla del mapa el punto
/// nuevo llega solo. Es el `watch` que antes vivía dentro del bloque: se mueve
/// acá para que el alta pueda usar el mismo bloque sin propiedad.
class SavedSiteLocationBlock extends ConsumerWidget {
  const SavedSiteLocationBlock({
    super.key,
    required this.site,
    this.onMoved,
    this.onSet = _habilitado,
  });

  /// Solo marca que el botón está habilitado: el push lo arma este bloque.
  static void _habilitado() {}

  final SiteSummary site;

  /// Se llama con el punto nuevo después de guardarlo, para ofrecer actualizar
  /// la dirección que ya estaba.
  final void Function(double lat, double lng)? onMoved;

  /// `null` deshabilita el botón, como en el bloque del alta.
  final VoidCallback? onSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actual =
        ref
            .watch(customerSitesProvider(site.customerId))
            .value
            ?.where((s) => s.id == site.id)
            .firstOrNull ??
        site;

    return SiteLocationBlock(
      lat: actual.lat,
      lng: actual.lng,
      onSet: onSet == null
          ? null
          : () async {
              final guardado = await Navigator.of(context)
                  .push<SiteLocationResult>(
                    MaterialPageRoute(
                      builder: (_) => SiteLocationScreen(site: actual),
                    ),
                  );
              if (guardado != null) onMoved?.call(guardado.lat, guardado.lng);
            },
    );
  }
}
