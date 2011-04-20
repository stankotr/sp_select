if OBJECT_ID('sp_select') is not null
  begin
    print 'Dropping procedure sp_select...'
    drop procedure sp_select
  end
 GO
/*
Created by: Filip De Vos
http://foxtricks.blogspot.com

Based on the post by Jonathan Kehayias
http://sqlblog.com/blogs/jonathan_kehayias/archive/2009/09/29/what-session-created-that-object-in-tempdb.aspx

Usage:
create table #lala (id int, value varchar(100))
insert into #lala values (10, 'hihi'), (11, 'haha')

exec sp_select 'tempdb..#lala'

exec sp_select 'msdb.dbo.MSdbms'

  CREATE TABLE #temp (id int, name varchar(200))
        INSERT INTO #temp VALUES (1, 'Filip')
        INSERT INTO #temp VALUES (2, 'Sam')

*/
CREATE PROCEDURE dbo.sp_select(@table_name sysname, @spid int = NULL, @max_pages int = 1000)
AS

  DECLARE @object_id int
        , @table     sysname
        , @db_name   sysname
        , @db_id     int
        , @file_name  varchar(MAX)  
        , @status    int
  
  IF PARSENAME(@table_name, 3) = 'tempdb'
    begin
      SET @table = PARSENAME(@table_name, 1)
      
      IF (SELECT COUNT(*)  from tempdb.sys.tables where name like @table + '[_]%') > 1
        BEGIN
            -- determine the default trace file
            SELECT @file_name = SUBSTRING(path, 0, LEN(path) - CHARINDEX('\', REVERSE(path)) + 1) + '\Log.trc'  
            FROM sys.traces   
            WHERE is_default = 1;  

            -- Match the spid with db_id and object_id via the default trace file
            SELECT top 1 @object_id = o.OBJECT_ID
            FROM sys.fn_trace_gettable(@file_name, DEFAULT) AS gt  
            JOIN tempdb.sys.objects AS o   
                 ON gt.ObjectID = o.OBJECT_ID  
            LEFT JOIN (SELECT distinct spid, dbid 
                         FROM master..sysprocesses 
                        WHERE spid = @spid or @spid is null) dr
              ON dr.spid = gt.SPID
            WHERE gt.DatabaseID = 2 
              AND gt.EventClass = 46 -- (Object:Created Event from sys.trace_events)  
              AND o.create_date >= DATEADD(ms, -100, gt.StartTime)   
              AND o.create_date <= DATEADD(ms, 100, gt.StartTime)
              AND o.name like @table + '[_]%'
              AND (gt.SPID = @spid or (@spid is null and dr.dbid = DB_ID()))
        END
      ELSE
        BEGIN
          SELECT @object_id = object_id from tempdb.sys.tables where name like @table + '[_]%'
        END
    END
  ELSE 
    SET @object_id = OBJECT_ID(@table_name)
  
  IF @object_id is null
    BEGIN 
      RAISERROR('The table [%s] does not exist', 16, 1, @table_name)
      RETURN (-1)
    END
  
  SET @db_id = DB_ID(PARSENAME(@table_name, 3))
    
  EXEC @status = master..sp_selectpages @object_id = @object_id, @db_id = @db_id, @max_pages = @max_pages
  
  RETURN (@status)
GO
if OBJECT_ID('sp_select') is null
  PRINT 'Failed to create procedure sp_select...'
ELSE
  PRINT 'Correctly created procedure sp_select...'
GO