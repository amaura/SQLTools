set pages 200
set lines 200

col owner format a30
col object_name format a100

select
owner,
object_name
from
dba_objects
where
status <> 'VALID';
