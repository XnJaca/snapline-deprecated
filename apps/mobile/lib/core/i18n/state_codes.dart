import 'package:phone_form_field/phone_form_field.dart';

import 'supported_countries.dart';

/// El código de dos letras de un estado o provincia, para los países donde la
/// dirección lo exige así.
///
/// Existe porque el geocodificador de Android devuelve «Maryland» y el de iOS
/// «MD», y el formulario acepta solo el código en Estados Unidos y Canadá. Es
/// dato de referencia, no dominio: la regla de qué países usan código vive en
/// [SupportedCountries].
abstract final class StateCodes {
  /// Devuelve el código si lo hay; si ya venía como código, lo normaliza; si el
  /// país no usa código o el nombre no se reconoce, devuelve lo recibido.
  static String toCode(IsoCode country, String value) {
    final limpio = value.trim();
    if (!SupportedCountries.esCodigoDeDosLetras(country)) return limpio;

    final tabla = switch (country) {
      IsoCode.US => _us,
      IsoCode.CA => _ca,
      _ => const <String, String>{},
    };
    if (limpio.length == 2 && tabla.containsValue(limpio.toUpperCase())) {
      return limpio.toUpperCase();
    }
    return tabla[limpio.toLowerCase()] ?? limpio;
  }

  static const _us = {
    'alabama': 'AL',
    'alaska': 'AK',
    'arizona': 'AZ',
    'arkansas': 'AR',
    'california': 'CA',
    'colorado': 'CO',
    'connecticut': 'CT',
    'delaware': 'DE',
    'district of columbia': 'DC',
    'washington, d.c.': 'DC',
    'washington dc': 'DC',
    'florida': 'FL',
    'georgia': 'GA',
    'hawaii': 'HI',
    'idaho': 'ID',
    'illinois': 'IL',
    'indiana': 'IN',
    'iowa': 'IA',
    'kansas': 'KS',
    'kentucky': 'KY',
    'louisiana': 'LA',
    'maine': 'ME',
    'maryland': 'MD',
    'massachusetts': 'MA',
    'michigan': 'MI',
    'minnesota': 'MN',
    'mississippi': 'MS',
    'missouri': 'MO',
    'montana': 'MT',
    'nebraska': 'NE',
    'nevada': 'NV',
    'new hampshire': 'NH',
    'new jersey': 'NJ',
    'new mexico': 'NM',
    'new york': 'NY',
    'north carolina': 'NC',
    'north dakota': 'ND',
    'ohio': 'OH',
    'oklahoma': 'OK',
    'oregon': 'OR',
    'pennsylvania': 'PA',
    'rhode island': 'RI',
    'south carolina': 'SC',
    'south dakota': 'SD',
    'tennessee': 'TN',
    'texas': 'TX',
    'utah': 'UT',
    'vermont': 'VT',
    'virginia': 'VA',
    'washington': 'WA',
    'west virginia': 'WV',
    'wisconsin': 'WI',
    'wyoming': 'WY',
    'puerto rico': 'PR',
  };

  static const _ca = {
    'alberta': 'AB',
    'british columbia': 'BC',
    'colombie-britannique': 'BC',
    'manitoba': 'MB',
    'new brunswick': 'NB',
    'nouveau-brunswick': 'NB',
    'newfoundland and labrador': 'NL',
    'terre-neuve-et-labrador': 'NL',
    'nova scotia': 'NS',
    'nouvelle-écosse': 'NS',
    'ontario': 'ON',
    'prince edward island': 'PE',
    'île-du-prince-édouard': 'PE',
    'quebec': 'QC',
    'québec': 'QC',
    'saskatchewan': 'SK',
    'northwest territories': 'NT',
    'territoires du nord-ouest': 'NT',
    'nunavut': 'NU',
    'yukon': 'YT',
  };
}
