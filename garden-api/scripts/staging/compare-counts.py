"""Compara las filas por tabla de producción (al respaldar) con las de staging (al restaurar).

Producción sigue recibiendo escrituras mientras corre pg_dump, así que se tolera una diferencia
chica (20 filas o 1 %). Una tabla que falta o una diferencia grande = el respaldo no sirve.
Uso: python3 compare-counts.py prod-counts.txt staging-counts.txt
"""
import sys


def load(path):
    out = {}
    for line in open(path, encoding='utf-8'):
        line = line.strip()
        if '|' in line:
            name, n = line.rsplit('|', 1)
            out[name] = int(n)
    return out


prod, staging = load(sys.argv[1]), load(sys.argv[2])
bad = []
for table, n in prod.items():
    if table not in staging:
        bad.append(f'{table}: falta en el respaldo restaurado')
        continue
    diff = abs(staging[table] - n)
    if diff > max(20, n // 100):
        bad.append(f'{table}: producción {n}, restaurado {staging[table]}')
if not prod:
    bad.append('no se leyó ninguna tabla de producción')
for b in bad:
    print(f'::error::{b}')
print(f'{len(prod)} tablas comparadas, {len(bad)} con problemas.')
sys.exit(1 if bad else 0)
