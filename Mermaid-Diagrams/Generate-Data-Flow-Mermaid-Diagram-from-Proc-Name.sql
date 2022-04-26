/* ================================================ */
declare @Proc_Name sysname = 'WP340B.RxTranInventoryInsert';
/* ================================================ */

declare @Proc_ID int = OBJECT_ID(@Proc_Name)

if OBJECT_ID('tempdb..#t') is not null drop table #t;

select
	[object_id],
	[type_desc],
	CONCAT(
		RTRIM([type]) COLLATE DATABASE_DEFAULT, 
		ROW_NUMBER() over (partition by [type] order by [name]), 
		IIF([type_desc] = 'USER_TABLE', '[', '(['),
		OBJECT_SCHEMA_NAME([object_id]), '.', [name],
		IIF([type_desc] = 'USER_TABLE', ']', '])')
	) as Labl
into #t
from sys.objects

declare @Proc_Label sysname = (select Labl from #t where [object_id] = @Proc_ID)

select 'graph LR'
union
select CONCAT(t.Labl, ' --> ', @Proc_Label)
from sys.sql_dependencies d
join #t t on d.[object_id] = t.[object_id]
where d.referenced_major_id = @Proc_ID
union
select CONCAT(@Proc_Label, ' --> ', t.Labl)
from sys.sql_dependencies d
join #t t on d.referenced_major_id = t.[object_id]
where d.[object_id] = @Proc_ID and t.[type_desc] <> 'USER_TABLE'
union
select CONCAT(t.Labl, ' -.-> ', @Proc_Label) -- read
from sys.sql_dependencies d
join #t t on d.referenced_major_id = t.[object_id]
where d.[object_id] = @Proc_ID and t.[type_desc] = 'USER_TABLE'
group by t.Labl
having MAX(is_updated * 1) = 0
union
select distinct CONCAT(@Proc_Label, ' ==> ', t.Labl) -- write
from sys.sql_dependencies d
join #t t on d.referenced_major_id = t.[object_id]
where d.[object_id] = @Proc_ID and d.is_updated = 1

