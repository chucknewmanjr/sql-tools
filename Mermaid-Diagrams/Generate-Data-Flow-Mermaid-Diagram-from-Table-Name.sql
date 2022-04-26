/* ================================================ */
declare @Table_Name sysname = 'WP340B.ReplenishedInventoryAlloc';
/* ================================================ */

if OBJECT_ID('tempdb..#t') is not null drop table #t;

declare @Label table ([object_id] int, Object_Label sysname, Is_Table bit);

with t as (
	select
		[object_id],
		OBJECT_SCHEMA_NAME([object_id]) + '.' + [name] as [Object_Name],
		RTRIM([type]) COLLATE DATABASE_DEFAULT as [type],
		ROW_NUMBER() over (partition by [type] order by [name]) as [Row_Number], 
		IIF([type_desc] = 'USER_TABLE', 1, 0) as Is_Table
	from sys.objects
)
insert @Label
select
	[object_id],
	CONCAT([type], [Row_Number], IIF(Is_Table = 1, '[', '(['), [Object_Name], IIF(Is_Table = 1, ']', '])')),
	Is_Table
from t;

declare @Proc table (Proc_ID int, Proc_Label sysname);

insert @Proc
select distinct l.[object_id], l.Object_Label
from @Label l
join sys.sql_dependencies d on l.[object_id] = d.[object_id]
where d.referenced_major_id = OBJECT_ID(@Table_Name)
	and d.is_updated = 1;

select 'graph LR'
union
select distinct ring.Proc_Label + ' -->|call| ' + red.Proc_Label + ' %% call'
	from sys.sql_dependencies d
	join @Proc ring on d.[object_id] = ring.Proc_ID
	join @Proc red on d.referenced_major_id = red.Proc_ID
union
	select red.Object_Label + ' -.-> ' + ring.Proc_Label + ' %% read'
	from sys.sql_dependencies d
	join @Proc ring on d.[object_id] = ring.Proc_ID
	join @Label red on d.referenced_major_id = red.[object_id]
	where red.Is_Table = 1
	group by red.Object_Label, ring.Proc_Label
	having MAX(d.is_updated * 1) = 0
union
	select distinct ring.Proc_Label + ' ==> ' + red.Object_Label + ' %% write'
	from sys.sql_dependencies d
	join @Proc ring on d.[object_id] = ring.Proc_ID
	join @Label red on d.referenced_major_id = red.[object_id]
	and d.is_updated = 1;
