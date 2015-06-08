set lines 200
set pages 200
col ACTION_TIME format a40
col COMMENTS format a40
select ACTION_TIME,version,COMMENTS from dba_registry_history;
