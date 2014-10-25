-- s.sql List non background sessions
set lines 200
set pages 200

select
a.sql_id,
b.sql_text
from v$session a, v$sql b
where a.sid=&1
and a.serial#=&2
and a.sql_id=b.sql_id;
