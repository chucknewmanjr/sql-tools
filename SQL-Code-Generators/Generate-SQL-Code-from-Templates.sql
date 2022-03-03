--declare @table_name sysname = 'Core.EntityAttributeValue';
declare @table_name sysname = 'Core.EntityCountryCustomXref';

/*
	select OBJECT_NAME(c.object_id), c.column_id, c.name, c.is_nullable
	from sys.columns c
	join sys.foreign_keys fk on c.object_id = fk.parent_object_id
	where referenced_object_id = OBJECT_ID('[Core].[EntityVersion]')
*/

set nocount on;

drop table if exists #columns;

with idx as (
	select i.[type_desc], ic.column_id
	from sys.indexes i
	join sys.index_columns ic on i.object_id = ic.object_id and i.index_id = ic.index_id
	where i.object_id = OBJECT_ID(@table_name)
		and i.is_unique = 1 and ic.partition_ordinal = 0
)
select c.[name], isnull(uc.[type_desc], 'updated') as [type_desc], c.is_nullable
into #columns
from sys.columns c
left join idx uc on c.column_id = uc.column_id
where c.object_id = OBJECT_ID(@table_name)
	and c.[name] not in ('EntityVersionId', 'PartitionKey', 'CreatedBy', 'CreatedDt', 'UpdatedBy', 'UpdatedDt', 'SysStartTime', 'SysEndTime')

declare @section_template varchar(max) = '

	-- "COPY"
	-- One or more of the entity versions might have been copied. So copy these subordinate rows too.
	-- Do this first because the rows inserted here may get deleted or updated.
	INSERT [[@2_Part_Table_Name]] (
		EntityVersionId, PartitionKey, [[@Unique_Columns_v1]], [[@Updated_Columns_v1]], CreatedBy, UpdatedBy
	)
	SELECT 
		c.InsertedEntityVersionId, t.PartitionKey, [[@Unique_Columns_v2]], [[@Updated_Columns_v2]], @v_UserId, @v_UserId
	FROM [[@2_Part_Table_Name]] t
	JOIN @v_VersionCopy c
		ON t.EntityVersionId = c.OriginalEntityVersionId;

	-- Delete rows that match current but are not in the user''s entries.
	-- This happens to the current version plus any versions with VersionEndDt after as-of date.
	-- That includes the inserted "copy".
	-- Update before delete. Avoid repeated joins with this table variable.
	DECLARE @v_Deleted[[@Just_The_Table_Name]] TABLE ([[@PK_Column]] int NOT NULL PRIMARY KEY)

	UPDATE targt WITH (XLOCK)
	SET UpdatedBy = @v_UserId, UpdatedDt = GETUTCDATE()
	OUTPUT DELETED.[[@PK_Column]] INTO @v_Deleted[[@Just_The_Table_Name]]
	FROM [[@2_Part_Table_Name]] targt
	JOIN @v_UpdatedVersion uv -- The list of Entity-Version rows that got updated
		ON targt.EntityVersionId = uv.UpdatedEntityVersionId
	JOIN [[@2_Part_Table_Name]] cur -- The current version for comparison
		ON uv.CurrentEntityVersionId = cur.EntityVersionId
	LEFT JOIN @p_[[@Just_The_Table_Name]]Tbl tvp -- The user''s entries
		ON uv.EntityId = tvp.EntityId 
		AND [[@Unique_Columns_v4]]
	WHERE tvp.EntityId IS NULL;

	DELETE targt
	FROM [[@2_Part_Table_Name]] targt
	JOIN @v_Deleted[[@Just_The_Table_Name]] sourc 
		ON targt.[[@PK_Column]] = sourc.[[@PK_Column]];

	-- Update the rows that point to updated versions.
	-- Just like the versions, only update a value if the user''s entry doesn''t match the current value.
	UPDATE targt
	SET [[@Updated_Columns_v4]]
		UpdatedBy = @v_UserId, 
		UpdatedDt = GETUTCDATE()
	FROM [[@2_Part_Table_Name]] targt 
	JOIN @v_UpdatedVersion uv -- The list of Entity-Version rows that got updated
		ON targt.EntityVersionId = uv.UpdatedEntityVersionId
	JOIN [[@2_Part_Table_Name]] cur -- The current version for comparison
		ON uv.CurrentEntityVersionId = cur.EntityVersionId 
		AND [[@Unique_Columns_v5]]
	JOIN @p_[[@Just_The_Table_Name]]Tbl tvp -- The user''s entries
		ON uv.EntityId = tvp.EntityId 
		AND [[@Unique_Columns_v6]]
	WHERE [[@Updated_Columns_v5]];

	-- It''s not enough to insert the user''s entries that are missing.
	-- That''s because rows might be missing from earlier versions as well.
	-- A row is inserted for a version if it''s missing from both that version and the current version.
	INSERT [[@2_Part_Table_Name]] (
		EntityVersionId, PartitionKey, [[@Unique_Columns_v1]], [[@Updated_Columns_v1]], CreatedBy, UpdatedBy
	)
	SELECT uv.UpdatedEntityVersionId, @v_PartitionKey, [[@Unique_Columns_v3]], [[@Updated_Columns_v3]], @v_UserId, @v_UserId
	FROM @p_[[@Just_The_Table_Name]]Tbl tvp -- The user''s entries
	JOIN @v_UpdatedVersion uv -- The list of Entity-Version rows that got updated
		ON tvp.EntityId = uv.EntityId
	LEFT JOIN [[@2_Part_Table_Name]] ver WITH (HOLDLOCK, UPDLOCK) -- This version
		-- HOLDLOCK avoids unique key violation, UPDLOCK avoids deadlock
		ON uv.UpdatedEntityVersionId = ver.EntityVersionId 
		AND ver.PartitionKey = @v_PartitionKey 
		AND [[@Unique_Columns_v7]]
	LEFT JOIN  [[@2_Part_Table_Name]] cur WITH (HOLDLOCK, UPDLOCK) -- The current version
		-- HOLDLOCK avoids unique key violation, UPDLOCK avoids deadlock
		ON uv.CurrentEntityVersionId = cur.EntityVersionId 
		AND cur.PartitionKey = @v_PartitionKey 
		AND [[@Unique_Columns_v4]]
	WHERE ver.EntityVersionId IS NULL
		AND cur.EntityVersionId IS NULL;

	-- Insert for new entities
	INSERT [[@2_Part_Table_Name]] (
		EntityVersionId, PartitionKey, [[@Unique_Columns_v1]], [[@Updated_Columns_v1]], CreatedBy, UpdatedBy
	)
	SELECT ie.EntityVersionId, @v_PartitionKey, [[@Unique_Columns_v3]], [[@Updated_Columns_v3]], @v_UserId, @v_UserId
	FROM @p_[[@Just_The_Table_Name]]Tbl tvp
	JOIN @v_InsertedEntity ie
		ON tvp.[Guid] = ie.[Guid];
