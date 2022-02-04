column c0 heading "Owner"                                    format a12
column c1 heading "Object|Name"                              format a30
column c2 heading "Object|Type"                              format a8
column c3 heading "Number of|Blocks in|Buffer|Cache"         format 99,999,999
column c4 heading "Percentage|of object|blocks in|Buffer"    format 999
column c5 heading "Buffer|Pool"                              format a7
column c6 heading "Block|Size"                               format 99,999

select
   t1.owner                                          c0,
   object_name                                       c1,
   case when object_type = 'TABLE PARTITION' then 'TAB PART'
        when object_type = 'INDEX PARTITION' then 'IDX PART'
        else object_type end c2,
   sum(num_blocks)                                     c3,
   (sum(num_blocks)/greatest(sum(blocks), .001))*100 c4,
   buffer_pool                                       c5,
   sum(bytes)/sum(blocks)                            c6
from
	(
	select /*+ NO_MERGE */
	   o.owner          owner,
	   o.object_name    object_name,
	   o.subobject_name subobject_name,
	   o.object_type    object_type,
	   count(distinct file# || block#)         num_blocks
	from
	   dba_objects  o,
	   v$bh         bh
	where
	   o.data_object_id  = bh.objd
	and
	   o.owner not in ('SYS','SYSTEM')
	and
	   bh.status != 'free'
	group by
	   o.owner,
	   o.object_name,
	   o.subobject_name,
	   o.object_type
	order by
	   count(distinct file# || block#) desc
	) t1,
   dba_segments s
where
   s.segment_name = t1.object_name
and
   s.owner = t1.owner
and
   s.segment_type = t1.object_type
and
   nvl(s.partition_name,'-') = nvl(t1.subobject_name,'-')
group by
   t1.owner,
   object_name,
   object_type,
   buffer_pool
having
   sum(num_blocks) > 10
order by
   sum(num_blocks) 
;
