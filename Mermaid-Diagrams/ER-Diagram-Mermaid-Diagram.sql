-- ================================================
-- This script returns Mermaid code that displays an ER diagram for the tables around a "Focal_Table".
-- These results can be used in an Azure DevOps wiki page.
-- Mermaid erDiagram decleration is experimental and not supported by Azure Devops wiki.
-- So instead, the flowchart declaration "graph RL" is used. RL means Right-to-Left so that FKs are arrows pointing left.
-- https://mermaid-js.github.io/mermaid/#/flowchart -- documentation
-- https://mermaid-js.github.io/mermaid-live-editor -- for testing
-- Dotted line means the FK column is nullable.
-- This script assumes all FKs are enforced. It does not search for unenforced FKs.
-- ================================================

declare @Focal_Table sysname = '[Core].[ClientAttribute]';

-- ====================================================
-- Make up Node Labels for all the tables
declare @Table_Node_Label table (Table_ID int, Node_Label sysname);

with t as (
	select 
		[object_id] as TableID,
		OBJECT_SCHEMA_NAME([object_id]) as SchemaName, 
		OBJECT_NAME([object_id]) as TableName, 
		UPPER(LEFT([name], 1)) as IDPrefix
	from sys.tables 
)
insert @Table_Node_Label (Table_ID, Node_Label)
select 
	TableID, 
	concat(
		IDPrefix
		, ROW_NUMBER() over (partition by IDPrefix order by SchemaName, TableName)
		, '[', SchemaName, '.', TableName, ']'
	)
from t

print CONCAT(@@ROWCOUNT, ' total tables')

-- ====================================================
-- Replace @Focal_Table with a Node_Label
set @Focal_Table = (select Node_Label from @Table_Node_Label where Table_ID = OBJECT_ID(@Focal_Table))

-- ====================================================
-- Collect all the relationships into a table variable.
declare @All_Relationships table (PK sysname, FK sysname, Is_Nullable bit, unique (PK, FK));

insert @All_Relationships
select 
	r.Node_Label, 
	p.Node_Label, 
	MAX(COLUMNPROPERTY(parent_object_id, COL_NAME(parent_object_id, parent_column_id), 'AllowsNull'))
from sys.foreign_key_columns fk
join @Table_Node_Label r on fk.referenced_object_id = r.Table_ID
join @Table_Node_Label p on fk.parent_object_id = p.Table_ID
group by fk.parent_object_id, fk.referenced_object_id, r.Node_Label, p.Node_Label;

print CONCAT(@@ROWCOUNT, ' enforced FKs')

-- ====================================================
-- Collect all the relationships that are around the "Focal_Table".
declare
	@GEN_GRANDPARENT int = 1,
	@GEN_PARENT int = 2,
	@GEN_SIBLING int = 3,
	@GEN_SPOUSE int = 4,
	@GEN_CHILD int = 5,
	@GEN_GRANDCHILD int = 6;

declare @These_Relationships table (PK sysname, FK sysname, Is_Nullable bit, Generation_Code tinyint); -- no uniqueness

-- ===== CHILD ===== --
insert @These_Relationships select *, @GEN_CHILD from @All_Relationships where PK = @Focal_Table;

print CONCAT(@@ROWCOUNT, ' children')

-- ===== PARENT ===== --
insert @These_Relationships select *, @GEN_PARENT from @All_Relationships where FK = @Focal_Table;

print CONCAT(@@ROWCOUNT, ' parents')

-- Dont show too many
if (select COUNT(*) from @These_Relationships) < 20 begin;
	-- ===== GRANDCHILD ===== --
	insert @These_Relationships
	select s.*, @GEN_GRANDCHILD
	from @All_Relationships s 
	join @These_Relationships t on s.PK = t.FK and t.Generation_Code = @GEN_CHILD;

	if @@ROWCOUNT > 10 delete @These_Relationships where Generation_Code = @GEN_GRANDCHILD;

	print CONCAT(@@ROWCOUNT, ' grandchildren')

	-- ===== GRANDPARENT ===== --
	insert @These_Relationships
	select s.*, @GEN_GRANDPARENT
	from @All_Relationships s 
	join @These_Relationships t on s.FK = t.PK and t.Generation_Code = @GEN_PARENT;

	if @@ROWCOUNT > 10 delete @These_Relationships where Generation_Code = @GEN_GRANDPARENT;

	print CONCAT(@@ROWCOUNT, ' grandparents')

	-- Dont show too many
	if (select COUNT(*) from @These_Relationships) < 25 begin;
		-- ===== SIBLING ===== --
		insert @These_Relationships
		select s.*, @GEN_SIBLING
		from @All_Relationships s 
		join @These_Relationships t on s.PK = t.PK and t.Generation_Code = @GEN_PARENT; -- sibling is child of parent

		if @@ROWCOUNT > 10 delete @These_Relationships where Generation_Code = @GEN_SIBLING;

		print CONCAT(@@ROWCOUNT, ' siblings')

		-- ===== SPOUSE ===== --
		insert @These_Relationships 
		select s.*, @GEN_SPOUSE
		from @All_Relationships s 
		join @These_Relationships t on s.FK = t.FK and t.Generation_Code = @GEN_CHILD; -- spouse is parent of child

		if @@ROWCOUNT > 10 delete @These_Relationships where Generation_Code = @GEN_SPOUSE;

		print CONCAT(@@ROWCOUNT, ' spouses')
	end;
end;

-- ====================================================
-- output
with t as (
	select PK as Node_Label from @These_Relationships
	union
	select FK as Node_Label from @These_Relationships
)
select 'graph RL' as [%% code]
union all
select r.FK + IIF(r.Is_Nullable = 1, '-.->', '-->') + r.PK
	from @All_Relationships r
	where PK in (select Node_Label from t)
		and FK in (select Node_Label from t)
union all
select CONCAT('%% ', COUNT(*), ' ', g.Gen_Label, ' relationships')
	from @These_Relationships r
	join (values 
		(1, 'GRANDPARENT'), 
		(2, 'PARENT'), 
		(3, 'SIBLING'), 
		(4, 'SPOUSE'), 
		(5, 'CHILD'), 
		(6, 'GRANDCHILD')
	) g (Generation_Code, Gen_Label) on r.Generation_Code = g.Generation_Code
	group by r.Generation_Code, g.Gen_Label
union all
select CONCAT('%% ', COUNT(*), ' total initial relationships') from @These_Relationships

