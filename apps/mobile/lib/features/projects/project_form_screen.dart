import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/project_status.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/session/session_controller.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/form_footer.dart';
import '../../core/widgets/help_sheet.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../l10n/app_localizations.dart';
import '../customers/site_location_screen.dart';
import 'project_pickers.dart';
import 'project_status_display.dart';

/// Alta y corrección de una obra.
///
/// Pantalla completa y no hoja: son varios campos y se llena parado en una obra.
///
/// `projectId` en `null` es alta; con valor, corrección. **El estado no se edita
/// acá** — se cambia desde el detalle, con solo las transiciones válidas, porque es
/// lo único que el servidor puede descartar.
class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key, this.projectId, this.customerIdInicial});

  /// Con qué cliente abre el alta, cuando se llega desde su ficha. Nulo cuando
  /// se entra por Obras y hay que elegirlo.
  final String? customerIdInicial;

  static const newRoute = '/projects/new';

  /// El alta con el cliente ya puesto, para llegar desde su ficha: ahí el dato
  /// ya está en pantalla y volver a pedirlo es el camino largo.
  static String newRouteForCustomer(String customerId) =>
      '$newRoute?customerId=$customerId';

  final String? projectId;

  static String editRoute(String id) => '/projects/$id/edit';

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _tipoDeTrabajo = TextEditingController();

  late String? _customerId = widget.customerIdInicial;
  String? _siteId;

  /// Nace en obra y no en prospecto: se da de alta parado en el trabajo. Con
  /// `LEAD` la obra recién creada no aparecería en la cartera —que muestra solo
  /// `IN_PROGRESS`— y se leería como que no se guardó.
  ProjectStatus _estado = ProjectStatus.inProgress;

  DateTime? _inicio;
  DateTime? _finEstimado;

  bool _cargado = false;
  bool _guardando = false;

  bool get _esAlta => widget.projectId == null;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _tipoDeTrabajo.dispose();
    super.dispose();
  }

  void _cargarDesde(ProjectSummary obra, ProjectDetail detalle) {
    _nombre.text = obra.name;
    _descripcion.text = detalle.description ?? '';
    _tipoDeTrabajo.text = detalle.serviceType ?? '';
    _customerId = detalle.customerId;
    _siteId = detalle.siteId;
    _estado = obra.status;
    _inicio = detalle.startDate;
    _finEstimado = detalle.targetEndDate;
    _cargado = true;
  }

  Future<void> _elegirCliente() async {
    final id = await showCustomerPicker(context);
    if (id == null || !mounted) return;
    setState(() {
      _customerId = id;
      // Cambiar de cliente vacía la propiedad: el `site_id` tiene que pertenecer
      // al `customer_id` y no se cruzan. Dejarla puesta crearía la obra en la
      // casa de otra persona.
      _siteId = null;
    });
  }

  Future<void> _elegirSitio() async {
    if (_customerId == null) return;
    final id = await showSitePicker(context, customerId: _customerId!);
    if (id == null || !mounted) return;
    setState(() => _siteId = id);
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final actual = esInicio ? _inicio : _finEstimado;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (esInicio) {
        _inicio = elegida;
      } else {
        _finEstimado = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    // Los selectores no son campos de texto, así que su falta no la caza el
    // `Form`: se valida antes y se muestra ahí mismo.
    final faltaSeleccion = _customerId == null || _siteId == null;
    if (!_formKey.currentState!.validate() || faltaSeleccion) {
      setState(() {});
      return;
    }

    setState(() => _guardando = true);
    final repo = ref.read(projectRepositoryProvider);
    final input = ProjectInput(
      customerId: _customerId!,
      siteId: _siteId!,
      name: _nombre.text.trim(),
      status: _estado,
      description: _descripcion.text.trim(),
      serviceType: _tipoDeTrabajo.text.trim(),
      startDate: _inicio,
      targetEndDate: _finEstimado,
    );

    if (_esAlta) {
      final id = await repo.create(input);
      if (mounted) context.pushReplacement('/projects/$id');
      return;
    }

    await repo.update(widget.projectId!, input);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;

    if (!_esAlta && !_cargado) {
      final consulta = ref.watch(projectByIdProvider(widget.projectId!));
      final detalle = ref.watch(projectDetailProvider(widget.projectId!)).value;
      final obra = consulta.value;

      if (obra == null || detalle == null) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.projectEditTitle)),
          body: consulta.hasValue
              ? EmptyState(
                  icon: Icons.work_off_outlined,
                  message: l10n.projectNotFound,
                )
              : const SizedBox.shrink(),
        );
      }
      _cargarDesde(obra, detalle);
    }

    final clientes = ref.watch(customersProvider('')).value ?? const [];
    final cliente = clientes.where((c) => c.id == _customerId).firstOrNull;
    final sitios = _customerId == null
        ? const <SiteSummary>[]
        : (ref.watch(customerSitesProvider(_customerId!)).value ?? const []);
    final sitio = sitios.where((s) => s.id == _siteId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        title: Text(_esAlta ? l10n.projectNewTitle : l10n.projectEditTitle),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(spacing.lg),
                children: [
                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.words,
                    autofocus: _esAlta,
                    decoration: InputDecoration(
                      labelText: l10n.fieldRequiredLabel(l10n.projectFieldName),
                      helperText: l10n.projectFieldNameHelp,
                      helperMaxLines: 2,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.projectFieldNameRequired
                        : null,
                  ),
                  SizedBox(height: spacing.md),
                  // En edición son dato y no campo: se fijan al crear (ficha de
                  // `proyecto`). Una obra tiene horas, fotos y facturas colgando, y
                  // cambiarle el cliente reasigna todo eso a otra persona.
                  if (!_esAlta) ...[
                    _SoloLectura(
                      label: l10n.projectFieldCustomer,
                      value: cliente?.displayName ?? '',
                    ),
                    SizedBox(height: spacing.md),
                    _SoloLectura(
                      label: l10n.projectFieldSite,
                      value: sitio?.oneLine ?? '',
                      hint: l10n.projectCustomerAndSiteFixed,
                    ),
                  ] else ...[
                    _Selector(
                      label: l10n.fieldRequiredLabel(l10n.projectFieldCustomer),
                      value: cliente?.displayName,
                      error: _customerId == null
                          ? l10n.projectFieldCustomerRequired
                          : null,
                      onTap: _elegirCliente,
                    ),
                    SizedBox(height: spacing.md),
                    _Selector(
                      label: l10n.fieldRequiredLabel(l10n.projectFieldSite),
                      value: sitio?.oneLine,
                      // Sin cliente el selector no tiene de dónde elegir, y decirlo
                      // es más útil que un campo muerto.
                      hint: _customerId == null
                          ? l10n.projectFieldSitePickCustomerFirst
                          : null,
                      // Material tapa el `helperText` cuando hay `errorText`, así
                      // que el mensaje accionable va como error: "este cliente no
                      // tiene propiedades, agregue una" sirve más que "falta elegir
                      // la propiedad" cuando no hay ninguna que elegir.
                      error: switch ((_customerId, _siteId, sitios.isEmpty)) {
                        (null, _, _) => null,
                        (_, _, true) => l10n.projectFieldSiteNoneForCustomer,
                        (_, null, false) => l10n.projectFieldSiteRequired,
                        _ => null,
                      },
                      onTap: _customerId == null ? null : _elegirSitio,
                    ),
                    // Se avisa, no se bloquea: guardar sin punto es válido.
                    if (sitio case final sitio? when !sitio.hasLocation) ...[
                      SizedBox(height: spacing.md),
                      SiteWithoutLocationNotice(site: sitio),
                    ],
                  ],
                  if (_esAlta) ...[
                    SizedBox(height: spacing.md),
                    _EstadoInicial(
                      value: _estado,
                      onChanged: (nuevo) => setState(() => _estado = nuevo),
                    ),
                  ],
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _tipoDeTrabajo,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.projectFieldServiceType,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _descripcion,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l10n.projectFieldDescription,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  Text(
                    l10n.projectDetailSectionWhen,
                    style: context.texts.titleSmall,
                  ),
                  SizedBox(height: spacing.md),
                  _Fecha(
                    label: l10n.projectFieldStartDate,
                    value: _inicio,
                    onPick: () => _elegirFecha(esInicio: true),
                    onClear: () => setState(() => _inicio = null),
                  ),
                  SizedBox(height: spacing.md),
                  _Fecha(
                    label: l10n.projectFieldTargetEndDate,
                    value: _finEstimado,
                    onPick: () => _elegirFecha(esInicio: false),
                    onClear: () => setState(() => _finEstimado = null),
                  ),
                  if (_esAlta) ...[
                    SizedBox(height: spacing.md),
                    // La visibilidad nace en etapas y se cambia aparte, en la
                    // ficha de la obra. Es un aviso y no un campo: suelto entre
                    // campos se leía como uno al que le faltan las opciones.
                    StatusChip(
                      // Verde y no gris: lo que dice es tranquilizador —nada
                      // sale sin que lo mande— y en gris se perdía.
                      tone: StatusTone.success,
                      label: l10n.projectVisibilityStages,
                      expand: true,
                      action: HelpButton(
                        title: l10n.projectVisibilityStagesHelpTitle,
                        body: l10n.projectVisibilityStagesHelpBody,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            FormFooter(
              child: FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: Text(l10n.actionSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El aviso de que la propiedad de la obra no tiene punto, con la salida de
/// fijarlo ahí mismo. Lo usan el alta y la tab Detalle.
///
/// Al volver del mapa el aviso desaparece solo: quien lo muestra lee la
/// propiedad del stream de Drift. Fijar escribe sobre la propiedad, que pide
/// `customers.write`: sin ese permiso se dice que falta, sin la acción.
class SiteWithoutLocationNotice extends ConsumerWidget {
  const SiteWithoutLocationNotice({super.key, required this.site});

  final SiteSummary site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sesion = ref.watch(sessionControllerProvider).value;
    final puedeFijar =
        sesion?.membership.permissions.contains('customers.write') ?? false;

    if (!puedeFijar) {
      return Text(
        l10n.projectSiteNoLocation,
        style: context.texts.bodyMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    return StatusChip(
      tone: StatusTone.warning,
      label: l10n.projectFieldSiteNoLocation,
      expand: true,
      action: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) => SiteLocationScreen(site: site),
          ),
        ),
        child: Text(l10n.siteLocationSet),
      ),
    );
  }
}

/// Un campo que se llena eligiendo, no escribiendo.
///
/// Usa `InputDecorator` para verse igual que los campos de texto de arriba: un
/// botón suelto se lee como otra clase de control y rompe la lectura del
/// formulario.
class _Selector extends StatelessWidget {
  const _Selector({
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.error,
  });

  final String label;
  final String? value;
  final String? hint;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final vacio = value == null || value!.isEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(spacing.radiusMd),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 2,
          // El error se muestra recién cuando se intentó guardar, no mientras se
          // llena: marcar en rojo algo que todavía no se tocó es hostil.
          errorText: error,
          enabled: onTap != null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                vacio ? '—' : value!,
                style: context.texts.bodyLarge?.copyWith(
                  color: vacio ? colors.onSurfaceVariant : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: spacing.sm),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Un dato que no se puede cambiar, con la misma forma que un campo.
///
/// No es un `_Selector` deshabilitado: un campo gris que no responde se lee como
/// que la app está trabada. Esto se lee como información.
class _SoloLectura extends StatelessWidget {
  const _SoloLectura({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        SizedBox(height: spacing.xs),
        Text(value.isEmpty ? '—' : value, style: context.texts.bodyLarge),
        if (hint != null) ...[
          SizedBox(height: spacing.xs),
          Text(
            hint!,
            style: context.texts.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// El estado con el que nace la obra.
///
/// En el alta no hay estado anterior, así que no hay escalera que respetar: se
/// ofrece todo el ciclo menos cancelada, que no tiene sentido al crear.
class _EstadoInicial extends StatelessWidget {
  const _EstadoInicial({required this.value, required this.onChanged});

  final ProjectStatus value;
  final ValueChanged<ProjectStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DropdownButtonFormField<ProjectStatus>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.fieldRequiredLabel(l10n.projectFieldStatus),
      ),
      items: [
        for (final estado in projectStatusLifecycle)
          if (estado != ProjectStatus.cancelled)
            DropdownMenuItem(value: estado, child: Text(estado.label(l10n))),
      ],
      onChanged: (nuevo) => nuevo == null ? null : onChanged(nuevo),
    );
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(context.spacing.radiusMd),
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                // Por la capa de i18n y nunca concatenando: el formato de fecha
                // no es el mismo en los dos idiomas.
                value == null
                    ? l10n.projectFieldDateNotSet
                    : MaterialLocalizations.of(context).formatFullDate(value!),
                style: context.texts.bodyLarge?.copyWith(
                  color: value == null ? colors.onSurfaceVariant : null,
                ),
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l10n.projectFieldDateClear,
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
              )
            else
              Icon(
                Icons.calendar_today_outlined,
                color: colors.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
