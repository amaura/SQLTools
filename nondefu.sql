set lines 200
set pages 200
col temporary_tablespace format a20
col default_tablespace format a20
col profile format a20

with s as (
select
owner,
round(sum(bytes)/1024/1024/1024,3) "GB"
from dba_segments
group by owner)
select
u.username,
u.default_tablespace,
u.temporary_tablespace,
u.profile,
s."GB"
from dba_users u, s
where
s.owner(+)=u.username
and
u.username not in
('ANONYMOUS',
'CTXSYS',
'DBSNMP',
'EXFSYS',
'LBACSYS',
'MDSYS',
'MGMT_VIEW',
'OLAPSYS',
'ORDDATA',
'OWBSYS',
'ORDPLUGINS',
'ORDSYS',
'OUTLN',
'SI_INFORMTN_SCHEMA',
'WK_TEST',
'WKSYS',
'WKPROXY',
'WMSYS',
'XDB',
'APEX_PUBLIC_USER',
'DIP',
'FLOWS_040100',
'FLOWS_FILES',
'MDDATA',
'ORACLE_OCM',
'SPATIAL_CSW_ADMIN_USR',
'SPATIAL_WFS_ADMIN_USR',
'XS$NULL',
'BI',
'HR',
'OE',
'PM',
'IX',
'SH',
'ODIM',
'ODIW',
'APPQOSSYS',
'APEX_030200',
'OWBSYS_AUDIT',
'SCOTT')
;
