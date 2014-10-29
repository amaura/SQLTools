set lines 200
set pages 200

select sid,
serial#,
sql_id,
prev_sql_id,
event
from v$session
where type <> 'BACKGROUND';
