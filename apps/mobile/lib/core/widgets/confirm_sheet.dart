import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Confirmar algo que no tiene vuelta atrás.
///
/// **Hoja y no diálogo**, con las dos acciones como botones de ancho completo:
/// un `TextButton` abajo a la derecha de un `AlertDialog` no se lee como botón
/// —es texto suelto— y acá se toca con guantes. Las dos opciones tienen que
/// verse como opciones.
///
/// La destructiva va **arriba y en rojo**, la salida abajo con borde. Arriba
/// porque es la que se vino a hacer; en rojo porque el color es lo que dice que
/// no hay deshacer.
Future<bool> confirmarAccionDestructiva(
  BuildContext context, {
  required String titulo,
  required String cuerpo,
  required String confirmar,
  required String cancelar,
  IconData icono = Icons.delete_outline,
}) => _preguntar(
  context,
  titulo: titulo,
  cuerpo: cuerpo,
  confirmar: confirmar,
  cancelar: cancelar,
  icono: icono,
  destructiva: true,
);

/// Confirmar algo que sí se puede deshacer, pero que sale de la empresa.
///
/// Mostrarle una foto al cliente o publicarla no se revierte del todo: se puede
/// bajar el nivel después, no des-verla. Misma forma que la destructiva —dos
/// botones de ancho completo— sin el rojo, que está reservado para lo que no
/// tiene vuelta.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String cuerpo,
  required String confirmar,
  required String cancelar,
  required IconData icono,
}) => _preguntar(
  context,
  titulo: titulo,
  cuerpo: cuerpo,
  confirmar: confirmar,
  cancelar: cancelar,
  icono: icono,
  destructiva: false,
);

Future<bool> _preguntar(
  BuildContext context, {
  required String titulo,
  required String cuerpo,
  required String confirmar,
  required String cancelar,
  required IconData icono,
  required bool destructiva,
}) async {
  final confirmado = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _Confirmacion(
      titulo: titulo,
      cuerpo: cuerpo,
      confirmar: confirmar,
      cancelar: cancelar,
      icono: icono,
      destructiva: destructiva,
    ),
  );
  return confirmado ?? false;
}

class _Confirmacion extends StatelessWidget {
  const _Confirmacion({
    required this.titulo,
    required this.cuerpo,
    required this.confirmar,
    required this.cancelar,
    required this.icono,
    required this.destructiva,
  });

  final String titulo;
  final String cuerpo;
  final String confirmar;
  final String cancelar;
  final IconData icono;
  final bool destructiva;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;

    // El cuerpo scrollea y los botones no: un motivo largo en un teléfono
    // chico desbordaba la hoja, y las dos salidas tienen que quedar a la vista.
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
                  Icon(
                    icono,
                    color: destructiva ? colors.error : colors.primary,
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(titulo, style: context.texts.titleLarge),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    cuerpo,
                    style: context.texts.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(icono),
                  label: Text(confirmar),
                  style: destructiva
                      ? FilledButton.styleFrom(
                          backgroundColor: colors.error,
                          foregroundColor: colors.onError,
                        )
                      : null,
                ),
              ),
              SizedBox(height: spacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(cancelar),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
