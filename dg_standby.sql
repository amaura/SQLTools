set pages 50
SELECT 
PROCESS, 
STATUS, 
THREAD#, 
SEQUENCE#, 
BLOCK#, 
BLOCKS 
FROM GV$MANAGED_STANDBY;