'

declare @results varchar(MAX) = @section_template;

declare @table_list varchar(MAX) = (select char(10) + '-- Core.' + OBJECT_NAME(parent_object_id) from sys.foreign_keys where referenced_object_id = OBJECT_ID('[Core].[EntityVersion]') order by 1 for xml path(''));

set @results = @table_list + @results;

-- powerwash name
set @table_name = CONCAT('[Core].[', OBJECT_NAME(OBJECT_ID(@table_name)), ']');

declare @stuff_len int

set @results = REPLACE(@results, '[[@2_Part_Table_Name]]', CONCAT('[Core].[', OBJECT_NAME(OBJECT_ID(@table_name)), ']'));

declare @pk_column sysname = (select [name] from #columns where [type_desc] = 'CLUSTERED')

set @results = REPLACE(@results, '[[@PK_Column]]', @pk_column);

set @results = REPLACE(@results, '[[@Just_The_Table_Name]]', OBJECT_NAME(OBJECT_ID(@table_name)));

declare @nl char(3) = char(10) + char(9) + char(9) -- new line is a line feed plus 3 tabs

select * from #columns

declare @Unique_Column_SQL nvarchar(MAX) = 'select [name] from #columns where [type_desc] = ''NONCLUSTERED'''

declare @Updated_Column_SQL nvarchar(MAX) = 'select [name] from #columns where [type_desc] = ''updated'''

declare @column_template_Table table (
	Column_Template_ID int identity primary key,
	Place_Holder sysname, -- unique
	Column_SQL nvarchar(MAX) not null,
	Column_Template varchar(MAX) not null,
	Prefix_Len int not null
)

insert @column_template_Table values ( -- ===== for UNIQUE columns =====
	'[[@Unique_Columns_v1]]',
	@Unique_Column_SQL,
	', [[Column_Name]]',
	2
), (
	'[[@Unique_Columns_v2]]',
	@Unique_Column_SQL,
	', t.[[Column_Name]]',
	2
), (
	'[[@Unique_Columns_v3]]',
	@Unique_Column_SQL,
	', tvp.[[Column_Name]]',
	2
), (
	'[[@Unique_Columns_v4]]',
	@Unique_Column_SQL,
	@nl + 'AND cur.[[Column_Name]] = tvp.[[Column_Name]]',
	7
), (
	'[[@Unique_Columns_v5]]',
	@Unique_Column_SQL,
	'AND targt.[[Column_Name]] = cur.[[Column_Name]]',
	4
), (
	'[[@Unique_Columns_v6]]',
	@Unique_Column_SQL,
	'AND targt.[[Column_Name]] = tvp.[[Column_Name]]',
	4
), (
	'[[@Unique_Columns_v7]]',
	@Unique_Column_SQL,
	'AND tvp.[[Column_Name]] = ver.[[Column_Name]]',
	4
), ( -- ===== for UPDATED columns =====
	'[[@Updated_Columns_v1]]',
	@Updated_Column_SQL,
	', [[Column_Name]]',
	2
), (
	'[[@Updated_Columns_v2]]',
	@Updated_Column_SQL,
	', t.[[Column_Name]]',
	2
), (
	'[[@Updated_Columns_v3]]',
	@Updated_Column_SQL,
	', tvp.[[Column_Name]]',
	2
), (
	'[[@Updated_Columns_v4]]', -- we may need a version of this for NULLABLE columns
	@Updated_Column_SQL,
	@nl + '[[Column_Name]] = IIF(tvp.[[Column_Name]] = cur.[[Column_Name]], targt.[[Column_Name]], tvp.[[Column_Name]]),',
	3
), (
	'[[@Updated_Columns_v5]]', -- we may need a version of this for NULLABLE columns
	@Updated_Column_SQL,
	@nl + 'AND targt.[[Column_Name]] <> IIF(tvp.[[Column_Name]] = cur.[[Column_Name]], targt.[[Column_Name]], tvp.[[Column_Name]])',
	7
);

if @results is null
	throw 50000, 'Some replacement must have been null', 1;

if exists (select 1 from @column_template_Table group by Place_Holder having COUNT(*) > 1)
	throw 50000, 'Place_Holder must be unique', 1;

if exists (select * from @column_template_Table where Column_Template not like '%[[][[]Column_Name]]%')
	throw 50000, 'Template must contain the [[Column_Name]] placeholder', 1;

declare @this int = (select MAX(Column_Template_ID) from @column_template_Table)
declare @Place_Holder sysname;
declare @Column_SQL nvarchar(MAX);
declare @Column_Template varchar(MAX);
declare @Prefix_Len int;
declare @Column_Name_Table table (Column_Name sysname);
declare @Replacement varchar(MAX);

while @this > 0 begin;
	select
		@Place_Holder = Place_Holder,
		@Column_SQL = Column_SQL,
		@Column_Template = Column_Template,
		@Prefix_Len = Prefix_Len
	from @column_template_Table
	where Column_Template_ID = @this;

	delete @Column_Name_Table;

	insert @Column_Name_Table exec (@Column_SQL);

	set @Replacement = (
		select REPLACE(@Column_Template, '[[Column_Name]]', Column_Name)
		from @Column_Name_Table
		for xml path('')
	)

	set @Replacement = REPLACE(@Replacement, '&lt;', '<')

	set @Replacement = REPLACE(@Replacement, '&gt;', '>')

	set @Replacement = STUFF(@Replacement, 1, @Prefix_Len, '')

	--print '"' + @Replacement + '"'
	
	set @results = REPLACE(@results, @Place_Holder, ISNULL(@Replacement, ''));
	
	set @this -= 1;
end;

print @results
