/*
select count(*), database_id, object_id, index_id, partition_number, alloc_unit_type_desc, index_level
from sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
group by database_id, object_id, index_id, partition_number, alloc_unit_type_desc, index_level
having count(*) > 1
order by 1 desc
*/

select 
	SCHEMA_NAME(t.[schema_id]) + t.[name] as table_name,
	DATEDIFF(day, t.modify_date, sysdatetime()) as modify_days,
	i.[name], 
	ips.partition_number,
	ips.index_type_desc,
	ips.alloc_unit_type_desc,
	case ips.index_level
		when 0 then 'leaf'
		when ips.index_depth then 'root'
		else 'inbetween'
	end index_level
	, case when ips.avg_fragmentation_in_percent > 30 then 'REBUILD' else 'REORG' end as suggestion
	, FORMAT(ips.avg_fragmentation_in_percent, 'N1') as avg_fragmentation_in_percent
	, ips.fragment_count
	, FORMAT(ips.avg_fragment_size_in_pages, 'N1') as avg_fragment_size_in_pages
	, ips.page_count
	, FORMAT(ips.avg_page_space_used_in_percent, 'N1') as avg_page_space_used_in_percent
	, ips.record_count
	, ips.min_record_size_in_bytes
	, ips.max_record_size_in_bytes
	, ips.avg_record_size_in_bytes
from sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
join sys.indexes i on ips.[object_id] = i.[object_id] and ips.index_id = i.index_id
join sys.tables t on ips.[object_id] = t.[object_id]
where ips.page_count >= 1000
	and ips.avg_fragmentation_in_percent >= 5
order by 1, i.index_id
go

