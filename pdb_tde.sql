set lines 200 pages 200
col name format a20
col key_id format a40
col keystore_type format a30

select p.name,e.KEY_ID,e.KEYSTORE_TYPE from v$pdbs p left join v$encryption_keys e on p.con_id=e.con_id;
