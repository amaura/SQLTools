set lines 170
set pages 10000
col event format a40
col sample_time format a40
select to_char(sample_time,'DD-MON-YY HH24:MI:SS'),
SESSION_ID,
SESSION_SERIAL#,
SQL_ID,
BLOCKING_SESSION,
BLOCKING_SESSION_SERIAL#,
BLOCKING_SESSION_STATUS,
EVENT from 
dba_hist_active_sess_history 
where to_char(sample_time,'DD-MM-YY HH24:MI:SS') between '15-06-21 10:02:00' and '15-06-21 10:10:00 PM'  
and BLOCKING_SESSION is not null order by 1 ;
