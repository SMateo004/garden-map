-- Filas por tabla (una línea "tabla|filas"), para comprobar que un respaldo restaurado está
-- completo. Lo usa .github/workflows/db-backup.yml en producción y en staging.
SELECT table_name || '|' || (xpath('/row/c/text()',
         query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
