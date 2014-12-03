set lines 200
set pages 200
col machine format a30
col wait_class format a20
select 
inst_id,
sid,
serial#,
program,
machine,
status,
wait_class
from gv$session
where type <> 'BACKGROUND';
