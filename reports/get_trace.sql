DECLARE @tracefile nvarchar(max) = (
	SELECT cast(value as nvarchar(max))
	FROM fn_trace_getinfo(1)
	WHERE property = 2 -- 2 means file name
)

SELECT 
	c.[name] as category, 
	e.[name] as event_name, 
	t.HostName, 
	t.LoginName, 
	t.ApplicationName,
	CAST(t.StartTime as date), 
	COUNT(*)
FROM fn_trace_gettable(@tracefile, DEFAULT) t 
JOIN sys.trace_events e ON t.EventClass = e.trace_event_id
join sys.trace_categories c on e.category_id = c.category_id
where t.DatabaseID = DB_ID() 
	and HostName <> @@SERVERNAME 
	and t.StartTime > DATEADD(day, -2, GETDATE()) 
GROUP BY c.[name], e.[name], t.HostName, t.LoginName, t.ApplicationName, cast(t.StartTime as date)
order by COUNT(*) desc

SELECT top 1000 
	t.StartTime, 
	c.[name] as category,
	e.[name] as event_name, 
	t.EventClass,
	t.ObjectName,
	t.TextData,
	t.HostName, 
	t.LoginName,
	t.ApplicationName
FROM fn_trace_gettable(@tracefile, DEFAULT) t 
JOIN sys.trace_events e ON t.EventClass = e.trace_event_id
join sys.trace_categories c on e.category_id = c.category_id
where t.DatabaseID = DB_ID() and HostName <> @@SERVERNAME
ORDER BY t.StartTime desc
go
