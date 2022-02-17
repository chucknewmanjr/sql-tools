declare
	@max_duration_sec real = 5,
	@Test_Start datetime = '2020-04-28 7:00 PM',
	@Test_Hours int = 5,
	@UTC_Offset int = 4 -- 5 means EST (standard) 4 means EDT (savings)
	--, @Object_Name sysname = 'EntMgmt.USP_DeleteFilingGroups';
	;

with query as (
	-- get max duration for each query in a proc
	select 
		p.query_id,
		SUM(rs.count_executions) as count_executions, 
		MAX(rs.[max_duration]) as [max_duration],
		COUNT(*) as plan_count
	from sys.query_store_runtime_stats_interval rsi
	join sys.query_store_runtime_stats rs on rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
	join sys.query_store_plan p on rs.plan_id = p.plan_id
	where rsi.end_time > DATEADD(hour, @UTC_Offset, @Test_Start)
		and rsi.start_time < DATEADD(hour, @UTC_Offset + @Test_Hours, @Test_Start)
	group by p.query_id
)
, obj as (
	-- join in the object and query text columns
	select 
		q.[object_id],
		LEFT(qt.query_sql_text, 3000) as query_sql_text,
		IIF(query_sql_text like 'SELECT StatMan([[]SC0]%', CHARINDEX(' FROM [', query_sql_text), NULL) from_pos,
		query.count_executions, 
		query.[max_duration],
		query.plan_count
	from query
	join sys.query_store_query q on query.query_id = q.query_id
	join sys.query_store_query_text qt on q.query_text_id = qt.query_text_id
)
, correction as (
	-- Figure out the correct object_id.
	-- This is slow. It's only needed when the object IDs have changed since the test.
	select obj.query_sql_text, m.[object_id]
	from (
		select distinct query_sql_text 
		from obj 
		where [object_id] <> 0
			and OBJECT_NAME([object_id]) is null
	) obj
	join sys.sql_modules m
		on 
		REPLACE(REPLACE(m.[definition], CHAR(9), ' '), CHAR(13) + CHAR(10), '  ')
		like 
		'%' + 
		REPLACE(REPLACE(REPLACE(IIF(LEFT(obj.query_sql_text, 1) = '(', 
		STUFF(obj.query_sql_text, 1, NULLIF(CHARINDEX(')', obj.query_sql_text), 0), '')
		, obj.query_sql_text), CHAR(9), ' '), CHAR(13) + CHAR(10), '  '), '[', '[[]') + 
		'%'
)
, stored_proc as (
	-- join in the correct object_id
	select 
		obj.*,
		COALESCE(
			'[' + OBJECT_SCHEMA_NAME(obj.[object_id]) + '].[' + OBJECT_NAME(obj.[object_id]) + ']', 
			'[' + OBJECT_SCHEMA_NAME(correction.[object_id]) + '].[' + OBJECT_NAME(correction.[object_id]) + ']',
			'UPDATE STATS ' + SUBSTRING(obj.query_sql_text, from_pos + 6, ISNULL(NULLIF(CHARINDEX('] TABLESAMPLE SYSTEM (', obj.query_sql_text, from_pos), 0), CHARINDEX('] WITH (READUNCOMMITTED) ', obj.query_sql_text, from_pos)) - from_pos - 5),
			left(obj.query_sql_text, 50) + ' ...'
		) as proc_name
	from obj
	left join correction on obj.query_sql_text = correction.query_sql_text
)
select
	ROUND(SUM([max_duration]) / 1e6, 3) as Max_Duration_Secs,
	Proc_Name,
	MAX(count_executions) as Total_Plan_Exec_Count,
	SUM(plan_count) as Plan_Count
from stored_proc
group by proc_name
having SUM([max_duration]) > @max_duration_sec * 1e6
order by Max_Duration_Secs desc;

--select 
--	FORMAT(DATEADD(hour, -@UTC_Offset, rsi.start_time), 'M/d/yy h:mm tt') as start_time, 
--	ROUND(MAX(rs.[max_duration]) / 1e6, 3) as Max_Duration_Secs, 
--	SUM(rs.count_executions) as Plan_Exec_Count, 
--	COUNT(*) as Plan_Count, 
--	qt.query_sql_text, 
--	CAST(p.query_plan as xml) as Query_Plan
--from sys.query_store_runtime_stats_interval rsi
--join sys.query_store_runtime_stats rs on rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
--join sys.query_store_plan p on rs.plan_id = p.plan_id
--join sys.query_store_query q on p.query_id = q.query_id
--join sys.query_store_query_text qt on q.query_text_id = qt.query_text_id
--where rsi.end_time > DATEADD(hour, @UTC_Offset, @Test_Start)
--	and rsi.start_time < DATEADD(hour, @UTC_Offset + @Test_Hours, @Test_Start)
--	and q.[object_id] = OBJECT_ID(@Object_Name)
--group by rsi.start_time, rsi.end_time, qt.query_sql_text, p.query_plan;
--go

