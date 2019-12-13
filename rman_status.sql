col "DEV" format a4
select
START_TIME,
END_TIME,
--INPUT_BYTES/1024/1024/1024 "IN GB",
--OUTPUT_BYTES/1024/1024/1024 "OUT GB",
INPUT_BYTES_DISPLAY,
OUTPUT_BYTES_DISPLAY,
SUBSTR(OUTPUT_DEVICE_TYPE,1,4)  "DEV",
STATUS,
INPUT_TYPE,
TIME_TAKEN_DISPLAY
from 
V$RMAN_BACKUP_JOB_DETAILS;
