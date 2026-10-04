import 'package:flutter/widgets.dart';

// ── MOVIMIENTO GARDEN ──────────────────────────────────────────────────────
// Única fuente de duraciones y curvas de la app. Igual que los colores salen
// de GardenColors, todo movimiento sale de acá — no inventar curvas sueltas.
//
// Duraciones:
//   instant     100 ms — press de botón, check de casilla
//   quick       180 ms — iconos de la barra, chips, tooltips
//   standard    280 ms — cambio de página, hojas inferiores
//   expressive  450 ms — cambio de estado de una reserva, foto que llega
//   celebrate   900 ms — solo 3 momentos: reserva confirmada, paseo
//                        terminado, primer retiro
//
// Curvas:
//   enter  — algo aparece
//   exit   — algo se va
//   pop    — algo cambia de estado (reemplaza a Curves.elasticOut)
//   move   — algo se desplaza o respira (scroll, pulso "en vivo")
//
// Reglas:
//   • Los iconos se animan al CAMBIAR de estado, una vez. Lo único que puede
//     quedar en bucle es el indicador "en vivo" y el icono del servicio
//     mientras está en curso.
//   • Si el sistema pide menos movimiento (MediaQuery.disableAnimations), usar
//     GardenMotion.resolve(): devuelve Duration.zero y el widget salta directo
//     al estado final.
class GardenMotion {
  static const instant    = Duration(milliseconds: 100);
  static const quick      = Duration(milliseconds: 180);
  static const standard   = Duration(milliseconds: 280);
  static const expressive = Duration(milliseconds: 450);
  static const celebrate  = Duration(milliseconds: 900);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit  = Curves.easeInCubic;
  static const Curve pop   = Curves.easeOutBack;
  static const Curve move  = Curves.easeInOut;

  /// True si el sistema operativo pidió reducir animaciones.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Devuelve [d], o Duration.zero si el usuario pidió menos movimiento.
  static Duration resolve(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  GardenMotion._();
}
