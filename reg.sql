-- reg.sql Show DB registry components
set pages 200
set lines 200

col comp_name format a60

select
comp_name,
version,
status
from dba_registry;
