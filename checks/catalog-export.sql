-- Read-only PostgreSQL 18 partial schema snapshot. Apache-2.0.
-- psql -XAt -v ON_ERROR_STOP=1 -v schema=public -v source=LABEL -v snapshot_id=ID -f checks/catalog-export.sql
-- Run against the intended database/role; provenance labels are caller claims.
SELECT json_build_object(
  'format','moonddl.catalog.v1',
  'postgres',current_setting('server_version_num')::int / 10000,
  'source',:'source','snapshot_id',:'snapshot_id',
  'captured_at',to_char(statement_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'tables',COALESCE((SELECT json_agg(json_build_object(
    'schema',n.nspname,'name',c.relname,'kind',CASE c.relkind WHEN 'p' THEN 'partitioned' ELSE 'ordinary' END,
    'columns',COALESCE((SELECT json_agg(json_build_object('name',a.attname,'data_type',pg_catalog.format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum)
      FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::json),
    'indexes',COALESCE((SELECT json_agg(json_build_object(
      'name',ic.relname,'unique',i.indisunique,'valid',i.indisvalid,'ready',i.indisready,
      'live',i.indislive,'immediate',i.indimmediate,'btree',am.amname='btree',
      'partial',i.indpred IS NOT NULL,'expression',i.indexprs IS NOT NULL,
      'default_order',NOT EXISTS(SELECT 1 FROM generate_series(0,i.indnkeyatts-1) k
        LEFT JOIN pg_catalog.pg_opclass op ON op.oid=i.indclass[k]
        LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum=i.indkey[k]
        WHERE i.indoption[k]<>0 OR NOT op.opcdefault OR i.indcollation[k]<>a.attcollation),
      'owned',EXISTS(SELECT 1 FROM pg_catalog.pg_constraint con WHERE con.conindid=i.indexrelid AND con.contype IN ('p','u','x')),
      'keys',COALESCE((SELECT json_agg(a.attname ORDER BY k) FROM generate_series(0,i.indnkeyatts-1) k
        JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum=i.indkey[k] AND a.attnum>0),'[]'::json)
    ) ORDER BY ic.relname) FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ic ON ic.oid=i.indexrelid
      JOIN pg_catalog.pg_am am ON am.oid=ic.relam WHERE i.indrelid=c.oid),'[]'::json)
  ) ORDER BY c.relname) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname=:'schema' AND c.relkind IN ('r','p')),'[]'::json)
);
