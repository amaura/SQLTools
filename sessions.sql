set lines 200
set pages 200
col inst_id format a3
col machine format a20
col program format a20
col wait_class format a20
select 
inst_id,
sid,
serial#,
substr(machine,0,20) "MACHINE",
substr(program,0,20) "PROGRAM",
status,
wait_class
from gv$session
where type <> 'BACKGROUND';
