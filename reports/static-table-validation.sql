-- ===== HOW TO =====
-- This script keeps the expected values in a temp table.
-- This script also generates those same rows in the results.
-- So if the expected values get old, you can fix that 
-- by running this script in the development environment 
-- and using the results to replace the expected values.

-- This script makes a hash value out of the entire contents of a table.
-- That hash value is matched to the expected value.
-- No results means all fixed tables match what's expected.
-- If a table doesn't match, that table gets displayed with expected and actual row counts.
-- It's up to you to investigate the discrepency further.
-- ==================
drop table if exists #expected;
go

select * into #expected from (values
	('[Core].[Application]', 0x562FB65A8118968A5593DADDEC694F6E, 3), 
	('[Core].[ApplicationAttribute]', 0xD41D8CD98F00B204E9800998ECF8427E, 0), 
	('[Core].[Country]', 0x104A2E3A1C819B01F9DADC562DC50956, 271), 
	('[Core].[Currency]', 0x15D39AC2807C232BDE51CEBB3B2D98B4, 154), 
	('[Core].[EntityClassification]', 0x420300AA8C0C08CFACDFDCC89E8667CE, 14), 
	('[Core].[EntityType]', 0x9AC92B2F3A84E935D3F2222D9B365E54, 8), 
	('[Core].[ExtraAttributesDefinition]', 0x4B07E1A5087BFF912D984B2EF2397094, 1), 
	('[Core].[Industry]', 0xD382E3896A3812B2044AA07916E83679, 55), 
	('[Core].[LedgerType]', 0x9715805E89919A748B5DBC87E26798FE, 3), 
	('[Core].[LockedEntitiesErrorType]', 0x3F392800B15EC68575BE6D737F9D13EB, 1), 
	('[Core].[MessageStatusType]', 0x1B1AAF7F4AC9818BC88304035343A199, 5), 
	('[Core].[OrgChartClassification]', 0xF78A1A5DBAA48B216D4A70A1119ED834, 7), 
	('[Core].[OrgChartColor]', 0xFB8A8AE3A57BE3EE4F88EF3DC3AA053F, 13), 
	('[Core].[OrgChartConnectorLine]', 0x631C0F4E2DFF7B86FC8D22CFAB488AF8, 8), 
	('[Core].[OrgChartShape]', 0x57E051A013DC51524B6DE5790EA6B241, 7), 
	('[Core].[Region]', 0x7187D17B76152F79D6E140592842DEB3, 4), 
	('[Core].[State]', 0x09385F382169E95EAAB4EE1FEAE893C6, 3846), 
	('[Security].[AccessPolicyType]', 0xC552A376E0FD8693E0AD5F5476FB7A77, 3), 
	('[Security].[Module]', 0x84BE3CF79E0234038766E41C546EA448, 1), 
	('[Security].[PrincipalType]', 0xAE6B41468368556D985FE92AF4E5ECDF, 2), 
	('[Security].[Role]', 0x041C78A769AB0B2F15E93238D7E9C0CD, 4), 
	('[Security].[RoleMembership]', 0xD1B9D004EDDFC37BEFCD80D8E65175AE, 6), 
	('[Security].[UserMgmtType]', 0x3477719369747639F87EDD7B5FED6E3E, 7)
) t1 (table_name, hash_value, row_count)
go

drop table if exists #returned;
go

create table #returned (table_name sysname, hash_value binary(16), row_count int);
go

declare @sql nvarchar(MAX)

-- build hash select statements
with t1 as (
	select '[' + TABLE_SCHEMA + '].[' + TABLE_NAME + ']' as table_name, column_name
	from INFORMATION_SCHEMA.COLUMNS
	where COLUMN_NAME not in ('CreatedBy', 'CreatedDt', 'UpdatedBy', 'UpdatedDt', 'SysStartTime', 'SysEndTime')
		 and RIGHT(COLUMN_NAME, 2) <> 'Id'
),
t2 as (
	select distinct 
		t.table_name, 
		p.[rows], 
		COUNT(*) as column_count, 
		stuff((
			select ', ' + column_name 
			from t1 
			where table_name = t.table_name 
			order by column_name 
			for xml path('')
		), 1, 2, '') as column_list
	from t1 t
	join sys.partitions p on p.object_id = OBJECT_ID(t.table_name) and p.index_id = 1
	where t.table_name in (select table_name from #expected)
	group by t.table_name, p.[rows]
)
select @sql = CONCAT(
		ISNULL(@sql + ' union ', ''), 
		'select ''', table_name, 
		''', hashbytes(''MD5'', isnull((select ', column_list, 
		' from ', table_name, 
		LEFT(' order by 1, 2, 3, 4, 5, 6, 7, 8, 9', column_count * 3 + 8), 
		' for json auto), '''')), ', [rows]
	)
from t2

-- collect results of hash select atatements
insert #returned exec (@sql)
go

-- compare the results to what's expected
select 
	e.table_name,
	e.row_count as row_count_expected,
	r.row_count as row_count_returned,
	e.hash_value as hash_expected,
	r.hash_value as hash_returned
from #expected e 
join #returned r on e.table_name = r.table_name
where e.hash_value <> r.hash_value
go

-- output the results for future changes
select CONCAT(
		'(''', table_name, ''', ', CONVERT(nvarchar(34), hash_value, 1), ', ', row_count, '), '
	) as returned_values
from #returned
go

