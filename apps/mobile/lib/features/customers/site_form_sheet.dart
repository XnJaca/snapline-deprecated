import 'package:flutter/material.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/device_geocoder.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/customer_repository.dart';
import '../../l10n/app_localizations.dart';
import 'address_fields.dart';
import 'address_review_sheet.dart';
import 'form_sheet.dart';
import 'site_location_block.dart';
import 'site_location_screen.dart';

/// Alta y corrección de una propiedad, en una hoja.
///
/// Devuelve el id de la propiedad, o `null` si se canceló. Es hoja y no pantalla
/// porque se abre desde adentro de otro formulario —el alta de obra de
/// SPEC-0005— y mandar a pantalla completa perdería lo que ya estaba escrito.
///
/// `site` en `null` es alta; con valor, corrección.
Future<String?> showSiteFormSheet(
  BuildContext context, {
  required String customerId,
  SiteSummary? site,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SiteFormSheet(customerId: customerId, site: site),
  );
}

class _SiteFormSheet extends ConsumerStatefulWidget {
  const _SiteFormSheet({required this.customerId, this.site});

  final String customerId;
  final SiteSummary? site;

  @override
  ConsumerState<_SiteFormSheet> createState() => _SiteFormSheetState();
}

class _SiteFormSheetState extends ConsumerState<_SiteFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final AddressFormControllers _direccion;
  bool _guardando = false;

  /// El punto elegido en el alta. Vive acá hasta «Agregar»: la propiedad no
  /// existe todavía, así que no hay contra qué guardarlo.
  SiteLocationResult? _punto;

  /// Si el geocodificador llenó algo al volver del mapa: se dice, para que se
  /// revise el número.
  bool _direccionRellenada = false;

  /// Mientras el teléfono responde: los campos, «Agregar» y el mapa quedan
  /// bloqueados.
  bool _buscandoDireccion = false;

  /// Cuál es la búsqueda vigente. Sube con cada punto elegido, y una respuesta
  /// que llega con un número viejo se descarta: es la del punto descartado.
  int _busqueda = 0;

  @override
  void initState() {
    super.initState();
    _direccion = AddressFormControllers(initial: widget.site?.address);
  }

  @override
  void dispose() {
    _direccion.dispose();
    super.dispose();
  }

  /// La dirección tal como está escrita ahora, completa o no, para mostrarla
  /// bajo el mapa. No pasa por `toDto`, que exige los campos obligatorios.
  String get _direccionEscrita => [
    _direccion.line1.text,
    _direccion.city.text,
    _direccion.state.text,
  ].map((parte) => parte.trim()).where((parte) => parte.isNotEmpty).join(', ');

  Future<void> _elegirPunto() async {
    final elegido = await Navigator.of(context).push<SiteLocationResult>(
      MaterialPageRoute(
        builder: (_) => SiteLocationScreen.pick(
          address: _direccionEscrita,
          initialLat: _punto?.lat,
          initialLng: _punto?.lng,
          initialRadiusM: _punto?.geofenceRadiusM,
        ),
      ),
    );
    if (elegido == null || !mounted) return;
    setState(() => _punto = elegido);
    await _rellenarDireccion(elegido);
  }

  /// Del punto a la dirección, solo los campos vacíos. Si no se pudo, no pasa
  /// nada: el mapa ya avisó si faltaba la red, y se escribe a mano.
  Future<void> _rellenarDireccion(SiteLocationResult punto) async {
    final mia = ++_busqueda;
    setState(() => _buscandoDireccion = true);
    GeocodedAddress? direccion;
    try {
      direccion = await ref
          .read(deviceGeocoderProvider)
          .fromCoordinates(punto.lat, punto.lng);
    } finally {
      if (mounted && mia == _busqueda) {
        setState(() => _buscandoDireccion = false);
      }
    }
    if (direccion == null || !mounted || mia != _busqueda) return;

    final rellenados = _direccion.fillMissing(direccion);
    if (rellenados.isEmpty) return;
    setState(() => _direccionRellenada = true);

    final estaBien = await showAddressReviewSheet(
      context,
      controllers: _direccion,
      filled: rellenados,
    );
    if (!estaBien && mounted) _direccion.line1Focus.requestFocus();
  }

  /// El punto de una propiedad guardada se movió: se ofrece poner la dirección
  /// que le corresponde. La regla está en SPEC-0013.
  ///
  /// Aceptar **escribe y encola en el acto**, sin esperar a «Guardar»: mover el
  /// punto ya se guardó solo, y dejar la dirección esperando un toque más
  /// reconstruye el mismo desacuerdo que esto viene a resolver.
  Future<void> _ofrecerActualizarDireccion(double lat, double lng) async {
    final mia = ++_busqueda;
    setState(() => _buscandoDireccion = true);
    GeocodedAddress? direccion;
    try {
      direccion = await ref
          .read(deviceGeocoderProvider)
          .fromCoordinates(lat, lng);
    } finally {
      if (mounted && mia == _busqueda) {
        setState(() => _buscandoDireccion = false);
      }
    }
    if (direccion == null || !mounted || mia != _busqueda) return;

    final cambios = _direccion.diff(
      direccion,
      countryName: CountrySelectorLocalization.of(context)?.countryName,
    );
    if (cambios.isEmpty) return;

    final actualizar = await showAddressUpdateSheet(context, changes: cambios);
    if (!actualizar || !mounted || mia != _busqueda) return;

    setState(() => _direccion.applyChanges(cambios, direccion!));
    final actualizada = _direccion.toDto();
    if (actualizada == null) return;
    await ref
        .read(customerRepositoryProvider)
        .updateSite(widget.site!.id, actualizada);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate() || _guardando) return;

    final direccion = _direccion.toDto();
    if (direccion == null) return;

    setState(() => _guardando = true);
    final repo = ref.read(customerRepositoryProvider);

    // La escritura es local: se aplica al instante y se encola. No hay estado de
    // espera de red que mostrar porque no se espera a la red.
    final id = widget.site == null
        ? await repo.addSite(
            widget.customerId,
            direccion,
            lat: _punto?.lat,
            lng: _punto?.lng,
            geofenceRadiusM: _punto?.geofenceRadiusM,
          )
        : await repo
              .updateSite(widget.site!.id, direccion)
              .then((_) => widget.site!.id);

    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return FormSheet(
      title: widget.site == null ? l10n.siteNewTitle : l10n.siteEditTitle,
      formKey: _formKey,
      onSave: _guardando || _buscandoDireccion ? null : _guardar,
      saveLabel: widget.site == null ? l10n.actionAdd : l10n.actionSave,
      children: [
        Text(
          l10n.customerFirstSiteHelp,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        SizedBox(height: context.spacing.md),
        // En el alta el mapa va primero: lo natural es usar la ubicación y
        // corregir lo que vino. En corrección la dirección sigue arriba.
        if (widget.site case final site?) ...[
          AddressFields(controllers: _direccion, enabled: !_buscandoDireccion),
          SizedBox(height: context.spacing.xl),
          SavedSiteLocationBlock(
            site: site,
            onMoved: _ofrecerActualizarDireccion,
            onSet: _buscandoDireccion ? null : () {},
          ),
        ] else ...[
          SiteLocationBlock(
            lat: _punto?.lat,
            lng: _punto?.lng,
            chosen: _punto != null,
            onSet: _buscandoDireccion ? null : _elegirPunto,
          ),
          SizedBox(height: context.spacing.xl),
          AddressFields(controllers: _direccion, enabled: !_buscandoDireccion),
          if (_buscandoDireccion) ...[
            SizedBox(height: context.spacing.sm),
            Row(
              children: [
                SizedBox.square(
                  dimension: context.spacing.lg,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: context.spacing.sm),
                Expanded(
                  child: Text(
                    l10n.siteAddressLookingUp,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_direccionRellenada) ...[
            SizedBox(height: context.spacing.sm),
            Text(
              l10n.siteAddressFilledFromPoint,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
