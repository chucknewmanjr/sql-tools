WITH t1 AS (
	SELECT --top 60 
		Timestamp_UTC, CAST(event_data AS XML) AS event_data_XML
	FROM master.sys.fn_xe_telemetry_blob_target_read_file('dl', null, null, null)
	--order by Timestamp_UTC desc
), t2 as (
	select
		Timestamp_UTC,
		event_data_XML.value('(/event/data[@name=''database_name'']/value)[1]', 'sysname') AS DB,
		event_data_XML.query('/event/data[@name=''xml_report'']/value/deadlock') AS Deadlock_XML
	from t1
)
SELECT
	CAST(Timestamp_UTC as date) as Deadlock_Date,
	DB,
	stuff(Deadlock_XML.value('(/deadlock/resource-list/pagelock/@objectname)[1]', 'sysname'), 1, 37, '') AS Res1_Name,
	stuff(Deadlock_XML.value('(/deadlock/resource-list/pagelock/@objectname)[2]', 'sysname'), 1, 37, '') AS Res2_Name,

	stuff(Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame/@procname)[1]', 'sysname'), 1, 37, '') AS Proc1_Name,
	stuff(Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame/@procname)[2]', 'sysname'), 1, 37, '') AS Proc2_Name,
	Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame/@line)[1]', 'int') AS Proc1_Line,
	Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame/@line)[2]', 'int') AS Proc2_Line

	,Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame)[1]', 'varchar(max)') AS Proc1_SQL
	,Deadlock_XML.value('(/deadlock/process-list/process/executionStack/frame)[2]', 'varchar(max)') AS Proc2_SQL
	,Deadlock_XML
FROM t2
order by Timestamp_UTC desc;
