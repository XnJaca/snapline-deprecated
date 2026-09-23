import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/labeled_value.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_chip.dart';
import '../../api/models/project_status.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../l10n/app_localizations.dart';
import 'project_form_screen.dart';
import 'project_status_display.dart';
import 'project_transitions.dart';

/// La tab de Detalle de una obra: qué trabajo es, de quién, dónde y cuándo.
///
/// Es también de donde se cambia el estado, porque es el único lugar que ya tiene
/// el contexto de en qué estado está.
class ProjectDetailsTab extends ConsumerWidget {
  const ProjectDetailsTab({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final obra = ref.watch(projectDetailProvider(projectId)).value;

    if (obra == null) return const SizedBox.shrink();

    return ListView(
      key: PageStorageKey<String>('$projectId.details'),
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.lg,
        spacing.lg,
        spacing.xxl,
      ),
      children: [
        _CambiarEstado(project: obra),
        SizedBox(height: spacing.lg),
        SectionHeader(
          title: l10n.projectDetailSectionWhat,
          action: TextButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.projectDetailEdit),
            onPressed: () =>
                context.push(ProjectFormScreen.editRoute(projectId)),
          ),
        ),
        SizedBox(height: spacing.md),
        _Ficha(
          children: [
            LabeledValue(label: l10n.projectFieldName, value: obra.name),
            LabeledValue(
              label: l10n.projectFieldServiceType,
              value: obra.serviceType,
            ),
            LabeledValue(
              label: l10n.projectFieldDescription,
              value: obra.description,
            ),
          ],
        ),
        SizedBox(height: spacing.lg),
        SectionHeader(title: l10n.projectDetailSectionWho),
        SizedBox(height: spacing.md),
        _Ficha(
          children: [
            LabeledValue(
              label: l10n.projectFieldCustomer,
              value: obra.customerName,
            ),
            LabeledValue(label: l10n.projectFieldSite, value: obra.site),
            if (obra.siteSummary case final sitio?)
              _PuntoDeLaPropiedad(site: sitio),
          ],
        ),
        SizedBox(height: spacing.lg),
        SectionHeader(title: l10n.projectFieldClientVisibility),
        SizedBox(height: spacing.md),
        _ModoDelCliente(project: obra),
        SizedBox(height: spacing.lg),
        SectionHeader(title: l10n.projectDetailSectionWhen),
        SizedBox(height: spacing.md),
        _Ficha(
          children: [
            _Fecha(label: l10n.projectFieldStartDate, value: obra.startDate),
            _Fecha(
              label: l10n.projectFieldTargetEndDate,
              value: obra.targetEndDate,
            ),
          ],
        ),
      ],
    );
  }
}

/// Si la propiedad de la obra tiene punto, y la salida de fijarlo si no.
class _PuntoDeLaPropiedad extends StatelessWidget {
  const _PuntoDeLaPropiedad({required this.site});

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;

    if (site.hasLocation) {
      return LabeledValue(
        label: l10n.siteLocationSection,
        value: l10n.siteLocationCoords(
          site.lat!.toStringAsFixed(5),
          site.lng!.toStringAsFixed(5),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.siteLocationSection,
            style: context.texts.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.xs),
          SiteWithoutLocationNotice(site: site),
        ],
      ),
    );
  }
}

/// Qué ve el cliente final de esta obra.
///
/// Arranca en etapas y pasar a avance es una acción explícita
/// (`docs/domain/proyecto.md`). Vive acá y no dentro de la hoja de nota: es una
/// propiedad de la obra, no de lo que se está escribiendo.
class _ModoDelCliente extends ConsumerWidget {
  const _ModoDelCliente({required this.project});

  final ProjectDetail project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;
    final enEtapas = project.clientVisibilityMode == 'STAGES';

