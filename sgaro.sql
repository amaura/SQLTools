set lines 200
set pages 200
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
col component format a30
select
COMPONENT,
INITIAL_SIZE,
TARGET_SIZE,
START_TIME
from v$SGA_RESIZE_OPS;
