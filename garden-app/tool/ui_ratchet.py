#!/usr/bin/env python3
"""Contador de deuda visual de garden-app: solo puede bajar.

Cuenta en lib/:
  - material_icons: usos de Icons.* de Material (reemplazar por GardenIcon)
  - emojis:         emojis en código (los iconos de interfaz son GardenIcon;
                    el emoji queda solo para lo que escribe la gente)
  - loose_curves:   Curves.* fuera de lib/theme/garden_motion.dart

Uso:
  python tool/ui_ratchet.py            # falla (exit 1) si algún número subió
  python tool/ui_ratchet.py --update   # baja la línea base tras migrar código

La línea base vive en tool/ui_ratchet_baseline.json. --update nunca la deja
subir: si un número aumentó, hay que migrar ese código a GardenIcon /
GardenMotion en vez de actualizar la base.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
BASELINE = Path(__file__).resolve().parent / "ui_ratchet_baseline.json"

# Archivos donde los emojis son datos, no iconos de interfaz.
EMOJI_ALLOW = {
    "lib/narrative/chat_event.dart",  # interpreta los mensajes del backend
    "lib/main_catalog.dart",          # ejemplos de mensajes en el catálogo
}
CURVES_ALLOW = {"lib/theme/garden_motion.dart"}

ICONS_RE = re.compile(r"(?<![\w.])Icons\.\w")
CURVES_RE = re.compile(r"(?<![\w.])Curves\.\w")


def is_emoji(cp: int) -> bool:
    return 0x1F300 <= cp <= 0x1FAFF or 0x2600 <= cp <= 0x27BF


def count() -> dict:
    totals = {"material_icons": 0, "emojis": 0, "loose_curves": 0}
    for f in sorted(LIB.rglob("*.dart")):
        rel = f.relative_to(ROOT).as_posix()
        text = f.read_text(encoding="utf-8")
        totals["material_icons"] += len(ICONS_RE.findall(text))
        if rel not in EMOJI_ALLOW:
            totals["emojis"] += sum(1 for ch in text if is_emoji(ord(ch)))
        if rel not in CURVES_ALLOW:
            totals["loose_curves"] += len(CURVES_RE.findall(text))
    return totals


def main() -> int:
    now = count()
    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else None

    if "--update" in sys.argv:
        if base:
            worse = {k: (base[k], v) for k, v in now.items() if v > base.get(k, v)}
            if worse:
                for k, (b, v) in worse.items():
                    print(f"✗ {k}: {b} → {v}. No se puede subir la línea base; migra ese código.")
                return 1
        BASELINE.write_text(json.dumps(now, indent=2) + "\n", encoding="utf-8")
        print("Línea base actualizada:", now)
        return 0

    if base is None:
        print("Falta tool/ui_ratchet_baseline.json. Créala con --update.")
        return 1

    failed = False
    for k, v in now.items():
        b = base.get(k, v)
        mark = "✗" if v > b else "✓"
        hint = ""
        if v > b:
            failed = True
            hint = {
                "material_icons": "  → usa GardenIcon(GIcon.…) de lib/design/garden_icons.dart",
                "emojis": "  → usa GardenIcon o Brote en lugar de emojis",
                "loose_curves": "  → usa GardenMotion.enter / exit / pop",
            }[k]
        print(f"{mark} {k}: {v} (base {b}){hint}")
    if not failed and any(now[k] < base.get(k, now[k]) for k in now):
        print("Bajaste deuda visual. Corre `python tool/ui_ratchet.py --update` y commitea la base.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