    return _Ficha(
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'STAGES',
              label: Text(l10n.projectVisibilityModeStages),
            ),
            ButtonSegment(
              value: 'PROGRESS',
              label: Text(l10n.projectVisibilityModeProgress),
            ),
          ],
          selected: {project.clientVisibilityMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => ref
              .read(projectRepositoryProvider)
              .cambiarModoDeCliente(project.id, s.first),
        ),
        if (enEtapas)
          Padding(
            padding: EdgeInsets.only(top: spacing.sm),
            child: Text(
              l10n.projectVisibilityModeHint,
              style: context.texts.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// El estado de la obra y las transiciones que se pueden hacer desde acá.
///
/// **Se ofrecen solo las válidas** —`nextStatusesFor`, la misma tabla que valida el
/// servidor— y no todas con una advertencia después: un botón que va a fallar no
/// debería estar dibujado.
class _CambiarEstado extends ConsumerWidget {
  const _CambiarEstado({required this.project});

  final ProjectDetail project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;
    final posibles = nextStatusesFor(project.status);

    return _Ficha(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.projectChangeStatusFrom(project.status.label(l10n)),
                style: context.texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            StatusChip(
              tone: project.status.tone,
              label: project.status.label(l10n),
              icon: project.status.icon,
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        if (posibles.isEmpty)
          // Terminada o cancelada: no se ofrece nada en vez de un selector que no
          // hace nada.
          Text(
            l10n.projectStatusTerminal,
            style: context.texts.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else ...[
          Text(l10n.projectChangeStatus, style: context.texts.titleSmall),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              for (final destino in posibles)
                OutlinedButton.icon(
                  icon: Icon(destino.icon, size: spacing.lg),
                  label: Text(destino.label(l10n)),
                  onPressed: () => _cambiar(context, ref, project.id, destino),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Los estados de los que no se vuelve. Tocarlos pide confirmación.
const _terminales = [ProjectStatus.completed, ProjectStatus.cancelled];

/// Cambia el estado, pidiendo confirmación si no hay vuelta atrás.
///
/// Terminar y cancelar son irreversibles por decisión del dominio —si se pudiera
/// reabrir, "terminada" dejaría de ser confiable para el reporte y para
/// publicar—, así que un toque por error deja la obra trabada. Las demás
/// transiciones no preguntan: pausar y reanudar se hacen a cada rato y un diálogo
/// en el medio sería un estorbo.
Future<void> _cambiar(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  ProjectStatus destino,
) async {
  final l10n = AppLocalizations.of(context);

  if (_terminales.contains(destino)) {
    // Hoja y no diálogo, como toda confirmación de la app. El rojo queda para
    // cancelar: terminar es igual de final, pero es el cierre bueno del
    // trabajo y no se lee como una advertencia.
    final cancela = destino == ProjectStatus.cancelled;
    final titulo = l10n.projectConfirmTitle(destino.label(l10n));
    final cuerpo = cancela
        ? l10n.projectConfirmCancelledBody
        : l10n.projectConfirmCompletedBody;

    final bool confirmado;
    if (cancela) {
      confirmado = await confirmarAccionDestructiva(
        context,
        titulo: titulo,
        cuerpo: cuerpo,
        confirmar: l10n.projectConfirmAccept,
        cancelar: l10n.actionCancel,
        icono: Icons.cancel_outlined,
      );
    } else {
      confirmado = await confirmarAccion(
        context,
        titulo: titulo,
        cuerpo: cuerpo,
        confirmar: l10n.projectConfirmAccept,
        cancelar: l10n.actionCancel,
        icono: Icons.check_circle_outline,
      );
    }
    if (!confirmado) return;
  }

  await ref.read(projectRepositoryProvider).changeStatus(projectId, destino);
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.outline),
        borderRadius: BorderRadius.circular(spacing.radiusMd),
      ),
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({required this.label, required this.value});

  final String label;
  final DateTime? value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return LabeledValue(
      label: label,
      // Por la capa de i18n: el formato no es el mismo en los dos idiomas.
      value: value == null
          ? null
          : MaterialLocalizations.of(context).formatFullDate(value!),
      // Una fecha sin definir sí se muestra: que la obra no tenga fecha de fin es
      // información, no un campo vacío.
      emptyPlaceholder: l10n.projectFieldDateNotSet,
    );
  }
}
