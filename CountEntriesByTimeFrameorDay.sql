
/* Create 2 reports : 
		1 . counts ContractParker movements
		2.  Counts SPT Movements
		
		DepENDencies:  ofir_CountMovements function must be installed */

/* Get the whole range of time from the related tabls */

DECLARE @starttime date , 
		@ENDtime date 




/* ContractParkers Report */
DECLARE @report table (ReportType varchar(20),[date] date,daily int,[00-06] int,[06-08] int,[08-10] int,[10-12] int,[12-14] int,[14-16] int,[16-18] int,[18-20] int,[20-22] int,[22-24] int)

SET @StartTime=(SELECT cast(min(time) as date) from dbo.ContractParkerMovements)
SET @ENDTime=(SELECT cast(max(time) as date) from dbo.ContractParkerMovements)


/* Looping Through dates and update the Report Table */
	WHILE @starttime <= @ENDtime
	BEGIN
	INSERT INTO @report (ReportType,date,daily,[00-06],[06-08],[08-10],[10-12],[12-14],[14-16],[16-18],[18-20],[20-22],[22-24])
 
	SELECT 'ContractParkers',@starttime,dbo.[ofir_CountMovements] (@starttime,null,null,1,1),
				   dbo.[ofir_CountMovements] (@starttime,0,6,1,1),
				   dbo.[ofir_CountMovements] (@starttime,6,8,1,1),
				   dbo.[ofir_CountMovements] (@starttime,8,10,1,1),
				   dbo.[ofir_CountMovements] (@starttime,10,12,1,1),
				   dbo.[ofir_CountMovements] (@starttime,12,14,1,1),
				   dbo.[ofir_CountMovements] (@starttime,14,16,1,1),
				   dbo.[ofir_CountMovements] (@starttime,16,18,1,1),
				   dbo.[ofir_CountMovements] (@starttime,18,20,1,1),
				   dbo.[ofir_CountMovements] (@starttime,20,22,1,1),
				   dbo.[ofir_CountMovements] (@starttime,22,24,1,1)


	SET @starttime=dateadd(day,1,@starttime)
	END
 SELECT * from @report where daily >0

/* ShotTermParkers Report */

DECLARE @report2 table (ReportType varchar(20),[date] date,daily int,[00-06] int,[06-08] int,[08-10] int,[10-12] int,[12-14] int,[14-16] int,[16-18] int,[18-20] int,[20-22] int,[22-24] int)

 SET @starttime = (SELECT cast(min(time) as date) from dbo.ParkingMovements)
 SET @ENDtime = (SELECT cast(max(time) as date) from dbo.ParkingMovements)

	WHILE @starttime <= @ENDtime
	BEGIN
	INSERT INTO @report2 (ReportType,date,daily,[00-06],[06-08],[08-10],[10-12],[12-14],[14-16],[16-18],[18-20],[20-22],[22-24])
 
	SELECT 'ShortTermParkers',@starttime,dbo.[ofir_CountMovements] (@starttime,null,null,2,1),
				   dbo.[ofir_CountMovements] (@starttime,0,6,2,1),
				   dbo.[ofir_CountMovements] (@starttime,6,8,2,1),
				   dbo.[ofir_CountMovements] (@starttime,8,10,2,1),
				   dbo.[ofir_CountMovements] (@starttime,10,12,2,1),
				   dbo.[ofir_CountMovements] (@starttime,12,14,2,1),
				   dbo.[ofir_CountMovements] (@starttime,14,16,2,1),
				   dbo.[ofir_CountMovements] (@starttime,16,18,2,1),
				   dbo.[ofir_CountMovements] (@starttime,18,20,2,1),
				   dbo.[ofir_CountMovements] (@starttime,20,22,2,1),
				   dbo.[ofir_CountMovements] (@starttime,22,24,2,1)


	SET @starttime=dateadd(day,1,@starttime)
	END
 SELECT * from @report2 where daily > 0
