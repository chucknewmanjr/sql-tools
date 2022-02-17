declare @t table (table_id int, TableName sysname, Alias sysname null)

insert @t
select object_id, 
	[name] 
		--+ 
		--case SCHEMA_NAME([schema_id])
		--	when 'Core' then ''
		--	when 'HistorySecurity' then 'SecurityHistory'
		--	else SCHEMA_NAME([schema_id])
		--end
	, 
	''
from sys.tables
where SCHEMA_NAME([schema_id]) not like 'History%';

update @t set Alias = LEFT(TableName, 1);

declare @pos int = 1

while @pos < 30 begin
	set @pos += 1;

	update @t
	set Alias += substring(TableName, @pos, 1)
	where Alias in (
			select Alias
			from @t 
			group by Alias 
			having COUNT(*) > 1 and count(distinct substring(TableName, @pos, 1)) > 1
		)
end;

--select LEFT(Alias, 3), count(*) from @t group by LEFT(Alias, 3) having count(*) > 1

update trgt
set Alias = LEFT(trgt.Alias, 3) + CAST(src.Suffix as varchar)
from @t trgt
join (
	select *, ROW_NUMBER() over (partition by LEFT(Alias, 3) order by len(TableName), TableName) as Suffix
	from @t
	where LEN(Alias) > 4 
		and LEFT(Alias, 3) in (select LEFT(Alias, 3) from @t group by LEFT(Alias, 3) having count(*) > 1)
) src on trgt.TableName = src.TableName

select '[' + OBJECT_SCHEMA_NAME(table_id) + '].[' + OBJECT_NAME(table_id) + ']', Alias from @t  order by 1
