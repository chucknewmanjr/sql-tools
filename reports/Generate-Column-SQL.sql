declare @Table_Name sysname = '[Core].[EntityVersion]'--

if OBJECT_ID('tempdb..#Column') is not null drop table #Column

select i.*, c.is_identity
into #Column
from INFORMATION_SCHEMA.COLUMNS i
join sys.columns c on OBJECT_ID(i.TABLE_SCHEMA + '.' + i.TABLE_NAME) = c.[object_id] and i.COLUMN_NAME = c.[name]
where c.[object_id] = OBJECT_ID(@Table_Name)

--select * from #Column

select 
	',' + COLUMN_NAME + IIF(is_identity=1, ' -- identity', '') as Comma_Before,
	COLUMN_NAME + ',' + IIF(is_identity=1, ' -- identity', '') as Comma_After,
	'sourc.' + COLUMN_NAME + ',' + IIF(is_identity=1, ' -- identity', ''),
	', @p_' + COLUMN_NAME + IIF(is_identity=1, ' -- identity', '') as Comma_Before,
	'@p_' + COLUMN_NAME + ',' + IIF(is_identity=1, ' -- identity', '') as Comma_After
from #Column order by ORDINAL_POSITION

select 
	', @p_' + COLUMN_NAME + ' ' + DATA_TYPE + ISNULL('(' + CAST(CHARACTER_MAXIMUM_LENGTH as varchar) + ')', '') + IIF(is_identity=1, ' -- identity', '') as Comma_Before,
	'@p_' + COLUMN_NAME + ' ' + DATA_TYPE + ISNULL('(' + CAST(CHARACTER_MAXIMUM_LENGTH as varchar) + ')', '') + ',' + IIF(is_identity=1, ' -- identity', '') as Comma_After,
	COLUMN_NAME + ' ' + DATA_TYPE + ISNULL('(' + CAST(CHARACTER_MAXIMUM_LENGTH as varchar) + ')', '') + IIF(IS_NULLABLE = 'YES', '', ' NOT') + ' NULL,' + IIF(is_identity=1, ' -- identity', '')
from #Column order by ORDINAL_POSITION

select 
	',' + COLUMN_NAME + ' = @p_' + COLUMN_NAME + IIF(is_identity=1, ' -- identity', ''),
	', @p_' + COLUMN_NAME + '=@v_' + COLUMN_NAME + IIF(is_identity=1, ' -- identity', ''),
	COLUMN_NAME + ' = sourc.' + COLUMN_NAME + IIF(is_identity=1, ' -- identity', '') + ',',
	COLUMN_NAME + ' = IIF(u.' + COLUMN_NAME + ' = c.' + COLUMN_NAME + ', ver.' + COLUMN_NAME + ', u.' + COLUMN_NAME + ')' + IIF(is_identity=1, ' -- identity', '') + ', '
from #Column order by ORDINAL_POSITION

select 
	--	or iif(t1.c = t2.c or (t1.c is null and t2.c is null), 1, 0) = 0
	'OR ' + 
		IIF(
			IS_NULLABLE = 'YES',
			'IIF(targt.' + COLUMN_NAME + ' = sourc.' + COLUMN_NAME + ' OR (targt.' + COLUMN_NAME + ' IS NULL AND sourc.' + COLUMN_NAME + ' IS NULL), 1, 0) = 0',
			'targt.' + COLUMN_NAME + ' <> sourc.' + COLUMN_NAME
		) + 
		IIF(is_identity=1, ' -- identity', ''),
	'AND ' + 
		IIF(IS_NULLABLE = 'YES', '(', '') + 
		COLUMN_NAME + ' = @p_' + COLUMN_NAME + 
		IIF(IS_NULLABLE = 'YES',' OR (' + COLUMN_NAME + ' IS NULL AND @p_' + COLUMN_NAME + ' IS NULL))','') + 
		IIF(is_identity=1, ' -- identity', ''),
	'AND (' + 
		COLUMN_NAME + ' = @p_' + COLUMN_NAME + 
		' OR (' + COLUMN_NAME + ' IS NULL AND @p_' + COLUMN_NAME + ' IS NULL))' + 
		IIF(is_identity=1, ' -- identity', '')
from #Column order by ORDINAL_POSITION

--openjson UserExt varchar(10) '$.UserExt',
select 
	COLUMN_NAME + ' ' + DATA_TYPE + ISNULL('(' + CAST(CHARACTER_MAXIMUM_LENGTH as varchar) + ')', '') + ' ''$.' + COLUMN_NAME + ''',' as Open_JSON
from #Column order by ORDINAL_POSITION
go

