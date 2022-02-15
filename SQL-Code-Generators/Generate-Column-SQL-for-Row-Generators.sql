drop table if exists #c -- drop old table
go

select top 0 * into #c from sys.columns -- make new table
go

-- ==================================
-- ===== Put_Your_Query_In_Here =====

declare @Put_Your_Query_In_Here nvarchar(MAX) = '
	SELECT
		cl.ClientId, 
		cl.[Name], 
		cl.ClientComment, 
		cl.SyncId, 
		r.RegionCode
	FROM [Core].[Client] cl
	join [Core].[Region] r on cl.HostRegionId = r.RegionId
	where cl.IsActive = 1
'
-- ==================================
-- ==================================

insert #c exec ('select top 0 * into #q from (' + @Put_Your_Query_In_Here + ') t; select * from tempdb.sys.columns where object_id = object_id(''tempdb..#q'')')
go

select 
	c.column_id,
	c.[name],
	REPLACE(t.template, '[name]', 't.' + c.[name]) + ''', '', ' + IIF(c.is_identity = 1, '-- identity', '')
from #c c 
join (values 
	(1, 'int smallint bit bigint tinyint decimal numeric'), -- no quotes
	(2, 'datetime date datetime2'), -- quotes but no replace
	(3, 'varchar nvarchar char uniqueidentifier xml'), -- might replace quotes
	(4, 'varbinary')
) dtg (data_type_group_id, data_type_list) 
	on dtg.data_type_list like '%' + TYPE_NAME(c.user_type_id) + '%'
join (values
	(1, 0, 0, '[name], '),
	(2, 0, 0, ''''''''', [name], '''''),
	(3, 0, 0, ''''''''', [name], '''''),
	(3, 1, 0, ''''''''', REPLACE([name], '''''''', ''''''''''''), '''''),
	(4, 0, 0, ''''''''', CONVERT(varchar(MAX), [name], 1), '''''''', '),
	(1, 0, 1, 'ISNULL(CAST([name] AS varchar(MAX)), ''NULL''), '),
	(2, 0, 1, 'ISNULL('''''''' + CAST([name] AS varchar(MAX)) + '''''''', ''NULL''), '),
	(3, 0, 1, 'ISNULL('''''''' + CAST([name] AS nvarchar(MAX)) + '''''''', ''NULL''), '),
	(3, 1, 1, 'ISNULL('''''''' + REPLACE([name], '''''''', '''''''''''') + '''''''', ''NULL''), '),
	(4, 0, 1, 'ISNULL('''''''' + CONVERT(varchar(MAX), [name], 1) + '''''''', ''NULL''), ')
	-- To-Do: Use QUOTENAME(value, '''') instead of REPLACE for columns under 128 characters wide.
) t (data_type_group_id, is_long, is_nullable, template) 
	on dtg.data_type_group_id = t.data_type_group_id
	and IIF(c.max_length between 1 and 18, 0, 1) = 0 -- uniqueidentifier max length is 16
	and c.is_nullable = t.is_nullable
order by c.column_id
go

