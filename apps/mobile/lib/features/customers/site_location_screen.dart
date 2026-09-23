import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/location/device_geocoder.dart';
import '../../core/location/device_location.dart';
import '../../core/location/map_type_store.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/field_action_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/sync/connectivity.dart';
import '../../l10n/app_localizations.dart';

/// Radios que se ofrecen, en metros.
///
/// Es un rango con paso y no un campo de texto: nadie sabe cuánto es 150, y el
/// número solo significa algo mirando el círculo sobre el mapa.
const _radioMin = 50.0;
const _radioMax = 500.0;
const _radioPaso = 25;

/// Cuando la propiedad no tiene punto, el mapa abre acá.
///
/// Es el centro de Maryland, donde trabaja el design partner. Abrir en (0,0)
/// —en medio del Atlántico— haría que la primera acción sea siempre buscar el
/// continente.
const _centroPorDefecto = LatLng(39.0458, -76.6413);

/// Lo que la pantalla devuelve en modo elegir: el punto y el radio, sin haber
/// escrito nada. Quien la abrió decide cuándo y con qué se guardan.
class SiteLocationResult {
  const SiteLocationResult({
    required this.lat,
    required this.lng,
    this.geofenceRadiusM,
  });

  final double lat;
  final double lng;
  final int? geofenceRadiusM;
}

/// Fija el punto y el radio de la geocerca de una propiedad.
///
/// Es pantalla completa y no una hoja: el punto se elige arrastrando con el
/// pulgar y necesita el ancho.
///
/// Dos modos con la misma pantalla. Con [site], guarda contra la propiedad y
/// vuelve con `true`. Con [SiteLocationScreen.pick] la propiedad todavía no
/// existe —es el alta—, así que no escribe: vuelve con un [SiteLocationResult]
/// y la hoja lo guarda junto con la dirección.
class SiteLocationScreen extends ConsumerStatefulWidget {
  SiteLocationScreen({super.key, required SiteSummary this.site})
    : address = site.oneLine,
      initialLat = site.lat,
      initialLng = site.lng,
      initialRadiusM = site.geofenceRadiusM;

  const SiteLocationScreen.pick({
    super.key,
    required this.address,
    this.initialLat,
    this.initialLng,
    this.initialRadiusM,
  }) : site = null;

  final SiteSummary? site;

  /// La dirección que se muestra bajo el mapa. En el alta es la que está escrita
  /// en la hoja en ese momento, completa o no.
  final String address;
  final double? initialLat;
  final double? initialLng;
  final int? initialRadiusM;

  bool get picks => site == null;

  @override
  ConsumerState<SiteLocationScreen> createState() => _SiteLocationScreenState();
}

class _SiteLocationScreenState extends ConsumerState<SiteLocationScreen> {
  LatLng? _punto;
  double? _radio;
  bool _guardando = false;
  bool _buscandoUbicacion = false;
  LocationFailure? _falloUbicacion;

  final _busqueda = TextEditingController();
  bool _buscandoDireccion = false;
  bool _sinResultado = false;

