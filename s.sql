set lines 200
set pages 200
col machine format a30
col wait_class format a20
select sid,
serial#,
program,
machine,
status,
wait_class
from v$session
where type <> 'BACKGROUND';
