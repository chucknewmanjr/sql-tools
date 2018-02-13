SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_PADDING ON;
GO

if db_name() = 'master' begin
	RAISERROR('Master not allowed.', 16, 1); 
	return;
end else if SCHEMA_ID('star') is null 
	exec('create schema star');
go

if OBJECT_ID('star.p_GetStagingColumnXml', 'P') is not null drop proc star.p_GetStagingColumnXml;
go

create proc star.p_GetStagingColumnXml(@stagingTable varchar(128)) as
	-- returns XML that looks like this:
	--   <columns>
	--     <column>
	--       <name>Employer</name>
	--       <action></action>
	--     </column>
	--   </columns>
	--
	-- In action tag, put dimention, measure, skip or leave it blank.
	-- Removing a column is the same as skip.
	-- Blank means the proc decides if it's a dimention or not.
	-- Use the XML as a parameter in p_CreateStarSchema proc.
	--
	-- --- EX ---
	-- exec star.p_GetStagingColumnXml 'dbo.[LaborDataStaging]'
	-- exec star.p_GetStagingColumnXml '[staging].[LaborData]'

	declare @objectId int = object_id(@stagingTable);

	select [name], '' as [action] from sys.columns where object_id = @objectId for xml path('column'), root('columns');
go

if OBJECT_ID('star.p_DropStarSchema', 'P') is not null drop proc star.p_DropStarSchema;
go

create proc star.p_DropStarSchema(@namePrefix varchar(10), @schema sysname = 'dbo') as
	-- returns SQL statements that are drops of tables.
	-- You execute what you like.
	--
	-- --- EX ---
	-- exec star.p_DropStarSchema 'Labor', 'Labor'
	-- exec star.p_DropStarSchema 'Labor2', 'Labor'

	select String
	from (
			select 1 as Sort_Order, 'if OBJECT_ID(''[' + @schema + '].[vw_' + @namePrefix + ']'') is not null drop view [' + @schema + '].[vw_' + @namePrefix + '];' as String
		union
			select 2 as Sort_Order, 'if OBJECT_ID(''[' + @schema + '].[' + @namePrefix + '_Fact]'') is not null drop table [' + @schema + '].[' + @namePrefix + '_Fact];' as String
		union
			select 4, 'if OBJECT_ID(''[' + @schema + '].[' + [name] + ']'') is not null drop table [' + @schema + '].[' + [name] + '];'
			from sys.tables 
			where [name] like @namePrefix + '[_]%[_]Dim' and [schema_id] = SCHEMA_ID(@schema)
	) t
	order by Sort_Order
go

if OBJECT_ID('star.fn_TemplateMerge') is not null drop function star.fn_TemplateMerge;
go

create function star.fn_TemplateMerge(@template nvarchar(max), @replacementXml xml, @separator nvarchar(max) = '') returns nvarchar(max) as begin
	/* ------------------------
	Returns a string of templates merged with replacements.
	This function is typically used for building SQL statements.
	The number of copies of the template matches the number or rows in @replacementXml. 
	Each copy has the placeholders replaced according to the row.
	A placeholder matches a column name / leaf tag / element inside square brackets. ([])
	Column names are not case sensitive.
	The replacement is the value in the column.
	@separator - Goes inbetween each copy of the @template.
	@replacementXml - Looks like:
	<row>
		<column>value</column>
	</row>
	
	-- EXAMPLE: This example returns "From left to right. From top to bottom."
	declare @template nvarchar(max) = 'From [this] to [that]. ';
	declare @replacementXml xml = (
		select * from (select 'left' as This, 'right' as That union select 'top', 'bottom') t
		for xml path('row')
	);
	declare @result nvarchar(max)
	set @result = star.fn_TemplateMerge(@template, @replacementXml, DEFAULT)
	print @result
	set @result = star.fn_TemplateMerge(@template, @replacementXml, '; ')
	print @result
	------------------------ */

	declare @Row table (Row_Num int identity, Row_XML xml, Work nvarchar(max));

	insert @Row (Row_XML, Work)
	select c.query('.'), @template
	from @replacementXml.nodes('row') tab(c);

	declare @Replacement table (
		Value_ID int identity, 
		Row_Num int, 
		Placeholder varchar(100), 
		Replacement varchar(1000)
	)

	insert @Replacement (Row_Num, Placeholder, Replacement)
	select r.Row_Num, c.value('local-name(.)', 'varchar(100)'), c.value('.', 'varchar(1000)')
	from @Row r
	cross apply r.Row_XML.nodes('row/*') t(c)

	declare @thisValueId int = (select max(Value_ID) from @Replacement)

	while @thisValueId > 0 begin
		update targt
		set Work = REPLACE(targt.Work, '[' + sourc.Placeholder + ']', sourc.Replacement)
		from @Row targt
		join @Replacement sourc on targt.Row_Num = sourc.Row_Num
		where sourc.Value_ID = @thisValueId

		set @thisValueId -= 1
	end

	declare @result nvarchar(max) = null

	select @result = ISNULL(@result + @separator, '') + Work
	from @Row

	return @result;
