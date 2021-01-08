SET ECHO        OFF
SET FEEDBACK    6
SET HEADING     ON
SET LINESIZE    180
SET PAGESIZE    50000
SET TERMOUT     ON
SET TIMING      OFF
SET TRIMOUT     ON
SET TRIMSPOOL   ON
SET VERIFY      OFF
​
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
​
COLUMN disk_group_name        FORMAT a20                  HEAD 'Disk Group'
COLUMN DIR                    FORMAT a20                  HEAD 'Directory'
COLUMN full_path              FORMAT a75                  HEAD 'ASM File Name / Volume Name / Device Name'
COLUMN system_created         FORMAT a8                   HEAD 'System|Created?'
COLUMN bytes                  FORMAT 9,999,999,999,999    HEAD 'Bytes'
COLUMN space                  FORMAT 9,999,999,999,999    HEAD 'Space'
COLUMN RealSize_GB            FORMAT 999G999D99           HEAD 'Size (GB)'
COLUMN space_GB               FORMAT 999G999D99           HEAD 'Occ. Space (GB)'
COLUMN File_count             FORMAT 999G999              HEAD 'Files Number'
COLUMN type                   FORMAT a18                  HEAD 'File Type'
COLUMN redundancy             FORMAT a12                  HEAD 'Redundancy'
COLUMN striped                FORMAT a8                   HEAD 'Striped'
COLUMN creation_date          FORMAT a20                  HEAD 'Creation Date'
​
BREAK ON report ON disk_group_name ON dir SKIP 1
​
COMPUTE sum LABEL ""              OF RealSize_GB Space_GB ON dir
COMPUTE sum LABEL ""              OF RealSize_GB Space_GB ON disk_group_name
COMPUTE sum LABEL "Grand Total: " OF RealSize_GB Space_GB ON report
​
spool detailASM.lst
select 
   disk_group_name
  ,dir
  ,type
  ,count(*)                  File_count
  ,sum(bytes)/1024/1024/1024 RealSize_GB
  ,sum(space)/1024/1024/1024 Space_GB
from    (SELECT
            db_files.disk_group_name
          , NVL(db_files.type, '<DIRECTORY>')  type
          ,regexp_replace(SYS_CONNECT_BY_PATH(db_files.alias_name, '/'),'^/([^/]*)/.*','\1') dir
          , SYS_CONNECT_BY_PATH(db_files.alias_name, '/') full_path
          , db_files.bytes
          , db_files.space
          , db_files.creation_date
          , LPAD(db_files.system_created, 4) system_created
        FROM
            ( SELECT
                  g.name               disk_group_name
                , a.parent_index       pindex
                , a.name               alias_name
                , a.reference_index    rindex
                , a.system_created     system_created
                , f.bytes              bytes
                , f.space              space
                , f.type               type
                , TO_CHAR(f.creation_date, 'DD-MON-YYYY HH24:MI:SS')  creation_date
              FROM
                  v$asm_file f RIGHT OUTER JOIN v$asm_alias     a USING (group_number, file_number)
                                           JOIN v$asm_diskgroup g USING (group_number)
            ) db_files
        WHERE db_files.type IS NOT NULL
        START WITH (MOD(db_files.pindex, POWER(2, 24))) = 0
            CONNECT BY PRIOR db_files.rindex = db_files.pindex
        UNION
        SELECT
            volume_files.disk_group_name
          , NVL(volume_files.type, '<DIRECTORY>')  type
          ,regexp_replace(volume_files.volume_name,'^/([^/]*)/.*','\1')
          , volume_files.volume_name
          , volume_files.bytes
          , volume_files.space
          , volume_files.creation_date
          , null
        FROM
            ( SELECT
                  g.name               disk_group_name
                , v.volume_name        volume_name
                , v.volume_device       volume_device
                , f.bytes              bytes
                , f.space              space
                , f.type               type
                , TO_CHAR(f.creation_date, 'DD-MON-YYYY HH24:MI:SS')  creation_date
              FROM
                  v$asm_file f RIGHT OUTER JOIN v$asm_volume    v USING (group_number, file_number)
                                           JOIN v$asm_diskgroup g USING (group_number)
            ) volume_files
        WHERE volume_files.type IS NOT NULL)
group by
   disk_group_name
  ,dir
  ,type
order by
    decode (disk_group_name,'DATA','1','RECO','2','DAT2','3','Z'||disk_group_name)
   ,decode (substr(dir,1,3),'ILI','1'||dir,'FID','2'||dir,'IST','3'||dir,'ASM','4', 'Z'||dir)
   ,decode (type,'DATAFILE','1','TEMPFILE','2','ONLINELOG','3','ARCHIVELOG','4','5'||type)
