set lines 200
col type format a25
select START_TIME,TYPE,ITEM,UNITS,SOFAR,to_char(timestamp,'DD-MON-YY hh24:mi:ss') from gv$recovery_progress;
