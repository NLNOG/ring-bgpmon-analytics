drop view if exists alarmtriggerview;
create view alarmtriggerview 
as 
select 
a.type as alarmtype,
GROUP_CONCAT(distinct o.email separator ',') as email,
GROUP_CONCAT(distinct CONCAT(p.prefix,' ',COALESCE(matchop,''),' ',COALESCE(as_regexp,'')) separator ',') as alarmprefix,
MIN(at.triggertime) as triggerperiodbegin,
MAX(at.triggertime) as triggerperiodend,
MAX(at.notified) as notified,
MAX(at.cleared) as cleared,
SUM(at.type = 'ANNOUNCE') as announces, 
SUM(at.type = 'WITHDRAW') as withdraws, 
GROUP_CONCAT(distinct at.prefix separator ',') as prefix,
GROUP_CONCAT(distinct at.path separator ',') as path,
GROUP_CONCAT(distinct at.source separator ',') as source
from 
alarmtriggers 
at 
right join alarms a on (at.alarm = a.id) 
right join prefixes p on (a.prefix = p.id) 
right join owners o on (a.owner = o.id) 
where 
at.id is not null
group by (UNIX_TIMESTAMP(at.triggertime) DIV 300), at.prefix
order by triggertime
;
select alarmtype,email,alarmprefix,triggerperiodbegin,triggerperiodend,notified,cleared,announces,withdraws,prefix from alarmtriggerview;
