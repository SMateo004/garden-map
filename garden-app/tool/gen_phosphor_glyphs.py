#!/usr/bin/env python3
"""Regenera lib/design/phosphor_glyphs.dart con los iconos usados en garden_icons.dart.

Los códigos salen del código fuente de phosphor_flutter 2.1.0 (no se usa como
dependencia porque no compila con Flutter 3.44). Para tenerlo en el caché:

  dart pub cache add phosphor_flutter --version 2.1.0
  python tool/gen_phosphor_glyphs.py

Para sumar un icono: agregar `nombre(Ph.nombrePhosphor)` en GIcon y correr esto.
Nombres en https://phosphoricons.com (en camelCase: calendar-dots → calendarDots).
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
cache = Path(os.environ.get("PUB_CACHE") or (
    Path(os.environ["LOCALAPPDATA"]) / "Pub" / "Cache" if os.name == "nt" else Path.home() / ".pub-cache"))
src = cache / "hosted" / "pub.dev" / "phosphor_flutter-2.1.0" / "lib" / "src"
if not src.exists():
    sys.exit(f"No encuentro {src}. Corre: dart pub cache add phosphor_flutter --version 2.1.0")

reg = (src / "phosphor_icons_regular.dart").read_text(encoding="utf-8")
duo = (src / "phosphor_icons_duotone.dart").read_text(encoding="utf-8")
icons = (ROOT / "lib" / "design" / "garden_icons.dart").read_text(encoding="utf-8")
names = sorted(set(re.findall(r"\(Ph\.(\w+)\)", icons)))

out = [
    "// GENERADO por tool/gen_phosphor_glyphs.py — no editar a mano.",
    "// Phosphor Icons (MIT, ver assets/fonts/phosphor/LICENSE). Fuentes en",
    "// assets/fonts/phosphor/*.ttf, códigos de phosphor_flutter 2.1.0.",
    "import 'package:flutter/widgets.dart';",
    "",
    "/// Glifo de Phosphor en sus dos estilos: regular (línea) y duotono",
    "/// (trazo [duoPrimary] + relleno suave [duoSecondary]).",
    "class PhGlyph {",
    "  final IconData regular;",
    "  final IconData duoPrimary;",
    "  final IconData duoSecondary;",
    "  const PhGlyph(this.regular, this.duoPrimary, this.duoSecondary);",
    "}",
    "",
    "const _reg = 'PhosphorRegular';",
    "const _duo = 'PhosphorDuotone';",
    "",
    "class Ph {",
]
missing = []
for n in names:
    r = re.search(r"static const %s = PhosphorFlatIconData\((0x[0-9a-f]+)" % n, reg)
    d = re.search(r"static const %s = PhosphorDuotoneIconData\(\s*(0x[0-9a-f]+),\s*PhosphorIconData\((0x[0-9a-f]+)" % n, duo)
    if not (r and d):
        missing.append(n)
        continue
    out.append(
        f"  static const {n} = PhGlyph(IconData({r.group(1)}, fontFamily: _reg), "
        f"IconData({d.group(1)}, fontFamily: _duo), IconData({d.group(2)}, fontFamily: _duo));")
if missing:
    sys.exit("No existen en Phosphor: " + ", ".join(missing))
out += ["", "  Ph._();", "}", ""]
(ROOT / "lib" / "design" / "phosphor_glyphs.dart").write_text("\n".join(out), encoding="utf-8")
print(f"{len(names)} glifos escritos")
