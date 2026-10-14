/// Saludo según la hora local del teléfono: "Buen día" (5:00–11:59),
/// "Buenas tardes" (12:00–18:59) y "Buenas noches" (19:00–4:59).
String timeGreeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 5 && h < 12) return 'Buen día';
  if (h >= 12 && h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}
