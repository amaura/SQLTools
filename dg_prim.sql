set lines 200
set pages 200
col dest_name format a20
col status format a10
col gap_status format a20
col error format a80
select
inst_id,
dest_name,
status,
protection_mode,
ARCHIVED_SEQ#,
APPLIED_SEQ#,
gap_status,
error
from gv$archive_dest_status
where status <> 'INACTIVE'
order by 1,2;
