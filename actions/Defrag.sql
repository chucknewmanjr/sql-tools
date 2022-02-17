drop table if exists #t;
go

-- ==================
--     PARAMETERS
-- ==================
declare @page_count int = 1000;
declare @reorg_avg_fragmentation_in_percent float = 5;
declare @rebuild_avg_fragmentation_in_percent float = 30;
declare @not_modified_in_days int = 7;
declare @time_limit_minutes int = 1;
-- ==================

select distinct
	ROW_NUMBER() over (order by t.modify_date desc) as row_num, -- start with the table that's gone the longest without a defrag
	'alter index ' + ISNULL('[' + i.[name] + ']', 'ALL') + ' on [' + SCHEMA_NAME(t.[schema_id]) + '].[' + t.[name] + '] ' +
	REPLACE(
		case 
			when ips.avg_fragmentation_in_percent >= @rebuild_avg_fragmentation_in_percent 
			then 'REBUILD{partition} with (online = on)'
			else 'REORGANIZE{partition}'
		end,
		'{partition}',
		case ips.partition_number
			when 1 then ''
			else ' partition = ' + CAST(ips.partition_number as varchar)
		end
	) + ';' as instruction
into #t
from sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
join sys.indexes i on ips.[object_id] = i.[object_id] and ips.index_id = i.index_id
join sys.tables t on ips.[object_id] = t.[object_id]
where ips.page_count >= @page_count
	and ips.avg_fragmentation_in_percent >= @reorg_avg_fragmentation_in_percent
	and DATEDIFF(DAY, t.modify_date, SYSDATETIME()) >= @not_modified_in_days;

declare @this_row_num int = (select MAX(row_num) from #t);
declare @time_limit datetime = DATEADD(MINUTE, @time_limit_minutes, SYSDATETIME());
declare @sql nvarchar(MAX);

while SYSDATETIME() < @time_limit and @this_row_num > 0 begin;
	select @sql = instruction from #t where row_num = @this_row_num;

	print convert(varchar, sysdatetime(), 114) + ' - ' + CAST(@this_row_num as varchar) + ' - ' + @sql;

	exec (@sql);
	
	set @this_row_num -= 1;
end;
go

