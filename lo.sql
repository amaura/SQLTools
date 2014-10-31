-- Session Long Operations
set pages 200 lines 200
col opname format a30
col message format a80
col "%" format 00.00
SET UNDERLINE =
select opname,
round((sofar/TOTALWORK)*100,2) "%",
time_remaining time,
message
from gv$session_longops where 
sofar <> TOTALWORK 
and TOTALWORK <> 0
order by 1;
