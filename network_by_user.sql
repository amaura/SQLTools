select
s.username,
decode(t.statistic#,1090,'bytes sent',1091,'bytes received') "STAT",
t.value/1024/1024 "MB"
from gv$sesstat t, gv$session s 
where
(t.STATISTIC#=1090 or t.STATISTIC#=1091) and 
t.sid=s.sid and
s.type <> 'BACKGROUND'
order by 3 desc;
