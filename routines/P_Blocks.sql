create or alter proc Tools.P_Blocks as
	/*	-- ===== TEST SCRIPT =====
		-- To cause a block, run the top half in one session and the whole thing in another.
		-- To release the block, run the bottom half in the first session.
		if OBJECT_ID('t') is null select 1 x into t;
		begin tran;
		select * from t with (xlock);
		rollback;
		drop table if exists t;
	*/
	select
		DB_NAME(p.[dbid]) as db,
		p.spid,
		p.blocked as blocked_by,
		l.locks,
		p.waittime / 1000 / 60 as wait_mins,
		p.lastwaittype,
		USER_NAME(p.[uid]) as username,
		p.open_tran,
		p.[status],
		p.hostname,
		p.[program_name],
		p.cmd,
		p.loginame,
		SUBSTRING(
			(select [text] from sys.dm_exec_sql_text(p.[sql_handle])),
			stmt_start / 2 + 1,
			IIF(stmt_end = -1, 4000, (stmt_end - stmt_start) / 2 + 1)
		) as SQL_Statement
	from sys.sysprocesses p
	left join (select req_spid, COUNT(*) as locks from [master].dbo.syslockinfo group by req_spid) l on p.spid = l.req_spid
	where p.blocked <> 0 -- include the blocked session
		or p.spid in (select blocked from sys.sysprocesses) -- include the blocking session
		or (
			p.[dbid] = DB_ID() -- exclude other DBs
			and p.spid <> @@SPID -- exclude this session
			and l.locks is not null -- exclude sessions without locks
			and (
				l.locks > 1 -- include sessions with multiple locks
				or (
					l.locks = 1 -- include sessions with a single lock. But only if ...
					and (
						p.lastwaittype <> 'MISCELLANEOUS' -- but only if it's not the usual
						or p.[status] <> 'sleeping'
						or p.cmd <> 'AWAITING COMMAND'
					)
				)
			)
		)
