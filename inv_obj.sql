set pages 200
set lines 200

col owner format a20
col object_type format a20
col object_name format a60

select
owner,
object_type,
object_name
from
dba_objects
where
status <> 'VALID';
