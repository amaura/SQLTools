select k.MASTERKEYID,c.name, e.keystore_type
from v$containers c
left join v$database_key_info k on k.con_id=c.con_id
left join v$encryption_keys e on concat('06',k.MASTERKEYID)=e.key_id;
