-- ------- --
-- encoder --
-- ------- --
declare @text table (y int identity(0,1), t varchar(MAX));

insert @text (t)
select *
from (values 
	('                  /\                                          /\                  '),
	('                 /  \                                        /  \                 '),
	('    /\      /\  / /\ \  /\      /\      /\  /\      /\      / /\ \      /\      /\'),
	('   /  \    / / / / / /  \ \    /  \    / / /  \    /  \    / / /  \    /  \    / /'),
	('  / /\ \  / / / / / / /\ \ \  / /\ \  / / / /\ \  / /\ \  / / / /\ \  / /\ \  / / '),
	(' / /  \ \/ /  \ \/ / / /  \ \/ /  \ \/ / / /  \ \/ /  \ \ \/ / / / / / /  \ \/ /  '),
	('/ /    \  /    \  / / /    \  /    \  / / /    \  /    \ \  / / / / / /    \  /   '),
	('\/      \/      \ \/ /      \/      \/  \/      \/      \/  \ \/ /  \/      \/    '),
	('                 \  /                                        \  /                 '),
	('                  \/                                          \/                  ')
) t (t);

with t as (
	select y, 1 x, left(t, 1) as c, stuff(t, 1, 1, '') as t from @text
	union all
	select y, x+1, left(t, 1), stuff(t, 1, 1, '') from t 
	where len(t) > 0
)
select cast(sum(charindex(c,'/\') * power(3,y)) as varchar) + ',' from t where c <> ' ' group by x 
order by x desc
for xml path('');
go

-- ------- --
-- decoder --
-- ------- --
with t as(select 0y,CAST(value as int)q,0r from STRING_SPLIT(REPLACE(REPLACE('45,90-2430,5103,405,783,2610,7377,22160,44560,13395,5193,270,567,3645\90-2475,5193-2430\63,405,810,2475,7377,22160,44560,13395,4950,1485,567,45,90-2430,5103','-',',270,810,2430\90,270,810,'),'\',',4860,1620,540,180,'),',')union all select y+1,q/3,q%3 from t where y<10)select'--'+REPLACE(REPLACE((select char(r+46)from t where y=u.y for xml path('')),'.',' '),'0','\')from t u group by y;
go

-- ------- --
--  small  --
-- ------- --
with t as(select x,0i,CAST(''as varchar(MAX)) a from (values(1029455660506050),(2270171348526990934),(4407174318369854082),(1441237924708470))t(x)union all select x,i+1,a+SUBSTRING(' /\', x/POWER(3.0,i)%3+1,1)from t where i<40)select'--'+a from t where i=40
go

