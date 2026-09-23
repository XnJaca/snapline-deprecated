import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location/device_geocoder.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/form_footer.dart';
import '../../data/repositories/customer_repository.dart';
import '../../l10n/app_localizations.dart';
import 'address_fields.dart';
import 'address_review_sheet.dart';
import 'customer_fields.dart';
import 'site_location_block.dart';
import 'site_location_screen.dart';

/// La ficha completa de un cliente: alta y corrección.
///
/// Pantalla y no hoja porque son muchos campos. La versión de dos campos que se
/// llena parado en una obra es `showCustomerFormSheet`, con los mismos campos en
/// modo mínimo.
///
/// `customerId` en `null` es alta; con valor, corrección.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customerId});

  static const newRoute = '/customers/new';

  final String? customerId;

  static String editRoute(String id) => '/customers/$id/edit';

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Se crean al primer build con lo que haya en local, no en `initState`: en
  /// edición hay que esperar a que el stream traiga la ficha.
  CustomerFormControllers? _campos;

  /// Solo en el alta: la primera propiedad del cliente, opcional.
  final _primeraPropiedad = AddressFormControllers();

  /// El punto de la primera propiedad. Vive acá hasta «Guardar»: ni el cliente
  /// ni la propiedad existen todavía.
  SiteLocationResult? _punto;
  bool _direccionRellenada = false;
  bool _buscandoDireccion = false;

  /// Cuál es la búsqueda vigente. Una respuesta con número viejo se descarta:
  /// es la del punto que se descartó.
  int _busqueda = 0;

  bool _guardando = false;

  bool get _esAlta => widget.customerId == null;

  @override
  void dispose() {
    _campos?.dispose();
    _primeraPropiedad.dispose();
    super.dispose();
  }

  /// La dirección tal como está escrita ahora, completa o no, para mostrarla
  /// bajo el mapa.
  String get _direccionEscrita => [
    _primeraPropiedad.line1.text,
    _primeraPropiedad.city.text,
    _primeraPropiedad.state.text,
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

  /// Del punto a la dirección, solo los campos vacíos. La regla está en
  /// SPEC-0013.
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

    final rellenados = _primeraPropiedad.fillMissing(direccion);
    if (rellenados.isEmpty) return;
    setState(() => _direccionRellenada = true);

    final estaBien = await showAddressReviewSheet(
      context,
      controllers: _primeraPropiedad,
      filled: rellenados,
    );
    if (!estaBien && mounted) _primeraPropiedad.line1Focus.requestFocus();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate() || _guardando) return;

    setState(() => _guardando = true);
    final repo = ref.read(customerRepositoryProvider);
    final input = _campos!.toInput();

    if (_esAlta) {
      // En este orden y no en paralelo: la propiedad cuelga del cliente, y el
      // servidor aplica el lote por `occurredAt`. Si llegara antes, la rechaza
      // por cliente inexistente.
      final id = await repo.create(input);
      final direccion = _primeraPropiedad.toDto();
      if (direccion != null) {
        await repo.addSite(
          id,
          direccion,
          lat: _punto?.lat,
          lng: _punto?.lng,
          geofenceRadiusM: _punto?.geofenceRadiusM,
        );
      }

      // Reemplaza el formulario, no lo apila: el back del detalle vuelve a la
      // lista y no a un alta ya guardada.
      if (mounted) context.pushReplacement('/customers/$id');
      return;
    }

    await repo.update(widget.customerId!, input);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;

    final consulta = _esAlta
        ? null
        : ref.watch(customerByIdProvider(widget.customerId!));
    final ficha = consulta?.value;

    // En edición se espera la ficha; en alta se arranca en blanco. El
    // `hasValue` evita anunciar "no está" en el frame anterior a la primera
    // emisión del stream, y evita armar los controllers vacíos y quedarse así.
    if (!_esAlta && ficha == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.customerEditTitle)),
        body: consulta!.hasValue
            ? EmptyState(
                icon: Icons.person_off_outlined,
                message: l10n.customerNotFound,
              )
            : const SizedBox.shrink(),
      );
    }
    _campos ??= CustomerFormControllers(initial: ficha);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        title: Text(_esAlta ? l10n.customerNewTitle : l10n.customerEditTitle),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(spacing.lg),
                children: [
                  CustomerFields(controllers: _campos!),
                  if (_esAlta) ...[
                    SizedBox(height: spacing.lg),
                    Text(
                      l10n.customerFirstSite,
                      style: context.texts.titleSmall,
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      l10n.customerFirstSiteHelp,
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: spacing.md),
                    // El mapa antes de la dirección, igual que en la hoja de
                    // propiedad: lo natural es usar la ubicación y corregir lo
                    // que vino.
                    SiteLocationBlock(
                      lat: _punto?.lat,
                      lng: _punto?.lng,
                      chosen: _punto != null,
                      onSet: _buscandoDireccion ? null : _elegirPunto,
                    ),
                    SizedBox(height: spacing.lg),
                    AddressFields(
                      controllers: _primeraPropiedad,
                      // Con punto elegido la dirección deja de ser opcional: sin
                      // ella no hay propiedad que guardar, y el punto se
                      // perdería en silencio.
                      optional: _punto == null,
                      enabled: !_buscandoDireccion,
                    ),
                    if (_buscandoDireccion) ...[
                      SizedBox(height: spacing.sm),
                      Row(
                        children: [
                          SizedBox.square(
                            dimension: spacing.lg,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: spacing.sm),
                          Expanded(
                            child: Text(
                              l10n.siteAddressLookingUp,
                              style: context.texts.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (_direccionRellenada) ...[
                      SizedBox(height: spacing.sm),
                      Text(
                        l10n.siteAddressFilledFromPoint,
                        style: context.texts.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            // Fijo al pie y no al final del scroll: son quince campos, y un
            // botón que hay que ir a buscar hasta abajo no se encuentra. Lo
            // único naranja sólido de la pantalla.
            FormFooter(
              child: FilledButton(
                onPressed: _guardando || _buscandoDireccion ? null : _guardar,
                child: Text(l10n.actionSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
