USE [PARK_DB]
GO
/****** Object:  UserDefinedFunction [dbo].[ofir_COUNTMovements]    Script Date: 31/08/2022 16:30:39 *****/

/* Function ofir_COUNTMovements
   ----------------------------
   
   Created : 31.08.2022 
   By : Ofir Elhayani
   Platform : Skidata Parking.Logic (All Versions)
   
   COUNTs movements by date or [time] (hours) increments . 
   Usage : dbo.ofir_COUNTMovements (<Date - date format>,<StartHour - int [0-24]>,<ENDHour - int [0-24]>,<Mode - int [1 or 2]>,<MovementType - int [1 or 2])
			
			Mode :  1 - COUNTs ContractParkers
					2 - COUNTs ShortTermParkers
			MovementType : 1- COUNTs Entries
					       2- COUNTs Exits
	
	IF StartHour and ENDHour are nulls then it will produce a daily result. 
*/	
	
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create FUNCTION [dbo].[ofir_COUNTMovements]
(
	@startdate date[time] ,
	@StartHour int = null,
	@ENDHour int = null,
	@mode int = null, /*1- COUNT contract parkers , 2 - COUNT spt's */
	@Movement int = null /* 1= entry , 2 - exit */
	
)
RETURNS int
BEGIN
	DECLARE @Return int;
	
	IF @mode=1 /*COUNT Contract Parkers */
	BEGIN
		IF @StartHour IS NULL and @ENDHour IS NULL and @Movement=1 /*Counts Daily Entries */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ContractParkerMovements  
		WHERE MovementTypeDesig='Entry' and ArticleNo > 2 
				and [time] BETWEEN @startdate and DATEADD(day,1,@startdate)
		END
		IF @StartHour IS NULL and @ENDHour IS NULL and @Movement=2 /*Counts Daily Exits */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ContractParkerMovements  
		WHERE MovementTypeDesig='Exit' and ArticleNo > 2 
				and [time] BETWEEN @startdate and DATEADD(day,1,@startdate)
		END

		IF @StartHour IS NOT NULL and @ENDHour IS NOT NULL and @Movement=1 /*Counts TimeInterval Entries */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ContractParkerMovements  
		WHERE MovementTypeDesig='Entry' and ArticleNo > 2 and [time] BETWEEN DATEADD(hour,@StartHour,@startdate) and DATEADD(hour,@ENDHour,@startdate)
		END
		IF @StartHour IS NOT NULL and @ENDHour IS NOT NULL and @Movement=2 /*Counts TimeInterval Exits */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ContractParkerMovements  
		WHERE MovementTypeDesig='Exit' and ArticleNo > 2 and [time] BETWEEN DATEADD(hour,@StartHour,@startdate) and DATEADD(hour,@ENDHour,@startdate)
		END
	END

	IF @mode=2 /*COUNT SPT */
	BEGIN
		IF @StartHour IS NULL and @ENDHour IS NULL and @Movement=1 /*Counts Daily Entries */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ParkingMovements  
		WHERE MovementTypeDesig='Entry' and ArticleNo =1 and [time] BETWEEN @startdate and DATEADD(day,1,@startdate)
		END
		IF @StartHour IS NULL and @ENDHour IS NULL and @Movement=2 /*Counts Daily Exits */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ParkingMovements  
		WHERE MovementTypeDesig='Exit' and ArticleNo =1 and [time] BETWEEN @startdate and DATEADD(day,1,@startdate)
		END

		IF @StartHour IS NOT NULL and @ENDHour IS NOT NULL and @Movement=1 /*Counts TimeInterval Entries */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ParkingMovements  
		WHERE MovementTypeDesig='Entry' and ArticleNo =1 and [time] BETWEEN DATEADD(hour,@StartHour,@startdate) and DATEADD(hour,@ENDHour,@startdate)
		END
		IF @StartHour IS NOT NULL and @ENDHour IS NOT NULL and @Movement=2 /*Counts TimeInterval Exits */
		BEGIN
		SELECT @Return=COUNT(*) 
		FROM dbo.ParkingMovements  
		WHERE MovementTypeDesig='Exit' and ArticleNo =1 and [time] BETWEEN DATEADD(hour,@StartHour,@startdate) and DATEADD(hour,@ENDHour,@startdate)
		END
	END
	RETURN (@Return);
END