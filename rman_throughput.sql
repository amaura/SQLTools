SET HEAD OFF
SELECT 'Throughput: '||
       ROUND(SUM(v.value/1024/1024),1) || ' Meg so far @ ' ||
       ROUND(SUM(v.value     /1024/1024)/NVL((SELECT MIN(elapsed_seconds)
            FROM gv$session_longops
            WHERE opname          LIKE 'RMAN: aggregate input'
              AND sofar           != TOTALWORK
              AND elapsed_seconds IS NOT NULL
       ),SUM(v.value     /1024/1024)),2) || ' Meg/sec'
 FROM gv$sesstat v, v$statname n, gv$session s
WHERE v.statistic# = n.statistic#
  AND n.name       = 'physical write total bytes'
  AND v.sid        = s.sid
  AND v.inst_id    = s.inst_id
  AND s.program LIKE 'rman@%'
GROUP BY n.name
/
SET HEAD ON
