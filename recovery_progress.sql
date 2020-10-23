set lines 200
col type format a25
select START_TIME st_time,TYPE,ITEM,UNITS,SOFAR,to_char(timestamp,'DD-MON-YY hh24:mi:ss') scn_time from gv$recovery_progress;
