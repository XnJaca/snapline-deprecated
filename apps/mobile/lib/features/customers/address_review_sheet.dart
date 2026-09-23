import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import '../../l10n/app_localizations.dart';
import 'address_fields.dart';

/// Lo que el geocodificador rellenó, para revisarlo antes de seguir.
///
/// Misma forma que `confirm_sheet.dart`: hoja y no diálogo, dos botones a ancho
/// completo. Devuelve `true` si está bien y `false` si se quiere corregir; al
/// cerrarla de otra forma cuenta como «está bien», porque los campos siguen
/// editables igual.
Future<bool> showAddressReviewSheet(
  BuildContext context, {
  required AddressFormControllers controllers,
  required List<AddressPart> filled,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AddressReviewSheet(
      changes: [
        for (final parte in filled)
          AddressChange(
            part: parte,
            before: '',
            after: controllers.controllerOf(parte)?.text ?? '',
          ),
      ],
    ),
  );
  return ok ?? true;
}

/// La misma hoja, comparando lo guardado contra la dirección del punto nuevo.
///
/// Devuelve `true` solo si se pidió actualizar: acá hay algo que perder, así que
/// cerrarla de cualquier otra forma deja la dirección como estaba.
Future<bool> showAddressUpdateSheet(
  BuildContext context, {
  required List<AddressChange> changes,
}) async {
  final actualizar = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AddressReviewSheet(changes: changes, comparing: true),
  );
  return actualizar ?? false;
}

class AddressReviewSheet extends StatelessWidget {
  const AddressReviewSheet({
    super.key,
    required this.changes,
    this.comparing = false,
  });

  final List<AddressChange> changes;

  /// Comparando lo guardado contra lo nuevo, en vez de mostrando lo rellenado.
  final bool comparing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = context.spacing;
    final colors = context.colors;

    String etiqueta(AddressPart parte) => switch (parte) {
      AddressPart.line1 => l10n.addressLine1,
      AddressPart.city => l10n.addressCity,
      AddressPart.state => l10n.addressState,
      AddressPart.postalCode => l10n.addressPostalCode,
      AddressPart.country => l10n.addressCountry,
    };

    // La lista scrollea y los botones no: con cuatro campos en un teléfono
    // chico, el techo lo pone la pantalla y las salidas siguen a la vista.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.place_outlined, color: colors.primary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      comparing
                          ? l10n.siteAddressUpdateTitle
                          : l10n.siteAddressReviewTitle,
                      style: context.texts.titleLarge,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(
                comparing
                    ? l10n.siteAddressUpdateBody
                    : l10n.siteAddressReviewBody,
                style: context.texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              SizedBox(height: spacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final cambio in changes) ...[
                        Text(
                          etiqueta(cambio.part),
                          style: context.texts.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: spacing.xs),
                        // Lo anterior solo cuando había algo: un «antes: vacío»
                        // no dice nada.
                        if (cambio.before.isNotEmpty)
                          Text(
                            '${l10n.siteAddressBefore}: ${cambio.before}',
                            style: context.texts.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Text(
                          cambio.before.isEmpty
                              ? cambio.after
                              : '${l10n.siteAddressAfter}: ${cambio.after}',
                          style: context.texts.bodyLarge,
                        ),
                        SizedBox(height: spacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: Text(
                    comparing
                        ? l10n.siteAddressUpdateAccept
                        : l10n.siteAddressReviewAccept,
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    comparing
                        ? l10n.siteAddressUpdateKeep
                        : l10n.siteAddressReviewFix,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
