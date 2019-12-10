set lines 200
col username format a30
col "PDB NAME" format a20
col profile format a30

select p.NAME "PDB NAME",u.USERNAME,u.PROFILE,u.LOCK_DATE,u.EXPIRY_DATE
from v$pdbs p, cdb_users u
where 
p.con_id=u.con_id
and username not in 
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
'SCOTT',
'TSMSYS');
