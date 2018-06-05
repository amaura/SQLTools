set lines 200
col "TOTAL GB" format 99999.9
col "USED GB" format 99999.9
col "RECLAIMABLE GB" format 99999.9
select
space_limit/1024/1024/1024 "TOTAL GB",
SPACE_USED/1024/1024/1024 "USED GB",
SPACE_RECLAIMABLE/1024/1024/1024 "RECLAIMABLE GB" 
from 
v$recovery_file_dest;