  /// `initialCameraPosition` solo se aplica al crear el mapa, así que mover el
  /// marcador no mueve la vista. Sin este controlador, "usar mi ubicación" pone
  /// el punto donde estás y te deja mirando el otro lado del continente.
  GoogleMapController? _mapa;

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (lat != null && lng != null) _punto = LatLng(lat, lng);
    _radio = widget.initialRadiusM?.toDouble();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _mapa?.dispose();
    super.dispose();
  }

  /// Lleva la cámara a la dirección escrita. **No fija el punto**: una
  /// dirección geocodificada cae en el centro de la manzana, y acá el punto es
  /// la geocerca (ADR-0012).
  Future<void> _buscarDireccion() async {
    final texto = _busqueda.text.trim();
    if (texto.isEmpty || _buscandoDireccion) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _buscandoDireccion = true;
      _sinResultado = false;
    });

    ({double lat, double lng})? donde;
    try {
      donde = await ref.read(deviceGeocoderProvider).searchAddress(texto);
    } finally {
      if (mounted) setState(() => _buscandoDireccion = false);
    }
    if (!mounted) return;

    if (donde == null) {
      setState(() => _sinResultado = true);
      return;
    }
    await _mapa?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(donde.lat, donde.lng), 17),
    );
  }

  Future<void> _usarMiUbicacion() async {
    setState(() {
      _buscandoUbicacion = true;
      _falloUbicacion = null;
    });

    final resultado = await ref.read(deviceLocationProvider).current();
    if (!mounted) return;

    setState(() {
      _buscandoUbicacion = false;
      if (resultado.isOk) {
        _punto = LatLng(resultado.lat!, resultado.lng!);
      } else {
        _falloUbicacion = resultado.failure;
      }
    });

    if (resultado.isOk) {
      await _mapa?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(resultado.lat!, resultado.lng!), 17),
      );
    }
  }

  Future<void> _guardar() async {
    final punto = _punto;
    if (punto == null || _guardando) return;

    final site = widget.site;
    if (site == null) {
      Navigator.of(context).pop(
        SiteLocationResult(
          lat: punto.latitude,
          lng: punto.longitude,
          geofenceRadiusM: _radio?.round(),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await ref
          .read(customerRepositoryProvider)
          .setSiteLocation(
            site.id,
            lat: punto.latitude,
            lng: punto.longitude,
            geofenceRadiusM: _radio?.round(),
          );
    } finally {
      // La escritura es local y casi nunca falla, pero si falla el botón no
      // puede quedar deshabilitado para siempre.
      if (mounted) setState(() => _guardando = false);
    }

    if (!mounted) return;
    // Devuelve el punto y no `true`: quien la abrió lo necesita exacto, y
    // leerlo del stream justo después abre una carrera con la notificación.
    Navigator.of(context).pop(
      SiteLocationResult(
        lat: punto.latitude,
        lng: punto.longitude,
        geofenceRadiusM: _radio?.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hayRed = ref.watch(connectivityProvider).value ?? true;
    final radioDibujado = _radio ?? _radioMin * 2;
    final satelite = ref.watch(satelliteMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.siteLocationTitle),
        actions: [
          // Híbrido y no satélite puro: sin los nombres de las calles la foto
          // aérea no ubica a nadie.
          IconButton(
            icon: Icon(satelite ? Icons.map_outlined : Icons.satellite_alt),
            tooltip: satelite
                ? l10n.siteLocationStandardMap
                : l10n.siteLocationSatellite,
            onPressed: () => ref.read(satelliteMapProvider.notifier).toggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  mapType: satelite ? MapType.hybrid : MapType.normal,
                  initialCameraPosition: CameraPosition(
                    target: _punto ?? _centroPorDefecto,
                    zoom: _punto == null ? 9 : 17,
                  ),
                  onMapCreated: (controlador) => _mapa = controlador,
                  onTap: (posicion) => setState(() => _punto = posicion),
                  markers: {
                    if (_punto != null)
                      Marker(
                        markerId: const MarkerId('site'),
                        position: _punto!,
                        draggable: true,
                        onDragEnd: (posicion) =>
                            setState(() => _punto = posicion),
                      ),
                  },
                  circles: {
                    if (_punto != null)
                      Circle(
                        circleId: const CircleId('geofence'),
                        center: _punto!,
                        radius: radioDibujado,
                        fillColor: context.colors.primary.withValues(
                          alpha: 0.12,
                        ),
                        strokeColor: context.colors.primary,
                        strokeWidth: 2,
                      ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  left: context.spacing.lg,
                  right: context.spacing.lg,
                  top: context.spacing.lg,
                  child: Column(
                    children: [
                      _Buscador(
                        controller: _busqueda,
                        buscando: _buscandoDireccion,
                        onSubmit: _buscarDireccion,
                      ),
                      if (_sinResultado) ...[
                        SizedBox(height: context.spacing.sm),
                        StatusChip(
                          tone: StatusTone.warning,
                          label: l10n.siteLocationSearchEmpty,
                          expand: true,
                        ),
                      ],
                      if (!hayRed || _falloUbicacion != null) ...[
                        SizedBox(height: context.spacing.sm),
                        _Aviso(hayRed: hayRed, fallo: _falloUbicacion),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Controles(
            direccion: widget.address,
            punto: _punto,
            radio: _radio,
            guardando: _guardando,
            buscandoUbicacion: _buscandoUbicacion,
            onUsarMiUbicacion: _usarMiUbicacion,
            onRadio: (valor) => setState(() => _radio = valor),
            onGuardar: _guardar,
          ),
        ],
      ),
    );
  }
}

/// Buscar una dirección para mover la cámara.
///
/// Sobre el mapa y no en la barra: es una ayuda para encontrar la zona, no la
/// acción de la pantalla, y acá queda junto a lo que modifica.
class _Buscador extends StatelessWidget {
  const _Buscador({
    required this.controller,
    required this.buscando,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool buscando;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;

    // Superficie con borde y no elevación: es la forma que usa el resto de la
    // app, y sobre el mapa hace falta el fondo opaco igual.
    return Material(
      borderRadius: BorderRadius.circular(spacing.radiusMd),
      color: context.colors.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.outline),
          borderRadius: BorderRadius.circular(spacing.radiusMd),
        ),
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: l10n.siteLocationSearch,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.md,
            ),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: buscando
                ? Padding(
                    padding: EdgeInsets.all(spacing.md),
                    child: SizedBox.square(
                      dimension: spacing.md,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: l10n.siteLocationSearch,
                    onPressed: onSubmit,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Lo que la pantalla dice cuando algo no está: sin red el mapa no dibuja, y sin
/// permiso no hay "usar mi ubicación". Ninguno de los dos impide poner el punto
/// a mano, y el texto lo dice.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.hayRed, required this.fallo});

  final bool hayRed;
  final LocationFailure? fallo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mensaje = switch (fallo) {
      LocationFailure.serviceDisabled => l10n.siteLocationServiceDisabled,
      LocationFailure.denied => l10n.siteLocationDenied,
      LocationFailure.deniedForever => l10n.siteLocationDeniedForever,
      LocationFailure.timeout => l10n.siteLocationTimeout,
      null => l10n.siteLocationNoNetwork,
    };

    return StatusChip(tone: StatusTone.warning, label: mensaje, expand: true);
  }
}

class _Controles extends StatelessWidget {
  const _Controles({
    required this.direccion,
    required this.punto,
    required this.radio,
    required this.guardando,
    required this.buscandoUbicacion,
    required this.onUsarMiUbicacion,
    required this.onRadio,
    required this.onGuardar,
  });

  final String direccion;
  final LatLng? punto;
  final double? radio;
  final bool guardando;
  final bool buscandoUbicacion;
  final VoidCallback onUsarMiUbicacion;
  final ValueChanged<double> onRadio;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(context.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La dirección y las coordenadas en texto, siempre: sin tiles son
            // lo único que ubica, y es lo que se dicta por teléfono.
            Text(direccion, style: context.texts.labelLarge),
            if (punto != null) ...[
              SizedBox(height: context.spacing.xs),
              Text(
                l10n.siteLocationCoords(
                  punto!.latitude.toStringAsFixed(5),
                  punto!.longitude.toStringAsFixed(5),
                ),
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: context.spacing.sm),
            Text(
              l10n.siteLocationHint,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: context.spacing.md),
            OutlinedButton.icon(
              onPressed: buscandoUbicacion ? null : onUsarMiUbicacion,
              icon: buscandoUbicacion
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(l10n.siteLocationUseMine),
            ),
            SizedBox(height: context.spacing.md),
            Row(
              children: [
                Text(l10n.siteLocationRadius, style: context.texts.labelLarge),
                const Spacer(),
                Text(
                  radio == null
                      ? l10n.siteLocationRadiusDefault
                      : l10n.siteLocationRadiusValue(radio!.round()),
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Slider(
              value: (radio ?? _radioMin * 2).clamp(_radioMin, _radioMax),
              min: _radioMin,
              max: _radioMax,
              divisions: ((_radioMax - _radioMin) / _radioPaso).round(),
              onChanged: onRadio,
            ),
            SizedBox(height: context.spacing.sm),
            FieldActionButton(
              onPressed: punto == null || guardando ? null : onGuardar,
              label: l10n.siteLocationSave,
              icon: Icons.place_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
