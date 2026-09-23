import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Si el mapa se ve en satélite en **este** dispositivo.
///
/// Preferencia de interfaz, no credencial: va a `SharedPreferences`, igual que
/// el tema y el idioma.
class MapTypeStore {
  const MapTypeStore(this._prefs);

  static const key = 'snapline.mapSatellite';

  final SharedPreferencesAsync _prefs;

  Future<bool> readSatellite() async {
    try {
      return await _prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> writeSatellite(bool value) async {
    // Perder la preferencia no puede impedir que el mapa cambie en pantalla.
    try {
      await _prefs.setBool(key, value);
    } catch (_) {}
  }
}

final mapTypeStoreProvider = Provider<MapTypeStore>((ref) {
  return MapTypeStore(SharedPreferencesAsync());
});

/// Arranca en mapa y carga lo guardado apenas puede: la pantalla del mapa no
/// está en el primer frame de la app, así que no hace falta leerlo en `main`.
class SatelliteMapNotifier extends Notifier<bool> {
  /// Si ya hubo una elección en esta sesión. La lectura del disco es asíncrona
  /// y puede resolver después de que alguien tocó el botón: sin esto, le
  /// pisaría su elección con el valor viejo.
  bool _elegido = false;

  @override
  bool build() {
    _elegido = false;
    ref.read(mapTypeStoreProvider).readSatellite().then((guardado) {
      // `ref.mounted` por si el provider se desecha con la lectura en vuelo:
      // hoy no pasa, pero escribir `state` ahí lanzaría.
      if (ref.mounted && !_elegido && guardado) state = true;
    });
    return false;
  }

  void toggle() {
    _elegido = true;
    state = !state;
    // No se espera: lo que la persona pidió ya pasó en pantalla.
    ref.read(mapTypeStoreProvider).writeSatellite(state);
  }
}

final satelliteMapProvider = NotifierProvider<SatelliteMapNotifier, bool>(
  SatelliteMapNotifier.new,
);
