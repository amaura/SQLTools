set lines 200 pages 200
col name format a20
col key_id format a40
col keystore_type format a30



select p.name,
e.KEY_ID,
e.KEYSTORE_TYPE,
to_char(e.creation_time,'YYYY-MM-DD HH24:MI:SS TZR') as creation_time,
to_char(e.activation_time,'YYYY-MM-DD HH24:MI:SS TZR') as activation_time
from v$pdbs p left join v$encryption_keys e 
on p.con_id=e.con_id;
