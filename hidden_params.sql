SELECT
a.ksppinm Param ,
b.ksppstvl SessionVal ,
c.ksppstvl InstanceVal,
a.ksppdesc Descr
FROM
x$ksppi a ,
x$ksppcv b ,
x$ksppsv c
WHERE
a.indx = b.indx AND
a.indx = c.indx AND
a.ksppinm LIKE '/_%' escape '/'
ORDER BY
1;
