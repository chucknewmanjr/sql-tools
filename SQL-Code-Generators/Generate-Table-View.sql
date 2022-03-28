-- ===== to-do =====
-- for the start table, make from clause. DONE
-- include all columns except the FKs. DONE
-- Add the FKs to a to-do list. DONE
-- process the to-do list. DONE
-- make a join to the referenced table. DONE
-- if the fk column is nullable, use left join. DONE

-- process the columns in the unique index.
-- if it doesn't have a unique index, use all the columns.
-- if any of the columns are a FK, add them to the to-do list.
-- add the remaining columns to the select.

declare @Table_Name sysname = '[dbo].[County_Event]';

declare @Table_ID int = OBJECT_ID(@Table_Name);

declare @Table table (Table_ID int, Table_Name sysname, Alias sysname);

insert @Table
select 
	[object_id],
	'[' + OBJECT_SCHEMA_NAME([object_id]) + '].[' + [name] + ']',
	CONCAT(
		LEFT([name], 1), 
		ROW_NUMBER() over (partition by LEFT([name], 1) order by LEN([name]), [name])
	)
from sys.tables;

declare @Join table (Join_ID int identity, Join_Text varchar(MAX));

insert @Join 
select 'from ' + Table_Name + ' ' + Alias
from @Table
where Table_ID = @Table_ID;

declare @SelectColumn table (Column_ID int, Column_Name sysname);

insert @SelectColumn
select c.column_id, a.Alias + '.'
from sys.columns c
join @Table a on c.[object_id] = a.Table_ID
left join sys.foreign_keys fk on c.[object_id] = fk.parent_object_id
where c.[object_id] = @Table_ID
	and fk.[object_id] is null;

declare @ToDoList table (ToDoList_ID int identity, FK_ID int);

insert @ToDoList
select [object_id]
from sys.foreign_keys
where parent_object_id = @Table_ID;



declare @ToDoList_ID int = 1;

while @ToDoList_ID <= (select max(ToDoList_ID) from @ToDoList) begin;
	with t as (
		select
			red.Table_Name,
			red.Alias,
			c.is_nullable,
			CONCAT(
				' and ', ring.Alias,
				'.', c.[name],
				' = ', red.Alias,
				'.', COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
			) as Join_Column
		from @ToDoList tdl
		join sys.foreign_key_columns fkc on tdl.FK_ID = fkc.constraint_object_id
		join @Table red on fkc.referenced_object_id = red.Table_ID
		join @Table ring on fkc.parent_object_id = ring.Table_ID
		join sys.columns c 
			on fkc.parent_object_id = c.[object_id] 
			and fkc.parent_column_id = c.column_id
		where tdl.ToDoList_ID = @ToDoList_ID
	)
	insert @Join
	select CONCAT(
			IIF(MAX(is_nullable + 0) = 1, 'left join ', 'join '),
			Table_Name, ' ', Alias,
			STUFF((select Join_Column + '' from t for xml path('')), 1, 4, ' on')
		)
	from t
	group by Table_Name, Alias




	set @ToDoList_ID += 1;
end;

select * from @Join

--from [dbo].[County_Event] C2
--join [dbo].[County] C1 on C2.County_ID = C1.County_ID

