-- ==================================
-- ===== Put_Your_Query_In_Here =====

declare @Put_Your_Query_In_Here nvarchar(MAX) = '
	select is_published, is_encrypted, create_date, database_id,
		resource_pool_id, default_language_name, [name],
		collation_name, service_broker_guid, replica_id, owner_sid
	from sys.databases
';

-- ==================================
-- ========== INSTRUCTIONS ==========

-- The output is SQL code that goes inside of CONCAT().

-- ==================================
-- ==================================

drop table if exists #column; -- drop table

select top 0 * into #column from sys.columns; -- recreate the table

-- insert rows about columns
insert #column exec ('select top 0 * into #q from (' + @Put_Your_Query_In_Here + ') t; select * from tempdb.sys.columns where object_id = object_id(''tempdb..#q'')');
go

declare @4q char(4) = REPLICATE('''', 4); -- 4 quotes in a row becomes a single quote
declare @6q char(6) = REPLICATE('''', 6); -- 6 quotes in a row becomes 2 single quotes

with
	col as (
		select
			column_id,
			[name] as column_name,
			TYPE_NAME(user_type_id) as typ,
			is_nullable,
			is_identity,
			case
				when max_length between 1 and 18 then 1
				when max_length between 19 and 128 then 2
				else 3
			end as length_type
		from #column
	),
	type_group as (
		-- numbers get no quotes or replacements
		select 'num' as grp, * from (values ('bit'), ('tinyint'), ('smallint'), ('int'), ('bigint'), ('decimal'), ('numeric'), ('real'), ('float'), ('money'), ('smallmoney')) t (typ)
		-- binaries get converted and no quotes
		union select 'bin', * from (values ('binary'), ('varbinary'), ('timestamp')) t (typ)
		-- dates and such get quotes but no replacements
		union select 'quo', * from (values ('datetime'), ('date'), ('datetime2'), ('time'), ('datetimeoffset'), ('smalldatetime'), ('uniqueidentifier'), ('hierarchyid')) t (typ)
		-- varchar and any remaining types get single quotes replaced with REPLACE or QUOTENAME.
	)
select
	col.column_id,
	col.column_name,
	col.typ,
	REPLACE(template.template, '[name]', 't.[' + col.column_name + ']') + ''', '',' + IIF(col.is_identity = 1, ' -- identity', '')
from col
left join type_group on col.typ = type_group.typ
join (values
	('num', 0, NULL, '[name], '), -- TESTED
	('bin', 0, NULL, 'CONVERT(varchar(MAX), [name], 1), '),
	('quo', 0, NULL, @4q + ', [name], ' + @4q + ', '), -- TESTED
	('oth', 0, 1,    @4q + ', [name], ' + @4q + ', '), -- A quote is unlikely in 18 or fewer characters.
	('oth', 0, 2,    @4q + ', QUOTENAME([name]), ' + @4q + ', '), -- QUOTENAME is nicer
	('oth', 0, 3,    @4q + ', REPLACE([name], ' + @4q + ', ' + @6q + '), ' + @4q + ', '), -- TESTED
	('num', 1, NULL, 'ISNULL(CAST([name] AS varchar(MAX)), ''NULL''), '), -- TESTED
	('bin', 1, NULL, 'ISNULL(CONVERT(varchar(MAX), [name], 1), ''NULL''), '), -- TESTED
	('quo', 1, NULL, 'ISNULL(' + @4q + ' + CAST([name] AS varchar(MAX)) + ' + @4q + ', ''NULL''), '), -- TESTED
	('oth', 1, 1,    'ISNULL(' + @4q + ' + [name] + ' + @4q + ', ''NULL''), '),
	('oth', 1, 2,    'ISNULL(' + @4q + ' + QUOTENAME([name]) + ' + @4q + ', ''NULL''), '),
	('oth', 1, 3,    'ISNULL(' + @4q + ' + REPLACE([name], ' + @4q + ', ' + @6q + ') + ' + @4q + ', ''NULL''), ') -- TESTED
) template (grp, is_nullable, length_type, template)
	on isnull(type_group.grp, 'oth') = template.grp 
	and col.is_nullable = template.is_nullable 
	and col.length_type = ISNULL(template.length_type, col.length_type)
order by col.column_id;

-- ==================================
-- =====      TEST QUERIES      =====

	--select reads, statement_context_id, query_hash, [ansi_nulls],
	--	start_time, wait_resource, [language], percent_complete,
	--	connection_id, [context_info]
	--from sys.dm_exec_requests;

	--select is_published, is_encrypted, create_date, database_id,
	--	resource_pool_id, default_language_name, [name],
	--	collation_name, service_broker_guid, replica_id, owner_sid
	--from sys.databases;

-- ==================================
-- ==================================
