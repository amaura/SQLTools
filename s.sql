set lines 200
set pages 200
col machine format a30
select sid,
serial#,
program,
machine,
status,
wait_class
from v$session
where type <> 'BACKGROUND';
