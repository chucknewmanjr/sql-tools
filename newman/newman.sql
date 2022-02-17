/*
drop table if exists #t1
go

select *
into #t1
from (values 
	(1, '        /\                    /\'),
	(2, ' /\  / / /  \  /\  / /\  /\  / /\  /\  /'),
	(3, '/  \/  \/ /  \/  \/ /  \/  \  / / /  \/'),
	(4, '        \/                    \/')
) t (n, a)
go

drop table if exists #t2
go

select n, CAST(0 as bigint) as x
into #t2
from #t1
go

declare @i int = (select max(len(a)) from #t1)

while @i > 0 begin
	update t2
	set x = t2.x * 3 + CHARINDEX(SUBSTRING(t1.a, @i, 1), '/\')
	from #t1 t1
	join #t2 t2 on t1.n = t2.n

	set @i -= 1
end
go

select * from #t2
*/

with t as(select x,0i,CAST(''as varchar(MAX)) a from (values(1029455660506050),(2270171348526990934),(4407174318369854082),(1441237924708470))t(x)union all select x,i+1,a+SUBSTRING(' /\', x/POWER(3.0,i)%3+1,1)from t where i<40)select'--'+a from t where i=40
go