end
go

if OBJECT_ID('star.p_CreateStarSchema') is not null drop proc star.p_CreateStarSchema
go

create proc star.p_CreateStarSchema(
	@stagingTable sysname, 
	@namePrefix varchar(10), 
	@schema sysname = 'dbo', 
	@stagingColumnXml xml = null
) as
	-- Creates tables and a view to make a star schema out of a staging table.
	-- @stagingColumnXml is optional. Null means this proc decides.
	-- Use p_GetStagingColumnXml proc to make the XML.
	-- That XML has an Action tag that's blank, dimention, measure or skip.
	-- - blank - This proc decides if it's a dimention or a measure for you.
	-- - dimention - A dimention table is created with sequential integer primary key.
	--		The fact table gets a foreign key to that table.
	-- - measure - This column goes in the fact table without a dimention table.
	-- - skip - this column is not used.
	--
	-- NOTE: date and time - A date dimention table is always created with 0 as 1/1/1900.
	--		The Action is ignored unless it's skip.
	--		Separate date column and time* column go in the fact table.
	--
	-- --- EX ---
	-- declare @Xml = '... staging column XML goes here ...'
	-- exec star.p_CreateStarSchema 'staging.LaborData', 'Labor', 'Labor', @Xml
	-- exec star.p_CreateStarSchema 'dbo.LaborDataStaging', 'Labor', 'Labor'
	-- exec star.p_CreateStarSchema 'dbo.[vw_Labor]', 'Labor2', 'Labor'

	declare @objectId int = object_id(@stagingTable);

	---- -----------------------------------------------------------
	---- validation
	--if exists (select * from sys.tables where [name] like @namePrefix + '[_]%' and object_id != @objectId) begin
	--	RAISERROR('Tables with a name that begin with this prefix already exist.', 16, 1);
	--	return
	--end

	-- this is a special case. this proc decides for all the columns if it's a measure or a dimention
	if @stagingColumnXml is null begin
		set @stagingColumnXml = (select [name], '' as [action] from sys.columns where object_id = @objectId for xml path('column'), root('columns'));
	end

	if SCHEMA_ID(@schema) is null exec('create schema [' + @schema + ']');

	set nocount on

	-- -----------------------------------------------------------
	-- -----------------------------------------------------------
	declare @StagingColumn table (
		ID int identity, 
		Column_Name sysname, 
		[Action] varchar(20),
		Data_Type varchar(20),
		Max_Length int,
		Scaling varchar(20),
		Null_Replacement varchar(20)
	);

	-- convert the XML into a table
	insert @StagingColumn (Column_Name, [Action])
	select 
		c.value('name[1]', 'sysname') as Column_Name, 
		isnull(c.value('action[1]', 'varchar(20)'), '') as [Action]
	from @stagingColumnXml.nodes('columns/column') t(c);

	-- fill in data types. The merge should only do updates
	with sourc as (
		select 
			c.[name] as Column_Name,
			t.[name] as Data_Type,
			c.max_length as Max_Length,
			case 
				when t.[name] in ('char', 'varchar', 'binary', 'varbinary') then '(' + isnull(cast(nullif(c.max_length, -1) as varchar), 'max') + ')'
				when t.[name] in ('nchar', 'nvarchar') then '(' + isnull(cast(nullif(c.max_length, -1) / 2 as varchar), 'max') + ')'
				when t.[name] in ('decimal', 'numeric') then '(' + cast(c.[precision] as varchar) + ',' + cast(c.scale as varchar) + ')'
				when t.[name] in ('float') then '(' + cast(c.[precision] as varchar) + ')'
				when t.[name] in ('datetime2', 'datetimeoffset', 'time') then '(' + cast(c.scale as varchar) + ')'
				else '' 
			end as Scaling,
			case
				when c.collation_name is not null then ''''''
				when t.[name] like '%date%' then '''9999-12-31'''
				when t.[name] in ('uniqueidentifier', 'image', 'text', 'ntext', 'sql_variant', 'xml', 'hierarchyid', 'timestamp') then 'NULL' -- these uncommon
				else '0'
			end as Null_Replacement
		from sys.columns c
		join sys.types t on c.user_type_id = t.user_type_id
		where object_id = @objectId
	)
	merge @stagingColumn as targt using sourc on targt.Column_Name = sourc.Column_Name
	when matched then update set Data_Type = sourc.Data_Type, Max_Length = sourc.Max_Length, Scaling = sourc.Scaling, Null_Replacement = sourc.Null_Replacement;
	-- when not matched then don't do insert. these columns are skipped

	-- fix blank actions the easy way
	update @stagingColumn
	set [Action] = 
		case
			-- date/time columns are special
			when Data_Type like '%date%' then 'datetime'
			-- all numbers (+time, bit, ) do not get a dimention table even if there's low cardinality (degenarate). so measure it is
			when Data_Type like '%int' then 'measure'
			when Data_Type like '%money' then 'measure'
			when Data_Type in ('decimal', 'numeric', 'float', 'real', 'bit', 'time') then 'measure'
			-- these uncommon
			when Data_Type in ('uniqueidentifier', 'image', 'text', 'ntext', 'sql_variant', 'xml', 'hierarchyid', 'timestamp') then 'skip' 
			-- low cardinality (non numeric) columns get a dimention table
			when Data_Type in ('date', 'char', 'nchar', '') then 'dimention'
			-- wide columns get a dimention table just to keep them out of the fact table
			when Data_Type in ('text', 'ntext', 'image', 'xml') then 'dimention'
			when Max_Length = -1 then 'dimention'
			-- the rest depends on the data
			else ''
		end
	where [Action] = '';

	-- now it is safe to delete skips
	delete @stagingColumn where [Action] = 'skip';

	-- get ready for all the templates, replacements and dynamic SQL that are to follow
	declare 
		@template nvarchar(max), 
		@replacementXml xml, 
		@sql nvarchar(max);

	-- fix blank actions the harder way - check cardinality
	set @template = 'select ''[Column_Name]'', avg(Factor) from (select count(*) as Factor from [stagingTable] group by [[Column_Name]]) t; ';

	set @replacementXml = (select * from @stagingColumn where [Action] = '' for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @sql = REPLACE(@sql, '[stagingTable]', @stagingTable)

	declare @Factor table (Column_Name sysname, Factor real);

	insert @Factor exec (@sql);

	update targt 
	set [Action] = case when sourc.Factor > 3 then 'dimention' else 'measure' end
	from @stagingColumn targt
	join @Factor sourc on targt.Column_Name = sourc.Column_Name
	where targt.[Action] = '';

	-- date/time columns are special
	update @stagingColumn set [Action] = 'datetime' where Data_Type like '%date%';

	-- -----------------------------------------------------------
	-- -----------------------------------------------------------
	-- all actions set. now let's create dimention tables. fill them too

	-- drop tables
	-- FOR TESTING ONLY - We have already validated that no tables exist.
	set @sql = (
		select 'drop table [' + @schema + '].[' + [name] + ']; '
		from sys.tables 
		where [name] like @namePrefix + '[_]%' and [schema_id] = SCHEMA_ID(@schema)
		order by max_column_id_used desc 
		for xml path('')
	);

	if @sql is not null begin
		print @sql; -- ==========
		exec (@sql); -- ----------------------------------------------
	end

	-- create date dimention (role-playing)
	set @sql = 'create table [' + @schema + '].[' + @namePrefix + '_Date_Dim] (Date_Value date NOT NULL primary key, Day_of_Week_Name varchar(10), Month_Name varchar(20))';
	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- fill date dimention table
	set @template = 'select min([[Column_Name]]), max([[Column_Name]]) from [stagingTable] where [[Column_Name]] is not null; ';

	set @replacementXml = (select * from @stagingColumn where Data_Type like '%date%' for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @sql = REPLACE(@sql, '[stagingTable]', @stagingTable)
	
	declare @Range table (Min_Date date, Max_Date date);

	insert @Range exec (@sql);

	-- this generates dates from 1900 to 2242 and then limits that to the min and max range
	set @template = 'with t as (select 0 as x union all select x + 1 from t where x < 49) insert [[schema]].[[namePrefix]_Date_Dim] (Date_Value) select Date_Value from (select cast(t1.x + t2.x * 50 + t3.x * 2500 as datetime) as Date_Value from t t1 cross join t t2 cross join t t3) t where Date_Value between ''[Min_Date]'' and ''[Max_Date]''; ';

	set @replacementXml = (
		select min(Min_Date) as Min_Date, max(Max_Date) as Max_Date, @namePrefix as namePrefix, @schema as [schema]
		from @Range
		for xml path('row')
	);

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- add in default date and name values
	set @sql = 'insert [' + @schema + '].[' + @namePrefix + '_Date_Dim] (Date_Value) values (''9999-12-31''); update [' + @schema + '].[' + @namePrefix + '_Date_Dim] set Day_of_Week_Name = DATENAME(weekday, Date_Value), Month_Name = DATENAME(month, Date_Value)';
	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- create dimention tables. fill them too
	set @template = 'create table [[schema]].[[namePrefix]_[Column_Name]_Dim] ([[namePrefix]_[Column_Name]_Dim_ID] int NOT NULL identity primary key, [[Column_Name]] [Data_Type][Scaling] NOT NULL); insert [[schema]].[[namePrefix]_[Column_Name]_Dim] ([[Column_Name]]) select distinct isnull([[Column_Name]], [Null_Replacement]) from [stagingTable] order by 1; ';

	set @replacementXml = (
		select *, @stagingTable as stagingTable, @namePrefix as namePrefix, @schema as [schema]
		from @StagingColumn
		where [Action] = 'dimention'
		for xml path('row')
	);

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- -----------------------------------------------------------
	-- -----------------------------------------------------------
	-- before we create a fact table, prep a fact column temp table.
	-- does not include the fact ID column.
	-- Action - straight, join, datepart (part of datetime), date (dates join to date dim)
	declare @FactColumn table (
		ID int identity
		, Staging_Column sysname -- insert fact
		, [Action] varchar(20) 
		, Fact_Column varchar(128) -- create fact, insert fact
		, Data_Type varchar(20) -- create fact
		, Null_Replacement varchar(20) -- insert fact
		, Dimention_Table varchar(128) -- insert fact
		, Alias varchar(5)
		, Dimention_Key_Column varchar(128) -- insert fact
	)

	insert @FactColumn (Staging_Column, [Action], Data_Type, Null_Replacement)
	select Staging_Column, [Action], Data_Type, Null_Replacement
	from (
			-- 2 columns created for every date/time column in staging. 
			-- "+ 0.1" means this one goes just above the other.
			select 
				ID + 0.1 as Sort_Order,
				Column_Name as Staging_Column,
				'datepart' as [Action],
				'date' as Data_Type,
				Null_Replacement
			from @StagingColumn
			where Data_Type like '%datetime%'
		union
			select 
				ID + 0.2 as Sort_Order,
				Column_Name as Staging_Column,
				case [Action] when 'dimention' then 'join' else 'straight' end as [Action],
				Data_Type + Scaling as Data_Type,
				Null_Replacement
			from @StagingColumn
	) t
	order by Sort_Order;

	update @FactColumn set
		[Action] = 'date'
	where [Action] = 'straight' and Data_Type = 'date'

	update @FactColumn set
		Data_Type = 'int'
	where [Action] = 'join'

	update @FactColumn set 
		Fact_Column = 
			case [Action] 
				when 'join' then @namePrefix + '_' + Staging_Column + '_Dim_ID' 
				when 'datepart' then @namePrefix + '_' + Staging_Column 
				else /*straight or date*/ Staging_Column 
			end,
		Dimention_Table = 
			case [Action] 
				when 'straight' then null 
				when 'join' then Staging_Column
				else /*date or datepart*/ 'Date' 
			end

	update targt set Alias = sourc.Alias
	from @FactColumn targt
	join (
		select ID, 'd' + cast(ROW_NUMBER() over (order by ID) as varchar) as Alias
		from (select ID from @FactColumn where Dimention_Table is not null) t
	) sourc on targt.ID = sourc.ID
	
	update @FactColumn set 
		Dimention_Key_Column = 
			case [Action] 
				when 'straight' then null 
				when 'join' then Fact_Column 
				else /*date or datepart*/ 'Date_Value' 
			end

	-- -----------------------------------------------------------
	-- -----------------------------------------------------------

	-- create fact table
	set @template = ', [[Fact_Column]] [Data_Type] NOT NULL';

	set @replacementXml = (select * from @FactColumn for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @sql = 'create table [' + @schema + '].[' + @namePrefix + '_Fact] ([' + @namePrefix + '_Fact_ID] int identity primary key' + @sql + '); ';

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- fill fact table (first, build joins. then, build insert statement)
	declare @factInsertMaster nvarchar(max) = 'insert [[schema]].[[namePrefix]_Fact] ([Fact_Columns]) SELECT [Staging_Columns] FROM [stagingTable] s[joins];';

	set @template = ' join [[schema]].[[namePrefix]_[Dimention_Table]_Dim] [Alias] on isnull(s.[[Staging_Column]], [Null_Replacement]) = [Alias].[[Staging_Column]]'

	set @replacementXml = (select * from @FactColumn where [Action] = 'join' for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @factInsertMaster = REPLACE(@factInsertMaster, '[joins]', @sql)

	set @sql = stuff((select ', [' + Fact_Column + ']' from @FactColumn order by ID for xml path('')), 1, 2, '') -- stuff chops off leading comma

	set @factInsertMaster = REPLACE(@factInsertMaster, '[Fact_Columns]', @sql)

	set @sql = null

	select @sql = ISNULL(@sql + ', ', '') + 
		case [Action]
			when 'straight' then 's.[' + Staging_Column + ']'
			when 'join' then Alias + '.[' + Dimention_Key_Column + ']'
			else /*date or datepart*/ 'isnull(cast(s.[' + Staging_Column + '] as date), ''9999-12-31'')'
		end
	from @FactColumn
	order by ID

	set @factInsertMaster = REPLACE(@factInsertMaster, '[Staging_Columns]', @sql)

	set @sql = @factInsertMaster

	set @sql = REPLACE(@sql, '[stagingTable]', @stagingTable);

	set @sql = REPLACE(@sql, '[namePrefix]', @namePrefix);

	set @sql = REPLACE(@sql, '[schema]', @schema);

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- create foreign keys from fact table to dimention tables
	set @template = 'alter table [[schema]].[[namePrefix]_Fact] add constraint [fk_[namePrefix]_[Staging_Column]] foreign key ([[Fact_Column]]) references [[schema]].[[namePrefix]_[Dimention_Table]_Dim] ([[Dimention_Key_Column]]); ';

	set @replacementXml = (select * from @FactColumn where [Action] in ('join', 'date') for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @sql = REPLACE(@sql, '[namePrefix]', @namePrefix);

	set @sql = REPLACE(@sql, '[schema]', @schema);

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- drop view
	set @sql = 'if OBJECT_ID(''[' + @schema + '].[vw_' + @namePrefix + ']'') is not null drop view [' + @schema + '].[vw_' + @namePrefix + '];'
	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	-- create view
	declare @viewMaster nvarchar(max) = 'create view [[schema]].[vw_[namePrefix]] ([Column_List]) as select [Columns_Out] from [[schema]].[[namePrefix]_Fact] f[joins];'

	set @template = ' join [[schema]].[[namePrefix]_[Dimention_Table]_Dim] [Alias] on f.[[Fact_Column]] = [Alias].[[Dimention_Key_Column]]'

	set @replacementXml = (select * from @FactColumn where [Action] in ('join', 'date', 'datepart') for xml path('row'));

	set @sql = star.fn_TemplateMerge(@template, @replacementXml, '')

	set @viewMaster = REPLACE(@viewMaster, '[joins]', @sql)

	set @sql = null

	select @sql = ISNULL(@sql + ', ', '') + 
		case [Action] 
			when 'join' then '[' + Staging_Column + ']' 
			else '[' + Fact_Column + ']' 
		end
	from @FactColumn
	order by ID;

	set @viewMaster = REPLACE(@viewMaster, '[Column_List]', @sql)

	set @sql = null

	select @sql = ISNULL(@sql + ', ', '') + 
		case [Action] 
			when 'straight' then 'f.[' + Fact_Column + ']' 
			when 'join' then Alias + '.[' + Staging_Column + ']'
			else /*date or datepart*/ Alias + '.[Date_Value]' 
		end
	from @FactColumn
	order by ID;

	set @viewMaster = REPLACE(@viewMaster, '[Columns_Out]', @sql)

	set @sql = @viewMaster

	set @sql = REPLACE(@sql, '[namePrefix]', @namePrefix);

	set @sql = REPLACE(@sql, '[schema]', @schema);

	print @sql; -- ==========
	exec (@sql); -- ----------------------------------------------

	/*
	*/
go
