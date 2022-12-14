USE [IPI_LPR_DB2]
GO
/****** Object:  View [dbo].[v_RegisteredMembers]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[v_RegisteredMembers]
AS
SELECT        org.OrganizationVisualName AS ORG, dep.Name AS Department, vis.Name, vis.LastName, rc.CarNumber, rc.IsVip, (CASE WHEN rm.RegisteredMemberId IN
                             (SELECT        guestId
                               FROM            guestinvitations) THEN '1' ELSE '0' END) AS ISGuest, rc.IsPresent, rc.CarParkID, rc.IsRestrict, vis.IsAnonymousVisitor AS Anonymous, rc.Active AS RCActive, vis.Active AS VSActive, vis.IdNumber, 
                         vis.PhoneNumber1, vis.PhoneNumber2, saa.StartTime AS VSValidFrom, saa.EndTime AS VSValidUntil, rc.StartDate AS RCValidFrom, rc.EndDate AS RCValidUntil, sar.ConcurrentCarsAllowedCount, 
                         sar.VipCarsAllowedCount, saa.IsParentInheritance, rc.CarId, av.AuthorizedVisitorId AS AVID, rm.RegisteredMemberId AS RMID, dep.DepartmentId AS DepId, org.OrganizationId AS OrgId, av.VisitorId, 
                         saa.SingleAccessAuthorizationId, rm.IsDeleted AS RMIsDeleted, rc.IsDeleted AS RCIsDeleted
FROM            dbo.Organizations AS org INNER JOIN
                         dbo.Departments AS dep ON dep.OrganizationId = org.OrganizationId INNER JOIN
                         dbo.RegisteredMembers AS rm ON rm.DepartmentId = dep.DepartmentId INNER JOIN
                         dbo.AuthorizedVisitors AS av ON av.AuthorizedVisitorId = rm.AuthorizedVisitorId LEFT OUTER JOIN
                         dbo.RegisteredCars AS rc ON rc.VisitorId = av.VisitorId LEFT OUTER JOIN
                         dbo.Visitors AS vis ON av.VisitorId = vis.VisitorId LEFT OUTER JOIN
                         dbo.SingleAccessAuthorizations AS saa ON saa.SingleAccessAuthorizationId = av.SingleAccessAuthorizationId LEFT OUTER JOIN
                         dbo.SingleAccessRestrictions AS sar ON sar.SingleAccessRestrictionId = saa.SingleAccessRestrictionId
GO
/****** Object:  Table [dbo].[LoadSubsInfo]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[LoadSubsInfo](
	[SubsId] [bigint] IDENTITY(1,1) NOT NULL,
	[FirstName] [nvarchar](20) NULL,
	[LastName] [nvarchar](20) NULL,
	[LicensePlate] [nvarchar](15) NOT NULL,
	[IdNumber] [nvarchar](20) NOT NULL,
	[Validation] [datetime] NULL,
	[Phone] [nvarchar](10) NULL,
	[IsVIP] [bit] NULL,
	[RFID] [nvarchar](10) NULL,
	[OrganizationName] [nvarchar](20) NOT NULL,
	[DepartmentName] [nvarchar](20) NOT NULL,
	[APT] [nvarchar](10) NULL,
	[CarsAllowed] [int] NOT NULL,
	[ParkingSpot] [nvarchar](10) NULL,
	[LoadStatus] [int] NOT NULL,
	[SystemMessageId] [tinyint] NULL,
	[IsProcessed] [bit] NULL,
	[IsGuest] [bit] NULL,
	[HostFullName] [nvarchar](50) NULL,
	[HostPhone] [nvarchar](50) NULL,
	[StartDate] [datetime] NULL,
	[UpdateStatus] [nvarchar](200) NULL,
	[Step] [nvarchar](max) NULL,
	[CarActive] [bit] NULL,
	[MemActive] [bit] NULL,
 CONSTRAINT [PK_LoadSubsInfo] PRIMARY KEY CLUSTERED 
(
	[SubsId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  StoredProcedure [dbo].[usp_lpr_LoadSubs_CreateCar]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Ofir Elhayani
-- Create date: 30.03.2020
-- Description:	Creates new car on registeredcars table
-- Update Log:
--				01.04.2020 Ofir Elhayani -- Added Reference to Isdeleted value 
--											Added Reference to Spot(ParkingSpot)+RfidTag values  
--				02.04.2020 Ofir Elhayani -- Redesigned the SP - Creates both car + permissions in one SP . Also - can deal with multiple cars per Subscriber. 
--											*** MUST HAVE UNIQUE IDNUMBER FOR EACH SUBSCRIBER & SAME IDNUMBER FOR EACH OF THE SUBSCRIBER'S CARS ***
--				21.12.2021	Ofir Elhayani -- Fixed Second condition (where there are no existing cars) refferals - caused Isvip to be null 
--				10.02.2022 Ofir Elhayani -- Changed checking conditions structure . some conditions were cancelled and some moved to the CreateCar procedure 
--				28.02.2022 Ofir Elhayani -- Added Update process to  existing cars
--				02.03.2022 Ofir Elhayani -- Changed procedure mthod of work. will work line by line instead by lists. 
--				14.04.2022 Ofir Elhayani -- Added condition That if the visitor is non active then the car will be updated as non active as well. 
--				25.04.2022 Ofir Elhayani -- (condition That if the visitor is non active then the car will be updated as non active as well) - Added update to endtime in registered cars also. 
--				29.08.2022 Ofir Elhayani -- Added reference to CarParkID column (check if exists and update\insert accordingly)
-- =============================================
CREATE PROCEDURE [dbo].[usp_lpr_LoadSubs_CreateCar]
	-- Add the parameters for the stored procedure here
	@Validation datetime,
	@VisitorId uniqueidentifier,
	@Subs_ID bigint,
	@CarUpdateStatus int OUTPUT,
	@VisId uniqueidentifier OUTPUT,
	@CARID uniqueidentifier OUTPUT,
	@Status int OUTPUT
	 
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;


/* Set Global Procedure Variables */


	   DECLARE @Cardone int
			  , @Car_Number varchar(50)
			  , @Car_Id uniqueidentifier
			  , @SingleAccessAuthorizationID uniqueidentifier
			  , @SingleAccessRestrictionId uniqueidentifier
			  , @max_num_cars int
			  , @Step nvarchar(MAX)
			  , @Message nvarchar(250)
			  , @IdNumber varchar(15)
			  , @IsGuest bit 
			--  , @HandicappedCar nvarchar (15)
			  , @CarUnderActiveRM nvarchar (15)
			  , @CarUnderNonActiveRM nvarchar(15)
			--  , @CarUnderNonActiveRMID uniqueidentifier
			 , @CarActive bit
			 



BEGIN TRY
  
	   
	   



	   /*If the carnumber exists in the DB under the same visitorID  - Then update it's status */
	  
	  SET @Car_Id = (select top(1) carId from RegisteredCars where  visitorId=@VisitorId and carnumber=(select licenseplate from LoadSubsInfo where SubsId=@Subs_ID) )
	  IF @Car_Id is not null
	   BEGIN
	  /* Optional condition for Car Non Active By Visitor Non Active   - Ofir 14.04.2022*/
	    Declare @VisActive bit = (select active from visitors where visitorId=@VisitorId) /* 14.04.2022*/,
				@EndDate datetime
		SET @Step='Car Exists - updating car Status'
		SET @CarActive = (select CarActive from LoadSubsInfo where SubsId=@Subs_Id)
		SET @EndDate = (select EndDate from RegisteredCars where carId=@Car_Id) /* 25.04.2022 */

		UPDATE RegisteredCars set Active=/* 14.04.2022*/(CASE when @VisActive=0 then 0 else /* 14.04.2022*/@CarActive /* 14.04.2022*/end)/* 14.04.2022*/
								 ,IsDeleted=0,
		/*25.04.2022*/			 EndDate=/* 25.04.2022*/(CASE when @VisActive=0 then getdate() else /* 25.04.2022*/@EndDate /* 25.04.2022*/end)/* 25.04.2022*/ 
								 where CarId=@Car_Id
		/*29.08.2022*/
		IF EXISTS (select c.name from sys.tables t
					join sys.columns c on c.object_id=t.object_id
					where t.name='RegisteredCars' and c.name='CarParkID')
		BEGIN
		UPDATE RegisteredCars set CarParkID=1 where CarId=@Car_Id
		END
		/*29.08.2022*/

		UPDATE LoadSubsInfo SET IsProcessed=1,LoadStatus=0,SystemMessageId=112,UpdateStatus='SUCCESS',Step=@Step where SubsId=@Subs_Id

			SET @VisId =@VisitorId 
			SET @Cardone  = 0
			SET @CarUpdateStatus=@CarDone

		END
		ELSE /*Go and create a new car in the DB */
		BEGIN
		
	  
			SET @Car_Number = (select LicensePlate from loadsubsinfo where SubsId=@Subs_ID)
			SET @Car_Id  = NEWID()
			SET @IdNumber= (select IdNumber from LoadSubsInfo where SubsId=@Subs_Id)
			SET @IsGuest = (select IsGuest from LoadSubsInfo where SubsId=@Subs_Id)
			
/* Perform Validation Checks  - Before Creating the Car */

/* Set Validation check variables */
-----------------------------------------------------------------------------
	SET @Step = 'CreateCar-Set @CarUnderActiveRM  Parameter'

	SET  @CarUnderActiveRM= (select  top (1) rc.carnumber from RegisteredCars rc 
									  join Visitors vis on vis.VisitorId=rc.VisitorId
									  join VisitorTypes vst on vst.VisitorTypeId=vis.VisitorTypeId
									  where rc.CarNumber=@Car_Number
									  and vis.VisitorId<>@VisitorId
									  and vis.VisitorTypeId='215161D4-201A-4F9A-B49C-DC0651F946A3'
									  and vis.active=1)
	

	
	SET @Step = 'CreateCar-Set @CarUnderNonActiveRM  Parameter'

	SET @CarUnderNonActiveRM = (select  top(1) rc.carnumber from RegisteredCars rc 
									  join AuthorizedVisitors av on av.VisitorId=rc.VisitorId
									  join RegisteredMembers rm on rm.AuthorizedVisitorId=av.AuthorizedVisitorId
									  join Visitors vis on vis.VisitorId=av.VisitorId
									  where (vis.active=0) and (rc.active=1) and rc.carnumber=@Car_Number  and vis.VisitorId<>@VisitorId)
-------------------------------------------------------------------------------
	

/* Validation Checks */



-----------------------------------------------------------------------------------------------


  SET @Step = 'CreateCar-Check for duplicate Guest CAR under Active RM(@CarUnderActiveRM)'

 --If Guest's Carnumber is under an Active RegisteredMember - exit the procedure and send relevant message
 IF (@CarUnderActiveRM is not null) and (@IsGuest=1)
 BEGIN
 SET @VisId=(select VisitorId from visitors where (IdNumber=@IdNumber))
 SET @Message = 'Guest Car is already registered under an active registered member - Will be skipped'
 --Added MessageId 133 to SystemMessages Table for Loading Error
 Update LoadSubsInfo set IsProcessed=1,LoadStatus=1,SystemMessageId=133,UpdateStatus=@Message,step=@Step where SubsId=@Subs_Id
 RETURN 
 END
 ----------------------------------------------------------------------------------------------
 SET @Step = 'CreateCar-Check for duplicate RM CAR under Active RM(@CarUnderActiveRM)'

 --If  Carnumber is under an Active RegisteredMember - exit the procedure and send relevant message
 IF (@CarUnderActiveRM is not null) and (@IsGuest=0)
 BEGIN
 --SET @VisId=(select VisitorId from visitors where (IdNumber=@IdNumber) and VisitorId<>@VisitorId)
 SET @Message = 'Car is already registered under an active registered member - Will be skipped'
 --Added MessageId 133 to SystemMessages Table for Loading Error
 Update LoadSubsInfo set IsProcessed=1,LoadStatus=1,SystemMessageId=133,UpdateStatus=@Message,step=@Step where SubsId=@Subs_Id

 RETURN 
 END
 --------------------------------------------------------------------------------------------------------------------------------

 /* Create Car Process */
 
			INSERT INTO dbo.RegisteredCars (CarId, VisitorId, CarNumber
							, CarTypeId
							, CreationTime, IsPresent, Active, IsRestrict, StartDate, EndDate,IsVip,IsBlackList,BlacklistDesc,RfidTag,Isdeleted,Spot)
				SELECT @car_id as CarId, 
						@visitorID as VisitorId, 
						@Car_Number as CarNumber
					 , '9920CEBA-4DA7-4614-B888-8E39210230B7' as CarTypeId	-- Regular
					 , GETDATE() as CreationTime
					 , 0 as IsPresent
					 , 1 as Active
					 , '0' as IsRestrict			
					 , GETDATE() as StartDate		
					 , CONVERT(datetime,@Validation, 103) as EndDate	/*25.04.2022*/
					 , ISNULL((select IsVip from loadsubsinfo where subsid=@Subs_Id),0) as IsVip
					 , 0 as IsBlackList
					 ,'' as BlacklistDesc	
					 , ISNULL((select RFID from LoadSubsInfo where subsid=@Subs_Id),'NONE') as RfidTag
					 , 0 as IsDeleted
					 , ISNULL((select ParkingSpot from LoadSubsInfo where subsid=@Subs_Id),'NONE') as Spot
			
			/*29.08.2022*/
		IF EXISTS (select c.name from sys.tables t
					join sys.columns c on c.object_id=t.object_id
					where t.name='RegisteredCars' and c.name='CarParkID')
		BEGIN
		UPDATE RegisteredCars set CarParkID=1 where CarId=@car_id
		END
		/*29.08.2022*/

			SET @CARID = @car_id

			
		--END Add New Car
		--Creating Car Permissions
		
				SET @max_num_cars  = (select CarsAllowed from LoadSubsInfo where SubsId=@Subs_ID)


	-- Update existing single-access-authorization record or add new one if missing
	SELECT	@SingleAccessAuthorizationID = saa.SingleAccessAuthorizationId
		  , @SingleAccessRestrictionId = saa.SingleAccessRestrictionId
	FROM	dbo.RegisteredCars rc
	LEFT JOIN	dbo.SingleAccessAuthorizations saa ON saa.SingleAccessAuthorizationId = rc.SingleAccessAuthorizationID
	WHERE	rc.CarId = @CarId


--Create SingleAccessRestriction
		
			SET	@SingleAccessRestrictionId = NEWID()
		/*	print 'Add SingleAccessRestrictionId = ' 
							+ CAST(@SingleAccessRestrictionId AS VARCHAR(50)) + ' ........................'*/
			
						INSERT INTO dbo.SingleAccessRestrictions (SingleAccessRestrictionId
										, ConcurrentCarsAllowedCount,VipCarsAllowedCount)
				SELECT	@SingleAccessRestrictionId as SingleAccessRestrictionId
					  , @max_num_cars as ConcurrentCarsAllowedCount
					  , CASE WHEN (select IsVip from loadsubsinfo where subsid=@Subs_Id)=1 THEN 1
					    ELSE 0 END as VipCarsAllowedCount
		
--Create SingleAccessAuthorization		

			SET	@SingleAccessAuthorizationID = NEWID()
		/*	print 'Adding SingleAccessAuthorizationId = ' 
							+ ISNULL(CAST(@SingleAccessAuthorizationID AS VARCHAR(50)), '***') 
							+ ' ........................'*/

			INSERT INTO dbo.SingleAccessAuthorizations (SingleAccessAuthorizationId, SingleAccessRestrictionId
								, StartTime, EndTime, IsTimeLimited, IsAuthorized, IsRestricted,IsLimitValidityAlways,IsParentInheritance)
				SELECT	@SingleAccessAuthorizationID as SingleAccessAuthorizationId
					  ,	@SingleAccessRestrictionId as SingleAccessRestrictionId
					  , GETDATE() as StartTime	 
					  ,CASE WHEN @Validation IS NULL THEN '9999-12-31 23:59:59.997'
								WHEN @Validation = '' THEN '9999-12-31 23:59:59.997'
								ELSE CONVERT(datetime,@Validation, 103)  END	
					  , 0  AS  IsTimeLimited 
					  , 1 as IsAuthorized	-- ?????????????????????????????????????????????????????????????
					  , CASE WHEN @SingleAccessRestrictionId IS NULL THEN 0
							ELSE 1											  
							END as IsRestricted	
					  , 1 as IsLimitValidityAlways
					  , 0 as IsParentInheritance
		/*	print 'Connect SingleAccessAuthorizationId=' 
							+ ISNULL(CAST(@SingleAccessAuthorizationID AS VARCHAR(50)), '***')
							+ ' to  RegisteredCars.CarId=' +  
							+ CAST(@CarId AS VARCHAR(50)) + ' ........................'*/
			--
			-- fix RegisteredCars record as SingleAccessAuthorization
			--
			UPDATE	dbo.RegisteredCars
			SET		SingleAccessAuthorizationID = @SingleAccessAuthorizationID,
			IsRestrict = CASE WHEN @SingleAccessRestrictionId IS NULL THEN 0
							ELSE 1											  
							END,
			StartDate = GETDATE(),
			EndDate = CASE WHEN @Validation IS NULL THEN '9999-12-31 23:59:59.997'
								WHEN @Validation = '' THEN '9999-12-31 23:59:59.997'
								ELSE CONVERT(datetime,@Validation, 103)  END
			WHERE	CarId = @CarId
				SET @Step=' CarID = ' + CAST (@Car_Id as nvarchar(40)) + ' Inserted Successfuly'
				
				UPDATE LoadSubsInfo SET IsProcessed=1,LoadStatus=0,SystemMessageId=0,UpdateStatus='SUCCESS',Step=@Step where SubsId=@Subs_Id
				SET @Cardone  = 0
				SET @CarUpdateStatus=@CarDone
			
	END

			SET @VisId =@VisitorId 
			SET @Cardone  = 0
			SET @CarUpdateStatus=@CarDone

END TRY


		BEGIN CATCH --------------------------------------------------------------------
	UPDATE LoadSubsInfo SET IsProcessed=1,LoadStatus=1,SystemMessageId=98 where SubsId=@Subs_Id

	DECLARE @DatabaseName VARCHAR(100) = DB_NAME()
		  , @DatabaseID   INT = DB_ID()
		  , @AdditionalInfo varchar(1000) = ''

	-- Add Error to Log table
	SET @additionalInfo = '*** ERROR: usp_lpr_LoadSubs_CreateCar() ' 
	SET @status = 1
	EXEC IPI_LPR_DB2.dbo.usp_AddErrorToDBALog
					  @DatabaseName   = @DatabaseName
					, @DatabaseID     = @DatabaseID
					, @AdditionalInfo = @additionalInfo

END CATCH; ---------------------------------------------------------------------
END



GO
/****** Object:  StoredProcedure [dbo].[usp_lpr_LoadSubs_CreateVisRmAv]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



 /*=============================================
-- Author:		Ofir Elhayani
-- Create date: 30.03.2020
-- Description:	Create Visitor+AuthorizedVisitor+RegisteredMember 

-- Update log : 
--				01.04.2020 Ofir Elhayani -- Added Creation of SingleAccessAuthorization+SingleAccessRestricyion to the RegisteredMember's AuthorizedVisitorId
										--	Added Reference to the APT(Room)+UpdateTime values in Visitors
										--	Added Reference to Isdeleted value on RegisteredMembers
				
				13.07.2021 Ofir Elhayani -- Added Guest functionality. 
											Added IsGuest,StartDate,FullHostname,HostPhone Parameters  and integrated into 
											1. Create SingleAccessAuthorization Creation process
											2. Guest Check Creation Process
										-- Added checks before loading : 
										1. If car is handicapped - will not be loaded with a relevant message
										2. If car is under an active registered member - will not be loaded with a relevant message
										3. If car is under a non active registered member - existing car will be marked for deletion, car will
																							be loaded and a relevant message will be updated. 
				

				10.02.2022 Ofir Elhayani -- Changed checking conditions structure . some conditions were cancelled and some moved to the CreateCar procedure 					
				28.02.2022 Ofir Elhayani -- Added Update process in case that the member is already in the DB 
				01.03.2022 Ofir Elhayani -- Added case for: 
											when the visitor exists on the list and on the DB but is marked as IsDeleted - The IsDeleted bit will be 0 instead of 1 
				25.04.2022 Ofir ELhayani -- Updated the update process. improved update statement 
-- =============================================*/
CREATE PROCEDURE [dbo].[usp_lpr_LoadSubs_CreateVisRmAv]
	-- Add the parameters for the stored procedure here
		 @SubsId bigint,
		 @SiteId uniqueidentifier,
		 @depid uniqueidentifier,
		 @Validation datetime,
		 @IsGuest bit,
		 @SAR uniqueidentifier OUTPUT,
		 @SAA uniqueidentifier OUTPUT,
		 @VisId uniqueidentifier OUTPUT,
		 @AuthId uniqueidentifier OUTPUT,
		 @RegmemId uniqueidentifier OUTPUT
		

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from interfering with SELECT statements.
	SET NOCOUNT ON;
	 DECLARE @Step nvarchar(200) = 'CreateVisRmAv-Set Primary Parameters'
	Declare @FirstName varchar(50) = (select firstname from LoadSubsInfo where SubsId=@SubsId),
	@LastName varchar(50) = (select LastName from LoadSubsInfo where SubsId=@SubsId), 
	@IdNumber varchar(15) = (select IdNumber from LoadSubsInfo where SubsId=@SubsId),
	@Phone varchar(50) = (select Phone from LoadSubsInfo where SubsId=@SubsId),
	@Room varchar(50) = (select APT from LoadSubsInfo where SubsId=@SubsId),
	@FullHostName nvarchar(40) = (select HostFullName from LoadSubsInfo where SubsId=@SubsId),
	@HostPhone nvarchar(40) =(select HostPhone from LoadSubsInfo where SubsId=@SubsId),
	@StartDate datetime = (select StartDate  from LoadSubsInfo where SubsId=@SubsId),
	@IsVip bit = (select isvip from LoadSubsInfo where SubsId=@SubsId),
	@MemActive bit = (select MemActive from LoadSubsInfo where SubsId=@SubsId),
	@Message nvarchar(250),
	@DupIDActVisID uniqueidentifier,
	@DupIDNonActRMID uniqueidentifier

	
	SET @Step = 'CreateVisRmAv-Set @DupIDActVisID  Parameter'


BEGIN TRY

 
 
----------------------------------------------------------------------------------------------
 	SET @Step = 'CreateVisRmAv-Check for duplicate visitor Id+name+lastname'

  -- If Visitor Exists (first name + Idnumber) -  Notify, and go to update cars from the list 
 IF exists (select  idnumber from visitors where  IdNumber=@IdNumber and VisitorTypeId='215161D4-201A-4F9A-B49C-DC0651F946A3')
 BEGIN
 SET @VisId=(select top(1) VisitorId from visitors where (IdNumber=@IdNumber) ) /*28.02.2022 (Name=@FirstName)  and*/
 SET @SubsId=@SubsId  /*28.02.2022*/
 SET @SAA=(select SingleAccessAuthorizationID from AuthorizedVisitors where VisitorId=@VisId)  /*28.02.2022*/
 SET @SAR=(select SingleAccessRestrictionID from SingleAccessAuthorizations where SingleAccessAuthorizationId=@SAA)  /*28.02.2022*/
 SET @RegmemId=(select rm.registeredmemberId from RegisteredMembers rm /*01.03.2022*/
					join AuthorizedVisitors av on av.AuthorizedVisitorId=rm.AuthorizedVisitorId 
					where av.VisitorId=@VisId)
UPDATE visitors set active=(CASE WHEN active=(select memactive from LoadSubsInfo where SubsId=@SubsId) THEN active  /*28.02.2022*/
							 ELSE (select memactive from LoadSubsInfo where SubsId=@SubsId)
							 END),
					 Name=(CASE WHEN name=(select FirstName from LoadSubsInfo where SubsId=@SubsId) THEN name  /*28.02.2022*/
							ELSE (select FirstName from LoadSubsInfo where SubsId=@SubsId)
							END),
					 LastName=(CASE WHEN LastName=(select LastName from LoadSubsInfo where SubsId=@SubsId) THEN LastName  /*28.02.2022*/
							ELSE (select LastName from LoadSubsInfo where SubsId=@SubsId)
							END)
					 
		where VisitorId=@VisId
UPDATE SingleAccessAuthorizations set EndTime = (CASE WHEN EndTime=/*25.04.2022*/CONVERT(datetime,@Validation, 103)/*25.04.2022*/ THEN EndTime  /*28.02.2022*/
													ELSE /*25.04.2022*/CONVERT(datetime,@Validation, 103)/*25.04.2022*/ END)
													where SingleAccessAuthorizationId=@SAA
UPDATE SingleAccessRestrictions set ConcurrentCarsAllowedCount = (CASE WHEN ConcurrentCarsAllowedCount=(select CarsAllowed from LoadSubsInfo where SubsId=@SubsId) THEN ConcurrentCarsAllowedCount
																	ELSE (select CarsAllowed from LoadSubsInfo where SubsId=@SubsId) END )
													where SingleAccessRestrictionId=@SAR  /*28.02.2022*/

/*01.03.2022*/
UPDATE RegisteredMembers set IsDeleted = 0 where RegisteredMemberId=@RegmemId

 SET @Message=' Already Exists - Updated Details'
  Update LoadSubsInfo set IsProcessed=1,LoadStatus=0,SystemMessageId=112,UpdateStatus=@Message,step=@step where SubsId=@SubsId 
  RETURN
 END
---------------------------------------------------------------------------------------------

 
 ELSE
 
 BEGIN
 ------------------------------------------------------------------------------------------------------
							----------------------------	
							--		ADD VISITOR		  --
							----------------------------

	/*Declare Variables */
	DECLARE @AuthorizedVisitorId uniqueidentifier = NEWID(),
		    @RegisterMemberID uniqueidentifier  = NEWID(),
		    @SingleAccessAuthorizationID uniqueidentifier = NEWID(),
		    @SingleAccessRestrictionId uniqueidentifier = NEWID(),
	    	@max_num_cars int = (select CarsAllowed from LoadSubsInfo where SubsId=@SubsId)

	
	SET @VisId = NEWID()
	SET @Step = 'CreateVisRmAv-Add new Visitor. VisID = ' + cast(@VisId as varchar(50))


			INSERT INTO dbo.Visitors (VisitorId, VisitorTypeId, Name,IdNumber,PhoneNumber1, PhoneNumber2
								, IsAnonymousVisitor
								, [Description]
								, CreationTime, SiteId, IsSiteVisitor, Active,UpdateTime,LastName,Room)
				SELECT	@VisId as VisitorId
					 , -- (CASE WHEN @IsGuest=0 THEN '215161D4-201A-4F9A-B49C-DC0651F946A3' /* RegisteredMember */
					  --        WHEN @IsGuest=1 THEN '045981DD-1AAC-4F9D-88F2-BED30E4187DB' /*Guest */
							--  END)  
						'215161D4-201A-4F9A-B49C-DC0651F946A3'  as VisitorTypeId	
						
					  , RTRIM(LTRIM((ISNULL(@FirstName, '')))) as Name
					  , @IdNumber as IdNumber
					  , @Phone as PhoneNumber1
					  ,'' as PhoneNumber2
					  , CASE WHEN ((@FirstName is not null) or (@LastName is not null) or (@IdNumber is not null)) THEN 0
							 ELSE 1 END as IsAnonymousVisitor
					  , (CASE WHEN @IsGuest=0 THEN 'Registered Member' /* RegisteredMember */
					          WHEN @IsGuest=1 THEN 'Guest' /*Guest */
							  END) as [Description]
					  , GETDATE() as CreationTime
					  , @siteid as  SiteId
					  , 1 as IsSiteVisitor	
					  , 1 as Active			
					  , GETDATE() as UpdateTime
					  , RTRIM(LTRIM((ISNULL(@LastName, ''))))  as LastName
					  , @Room as Room
----------------------------------------------------------------------------------------------------------------------------
							----------------------------	
							-- ADD AUTHORIZEDVISITOR  --
							----------------------------

		
		SET @Step = 'CreateVisRmAv-Add new AuthorizedVisitor. AvID = ' + cast(@AuthorizedVisitorId as varchar(50))

		INSERT INTO dbo.AuthorizedVisitors (AuthorizedVisitorId, VisitorId, ElapsedEntrancesOffset)
				SELECT	@AuthorizedVisitorId as AuthorizedVisitorId
					  , @VisId as VisitorId
				  , 0 as ElapsedEntrancesOffset
		SET @AuthId=@AuthorizedVisitorId
-----------------------------------------------------------------------------------------------------------------
							-------------------------
							--ADD REGISTERED MEMBER--
							-------------------------
		
		
		SET @Step = 'CreateVisRmAv-Add new RegisteredMembers . RmID = ' + cast(@RegisterMemberID as varchar(50))

			INSERT INTO dbo.RegisteredMembers (RegisteredMemberId, AuthorizedVisitorId, DepartmentId, IsDepartmentMember,IsDeleted)
				SELECT	@RegisterMemberID as RegisteredMemberId
					  , @AuthorizedVisitorId as AuthorizedVisitorId
					  , @depid as DepartmentId
					  , CASE WHEN @depid IS NULL THEN 0 ELSE 1 END as IsDepartmentMember
					  , 0 as Isdeleted
		SET @RegmemId=@RegisterMemberID

-------------------------------------------------------------------------------------------------
				
				





				----------------------------------------------
				--		ADD SINGLEACCESSRESTRICTION         --
				----------------------------------------------
		SET @Step = 'CreateVisRmAv-Add new SingleAccessRestriction. SARID = ' + cast(@SingleAccessRestrictionId as varchar(50))

			
		INSERT INTO dbo.SingleAccessRestrictions (SingleAccessRestrictionId
												, ConcurrentCarsAllowedCount,VipCarsAllowedCount)
				SELECT	@SingleAccessRestrictionId as SingleAccessRestrictionId
					  , @max_num_cars as ConcurrentCarsAllowedCount
					  , CASE WHEN @IsVip is null or @IsVip=0 THEN 0
						ELSE (select count(isvip) from LoadSubsInfo where IdNumber=@IdNumber and FirstName=@FirstName and LastName=@LastName)
						END as VipCarsAllowedCount
						    
		SET @SAR=@SingleAccessRestrictionId

				----------------------------------------------
				--		ADD SINGLEACCESSAUTHORIZATION       --
				----------------------------------------------	

		SET @Step = 'CreateVisRmAv-Add new SingleAccessAuthorization. SAAID = ' + cast(@SingleAccessAuthorizationID as varchar(50))

			
			INSERT INTO dbo.SingleAccessAuthorizations (SingleAccessAuthorizationId, 
														SingleAccessRestrictionId,
														StartTime, 
														EndTime, 
														IsTimeLimited, 
														IsAuthorized, 
														IsRestricted,
														IsLimitValidityAlways,
														IsParentInheritance)

				SELECT	@SingleAccessAuthorizationID as SingleAccessAuthorizationId
					  ,	@SingleAccessRestrictionId as SingleAccessRestrictionId
					  /* 13.07.2021 */
					  , (CASE WHEN @StartDate IS NOT NULL THEN @StartDate 
							  WHEN @StartDate ='' THEN GETDATE()	
					      ELSE GETDATE()
						  END) as StartTime	
						  -------
					  ,(CASE WHEN @Validation IS NULL THEN '9999-12-31 23:59:59.997'
								WHEN @Validation = '' THEN '9999-12-31 23:59:59.997'
								ELSE CONVERT(datetime,@Validation, 103)  END) as EndTime	
					  , 0  AS  IsTimeLimited 
					  , 1 as IsAuthorized	
					  , (CASE WHEN @SingleAccessRestrictionId IS NULL THEN 0
							ELSE 1											  
							END) as IsRestricted	
					  , 1 as IsLimitValidityAlways
					  , (CASE WHEN exists (select RoutingPlanSubscriberOUId from RoutingPlanSubscribers where  RoutingPlanSubscriberOUId=@depid) THEN 1
								ELSE 0 
								END) as IsParentInheritance /*If Exist Routing Plan to The Department then Mark it as inherit Routings */
			

			SET @SAA=@SingleAccessAuthorizationID

			---------------------------------------------------------------------
			-- Connect AuthorizedvisitorID  record as SingleAccessAuthorization--
			---------------------------------------------------------------------

			SET @Step = 'Connect AuthorizedvisitorID  record as SingleAccessAuthorization. SAAID = ' 
						+ cast(@SingleAccessAuthorizationID as varchar(50))
						+ ', AVID= '
						+ CAST(@AuthorizedVisitorId AS VARCHAR(50))

			
			UPDATE	dbo.AuthorizedVisitors
			SET		SingleAccessAuthorizationID = @SingleAccessAuthorizationID
			WHERE	AuthorizedVisitorId = @AuthorizedVisitorId
---------------------------------------------------------------------------------------------------------------

			-------------------------------------
			--		INSERT GUEST INVITATION    --
			-------------------------------------


			/* 13.07.2021 */
			IF (@IsGuest=1) and @RegisterMemberID not in (select guestid from GuestInvitations)/* Add As Guest */
			BEGIN
			Declare @invId bigint = (SELECT (MAX(InvitationId)+1) FROM GuestInvitations)
			SET @invId=(CASE WHEN @invId is null THEN 1
						ELSE @invId
						END)
			
			SET @Step = 'Insert Guest Invitation. IvitationId = ' 
						+ CAST(@invId as nvarchar(5))
						+ ' , GuestID = '
						+CAST(@RegisterMemberID as nvarchar(40))

			INSERT INTO GuestInvitations (InvitationId,hostFullName,hostPhone,guestId)
			
			SELECT 
			@invId as InvitationId,
			@FullHostName as hostFullName,
			@HostPhone as hostPhone,
			@RegisterMemberID as GuestId
			--select * from GuestInvitations 
			END
-------------------------------------------------------------------------
			
Print @FirstName + ' ' + @LastName + ' Processed'
		
	Update LoadSubsInfo set IsProcessed=1,LoadStatus=0,SystemMessageId=0,UpdateStatus ='SUCCESS',step='Visitor Created. Moving to Car Creation' where SubsId=@SubsId
END
END TRY

		BEGIN CATCH --------------------------------------------------------------------

		Update LoadSubsInfo set IsProcessed=1,LoadStatus=1,SystemMessageId=99,UpdateStatus='Failed',Step=@Step where SubsId=@SubsId
	
	
END CATCH; ---------------------------------------------------------------------
END



GO
/****** Object:  StoredProcedure [dbo].[usp_lpr_LoadSubs_DeleteMembersCarsByDep]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[usp_lpr_LoadSubs_DeleteMembersCarsByDep]
(
	@DepId uniqueidentifier
)


AS
BEGIN



BEGIN TRY ----------------------------------------------------------------------


IF @DepId is not null
BEGIN

Declare @Cars int,
		@Member int
-------------------------------------------------
--Creates Temporary Tables for Cars and Members - 
--destinated for Deletion (IsDeleted=1)		    -
-------------------------------------------------
CREATE TABLE #ForDeletion (
							RMID uniqueidentifier,
							CARID uniqueidentifier,
							AVID uniqueidentifier,
							VISID uniqueidentifier)

INSERT INTO #ForDeletion ( RMID ,
							CARID ,
							AVID ,
							VISID )

SELECT rm.RegisteredMemberId as RMID,
	   rc.carId as CARID,
	   av.AuthorizedVisitorId as AVID,
	   av.VisitorId as VISID
FROM Departments dep
join RegisteredMembers rm on rm.DepartmentId=dep.DepartmentId
join AuthorizedVisitors av on av.AuthorizedVisitorId=rm.AuthorizedVisitorId
left join RegisteredCars rc on rc.VisitorId=av.VisitorId
where rm.DepartmentId=@DepId

set @Cars = (select count(carId) from #ForDeletion)
set @Member = (select count (distinct RMID) from #ForDeletion)

select @Cars as 'CarsForDeletion',@Member as 'MembersForDeletion' 



/* Mark Cars and Members for Deletion */

update RegisteredCars set IsDeleted=1 where carId in (select carId from #ForDeletion)
update RegisteredMembers set IsDeleted=1 where RegisteredMemberId in (select RMID from #ForDeletion)

/* Delete */

Exec dbo.DeleteDeletedMembersCars

/* LOG */

IF (@Cars > 0) or (@Member > 0)
BEGIN
DECLARE @DatabaseName VARCHAR(100) = DB_NAME()
		  , @DatabaseID   INT = DB_ID()
		  , @AdditionalInfo varchar(1000) = ''

Set @AdditionalInfo='Deleted ' + cast(@Cars as varchar(5)) + ' Cars, and ' + cast(@Member as varchar(5)) + ' Members from DepartmentId = ' + Cast(@DepId as varchar(50))

INSERT INTO dbo.DBALog (  DatabaseID,     
								DatabaseName,			 
								ProcedureName,  
								ErrorLine, 
								ErrorNumber,
								ErrorMessage,   
								ErrorSeverity,	 
								ErrorState,	 
								XactState,
								AdditionalInfo, 
								TransactionsCount, 
								PerformedTransaction
						)
	SELECT @DatabaseID AS DatabaseID, 
		   @DatabaseName AS dbName, 
		   '[usp_lpr_LoadSubs_DeleteMembersCarsByDep]' AS ProcedureName,
		   0 AS ErrorLine, 
		   0 AS ErrorNumber, 
		   'INFO - NOT AN ERROR' AS ErrorMessage,
		   0 AS ErrorSeverity, 
		   0 AS ErrorState,
		   0 AS XactState, 
		   @AdditionalInfo AS AdditionalInfo,
		   0 AS TransactionsCount, 
		   'INFO Message' AS PerformedTransaction

END

------------------------------------
-- Drop Temporary tables if exists -
------------------------------------
Drop Table #ForDeletion
END




END TRY ------------------------------------------------------------------------

BEGIN CATCH --------------------------------------------------------------------

	

	-- Add Error to Log table
	SET @additionalInfo = '*** ERROR: [usp_lpr_LoadSubs_DeleteMembersCarsByDep]() ' 

	EXEC [IPI_LPR_DB].dbo.usp_AddErrorToDBALog
					  @DatabaseName   = @DatabaseName
					, @DatabaseID     = @DatabaseID
					, @AdditionalInfo = @additionalInfo

END CATCH; ---------------------------------------------------------------------





END




GO
/****** Object:  StoredProcedure [dbo].[usp_lpr_LoadSubs_LoadingSubs]    Script Date: 30/08/2022 00:03:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-- Batch submitted through debugger: SQLQuery3.sql|7|0|C:\Users\ADMINI~1\AppData\Local\Temp\4\~vs72FE.sql

/* =======================================================================
SP Name:	usp_lpr_loadingsubs

Created by:		Yaacov Cabessa
Creation date:	23/03/2020

Update date:	<date>	<name>	<comment>
				23.03.2020	Yaacov	creation
				29.03.2020  Ofir Elhayani -- Added Add visitor+Authorizedvisitor+RegisteredMember Creation
				30.03.2020  Ofir Elhayani - Created 3 Stored Procedures :
											usp_lpr_CreateVisRmAv - Creates new visitor, registeredmember and authorizedvisitor
											usp_lpr_CreateCar - Creates New RegisteredCar
											usp_lpr_CreateCarValidationData - Creates new SingleAccessRestrictionId+SingleAccessAuthorizationId and links them to the right CarId 

											
				02.04.2020 Ofir Elhayani - Redesigned main SP - now 2 Sub Sp's work instead of 3. Car SP returns status mode when works is done '0'. If the is an error- it does not return value and the SP fails. 
				10.02.2022 Ofir Elhayani - Changed Reporting method to the LoadSubsInfo table 
				01.03.2022 Ofir Elhayani - Added Mode 2 - Update all cars+members of @DepId as Isdeleted and then continue loading
				28.08.2022 Ofir Elhayani - Fixed bug when loading multy departments of the same organization. (all subscribers were loaded to the first department of the specified org. 
											now subscribers will be loaded to a the specified department of the specified org) 

Description: add registered member and car to site/organization/department

Input:	
	  @sitename	sitename
	  @organizationname	
	  @departmentname
	  @memberdetails xml/jason format
	  @cardetails	xml/jason format
	  @mode int 
	  @status int out is status returned to caller

Usage:	

-- =======================================================================*/
CREATE PROCEDURE [dbo].[usp_lpr_LoadSubs_LoadingSubs]
								  @siteid	uniqueidentifier = NULL
								, @orgid	uniqueidentifier = NULL
								, @depid	uniqueidentifier= NULL
								, @mode int = NULL
								, @status int = NULL OUTPUT
AS
BEGIN

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	SET NOCOUNT ON;	-- to prevent extra result sets from interfering with SELECT statements.

	DECLARE @Step nvarchar(MAX)
	
	IF (@siteid IS NOT NULL AND @orgid IS NOT NULL AND @depid IS NOT NULL)
	BEGIN

BEGIN TRY ----------------------------------------------------------------------
	--Checking that none of the inputs is null
	
/* Clean LoadSubsInfo table */	
--Updates value in IsProcessed Column on all the rows of LoadSubsInfo Table 
	
	SET @Step='Prepare Table for loading + Clean Table from comments'
	Update LoadSubsInfo set IsProcessed=0,UpdateStatus='',Step='',SystemMessageId=''
	
--------------------------------------------------------------------------------	
	/* Declaring Variables */

	Declare /* LoadSubs Procedure Variables */
			@Subs_ID bigint, /*Row Number in the LoadSubsInfo */
			@Validation datetime, /* Subscriber EndTime */
			@VisitorId uniqueidentifier, /*Subscriber VisitorID */
			@RmSAA uniqueidentifier, /* Subscriber singleaccessauthorizationId */
			@RmSAR uniqueidentifier, /* Subscriber singleaccessrestrictionId */
			@AuthVisId uniqueidentifier, /* Subscriber AuthorizedVisitorId */
			@RegisteredmemberId uniqueidentifier, /* Subscriber RegisteredmemberId */
			@SingleAccessRestriction uniqueidentifier,
			@Car_Status int, /*Car_Status */
			@VisId uniqueidentifier,
			@IsGuest int, /*Is the subscriber is guest */
			@CARID uniqueidentifier,
			/* DBAlog Reporting Variables */
			@DatabaseName VARCHAR(100) = DB_NAME(),
		    @DatabaseID   INT = DB_ID(),
		    @AdditionalInfo varchar(1000) = '',
			/*Counting Reporting Variables */
		    @MemCounter int,
		    @CarCounter int
--------------------------------------------------------------------------------------------------------------------
				/* MODE 2 - DELETE DEPARTMENT CONTENT */
	IF @mode=2
	BEGIN	
		/* Mark For Deletion */
		UPDATE RegisteredMembers set isdeleted = 1 where RegisteredMemberId in (select RegisteredMemberId from RegisteredMembers where DepartmentId=@depid)
		UPDATE RegisteredCars set isdeleted = 1 where CarId in (select rc.CarId from RegisteredMembers rm
																 join AuthorizedVisitors av on av.AuthorizedVisitorId=rm.AuthorizedVisitorId
																 join RegisteredCars rc on rc.VisitorId=av.VisitorId
																 where rm.DepartmentId=@depid)
	END
	ELSE
	BEGIN
-------------------------------------------------------------------------------------
	/* Counts the members + cars before loading */

	SET @MemCounter = (select count(distinct idnumber) from LoadSubsInfo where IsProcessed=0)
	set @CarCounter = (select count(LicensePlate) from LoadSubsInfo where IsProcessed=0)
	Set @AdditionalInfo='List Size Before Loading: ' + cast(@MemCounter as varchar(5)) + ' Members, and ' + cast(@CarCounter as varchar(5)) + ' Cars' 

	/* Report to DBAlog before loading */

	INSERT INTO dbo.DBALog (  DatabaseID,     
								DatabaseName,			 
								ProcedureName,  
								ErrorLine, 
								ErrorNumber,
								ErrorMessage,   
								ErrorSeverity,	 
								ErrorState,	 
								XactState,
								AdditionalInfo, 
								TransactionsCount, 
								PerformedTransaction
						)
	SELECT @DatabaseID AS DatabaseID, 
		   @DatabaseName AS dbName, 
		   '[usp_lpr_LoadSubs_LoadingSubs]' AS ProcedureName,
		   0 AS ErrorLine, 
		   0 AS ErrorNumber, 
		   'INFO - NOT AN ERROR' AS ErrorMessage,
		   0 AS ErrorSeverity, 
		   0 AS ErrorState,
		   0 AS XactState, 
		   @AdditionalInfo AS AdditionalInfo,
		   0 AS TransactionsCount, 
		   'INFO Message' AS PerformedTransaction
-------------------------------------------------------------

	--As long as the count of Unprocessed rows for the organization is above 0 
	SET @Step = 'Start Loading Table'
	  
--	WHILE  exists (select * from LoadSubsInfo where (OrganizationName=(select OrganizationVisualName from Organizations where OrganizationId=@orgid)) and  (IsProcessed=0))
/*28.08.2022*/    WHILE  exists (select * from LoadSubsInfo where (OrganizationName=(select OrganizationVisualName from Organizations where OrganizationId=@orgid)) 
					 and  (DepartmentName=(select name from Departments where DepartmentId=@depid and OrganizationId=@orgid))
					 and IsProcessed=0)
	BEGIN
	--SET	 @Subs_ID  = (select top (1) SubsId from LoadSubsInfo where 
	--				 ((OrganizationName=(select OrganizationVisualName from Organizations where OrganizationId=@orgid)) and  (IsProcessed=0)))
/*28.08.2022*/	SET	 @Subs_ID  = (select top (1) SubsId from LoadSubsInfo where 
					 (OrganizationName=(select OrganizationVisualName from Organizations where OrganizationId=@orgid)) 
					 and  (DepartmentName=(select name from Departments where DepartmentId=@depid and OrganizationId=@orgid))
					 and IsProcessed=0)
	SET	 @Validation  = (select Validation from LoadSubsInfo where SubsId=@Subs_ID)
	SET	 @IsGuest = (select IsGuest from LoadSubsInfo where SubsId=@Subs_ID)
	SET  @Step  = 'Now Creating SubsID' + CAST(@Subs_ID as nvarchar(10))
	
	-- Receives the VisId OUTPUT parameter from usp_lpr_CreateVisRmAv stored procedure and apply it to @VisitorId

	EXEC [dbo].usp_lpr_LoadSubs_CreateVisRmAv @Subs_Id, 
											  @SiteId , 
											  @depid , 
											  @Validation, 
											  @IsGuest,
										      @visId=@visitorId OUTPUT, 
											  @SAR=@RmSAR  OUTPUT,
											  @SAA=@RmSAA  OUTPUT,
											  @AuthId=@AuthVisId  OUTPUT,
											  @RegmemId=@RegisteredmemberId  OUTPUT
	/* Skip the Visitor If there is an error message */
	IF (select SystemMessageId from LoadSubsInfo where SubsId=@Subs_ID) = 133  
	BEGIN
	CONTINUE
	END
	

	ELSE 
	BEGIN
	IF (select SystemMessageId from LoadSubsInfo where SubsId=@Subs_ID) = 112  
	BEGIN
	update LoadSubsInfo set Step='Updated Existing Visitor details' where SubsId=@Subs_ID
	END
	/* Create Car */
	EXEC [dbo].usp_lpr_LoadSubs_CreateCar  @Validation  , 
										   @visitorID, 
										   @Subs_ID,
										   @CarUpdateStatus = @Car_Status OUTPUT,
										   @VisId=@VisId OUTPUT,
										   @CarID=@CARID OUTPUT, 
										   @status = @status OUTPUT	
	
	/* Skip the Car If there is an error message */
	IF (select SystemMessageId from LoadSubsInfo where SubsId=@Subs_ID) = 133  
	BEGIN
	CONTINUE
	END
	IF (select SystemMessageId from LoadSubsInfo where SubsId=@Subs_ID) = 112  
	BEGIN
	update LoadSubsInfo set IsProcessed = 1	,LoadStatus = 0	,SystemMessageId = 112,UpdateStatus='SUCCESS',Step='Updated Existing Car Status' 
	where SubsId = @Subs_ID
	CONTINUE
	END
	
	END

	IF ((@visitorID IS NOT NULL) and (@Car_Status=0))-- and (@RmSAR IS NOT NULL))
			BEGIN
			SET @Step='VisId= ' + Cast(@visId as nvarchar(40)) +' , CarID = ' + CAST (@CARID as nvarchar(40))
			   update LoadSubsInfo set IsProcessed = 1	,LoadStatus = 0	,SystemMessageId = 0,UpdateStatus='SUCCESS',Step=@Step 
			   where SubsId = @Subs_ID
			   
			END
			ELSE
			BEGIN
			SET @Step='VisId= ' + NULLIF(Cast(@visId as nvarchar(40)),'NO VISID') +' , CarID = ' + NULLIF(CAST(@CARID as nvarchar(40)),'NO CARID')

				update LoadSubsInfo set IsProcessed = 0	,LoadStatus = 1	,SystemMessageId = 133,UpdateStatus='FAILED',Step=@Step where SubsId = @Subs_ID
				
					 
					 SET @status = 1
					 Select @status
			END
	END
	
	/* Set Counters for Post loading report */
	SET @MemCounter = (select count(distinct idnumber) from LoadSubsInfo where UpdateStatus='SUCCESS' and IsProcessed=1 and SystemMessageId=0)
	set @CarCounter = (select count(LicensePlate) from LoadSubsInfo where UpdateStatus='SUCCESS' and IsProcessed=1 and SystemMessageId=0)
	Set @AdditionalInfo='Total Loaded: ' + cast(@MemCounter as varchar(5)) + ' Members, and ' + cast(@CarCounter as varchar(5)) + ' Cars' 
	/* Report to DBAlog After loading */
	INSERT INTO dbo.DBALog (  DatabaseID,     
								DatabaseName,			 
								ProcedureName,  
								ErrorLine, 
								ErrorNumber,
								ErrorMessage,   
								ErrorSeverity,	 
								ErrorState,	 
								XactState,
								AdditionalInfo, 
								TransactionsCount, 
								PerformedTransaction
						)
	SELECT @DatabaseID AS DatabaseID, 
		   @DatabaseName AS dbName, 
		   '[usp_lpr_LoadSubs_LoadingSubs]' AS ProcedureName,
		   0 AS ErrorLine, 
		   0 AS ErrorNumber, 
		   'INFO - NOT AN ERROR' AS ErrorMessage,
		   0 AS ErrorSeverity, 
		   0 AS ErrorState,
		   0 AS XactState, 
		   @AdditionalInfo AS AdditionalInfo,
		   0 AS TransactionsCount, 
		   'INFO Message' AS PerformedTransaction
		
		SET @status = 0
		SELECT @status

	update LoadSubsInfo set Step = 'Loaded Successfully' where IsProcessed=1 and SystemMessageId=0
END
	
END TRY ------------------------------------------------------------------------

BEGIN CATCH --------------------------------------------------------------------


	-- Add Error to Log table
	SET @additionalInfo = CAST(@Step as varchar(1000))

	EXEC [IPI_LPR_DB2].dbo.usp_AddErrorToDBALog
					  @DatabaseName   = @DatabaseName
					, @DatabaseID     = @DatabaseID
					, @AdditionalInfo = @additionalInfo
	set @status =1
	Select @status

END CATCH; ---------------------------------------------------------------------

END
END


GO
EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPane1', @value=N'[0E232FF0-B466-11cf-A24F-00AA00A3EFFF, 1.00]
Begin DesignProperties = 
   Begin PaneConfigurations = 
      Begin PaneConfiguration = 0
         NumPanes = 4
         Configuration = "(H (1[41] 4[30] 2[10] 3) )"
      End
      Begin PaneConfiguration = 1
         NumPanes = 3
         Configuration = "(H (1 [50] 4 [25] 3))"
      End
      Begin PaneConfiguration = 2
         NumPanes = 3
         Configuration = "(H (1 [50] 2 [25] 3))"
      End
      Begin PaneConfiguration = 3
         NumPanes = 3
         Configuration = "(H (4 [30] 2 [40] 3))"
      End
      Begin PaneConfiguration = 4
         NumPanes = 2
         Configuration = "(H (1 [56] 3))"
      End
      Begin PaneConfiguration = 5
         NumPanes = 2
         Configuration = "(H (2 [66] 3))"
      End
      Begin PaneConfiguration = 6
         NumPanes = 2
         Configuration = "(H (4 [50] 3))"
      End
      Begin PaneConfiguration = 7
         NumPanes = 1
         Configuration = "(V (3))"
      End
      Begin PaneConfiguration = 8
         NumPanes = 3
         Configuration = "(H (1[56] 4[18] 2) )"
      End
      Begin PaneConfiguration = 9
         NumPanes = 2
         Configuration = "(H (1 [75] 4))"
      End
      Begin PaneConfiguration = 10
         NumPanes = 2
         Configuration = "(H (1[66] 2) )"
      End
      Begin PaneConfiguration = 11
         NumPanes = 2
         Configuration = "(H (4 [60] 2))"
      End
      Begin PaneConfiguration = 12
         NumPanes = 1
         Configuration = "(H (1) )"
      End
      Begin PaneConfiguration = 13
         NumPanes = 1
         Configuration = "(V (4))"
      End
      Begin PaneConfiguration = 14
         NumPanes = 1
         Configuration = "(V (2))"
      End
      ActivePaneConfig = 0
   End
   Begin DiagramPane = 
      Begin Origin = 
         Top = -96
         Left = 0
      End
      Begin Tables = 
         Begin Table = "org"
            Begin Extent = 
               Top = 138
               Left = 38
               Bottom = 268
               Right = 278
            End
            DisplayFlags = 280
            TopColumn = 1
         End
         Begin Table = "dep"
            Begin Extent = 
               Top = 6
               Left = 848
               Bottom = 136
               Right = 1088
            End
            DisplayFlags = 280
            TopColumn = 1
         End
         Begin Table = "rm"
            Begin Extent = 
               Top = 6
               Left = 593
               Bottom = 136
               Right = 810
            End
            DisplayFlags = 280
            TopColumn = 0
         End
         Begin Table = "av"
            Begin Extent = 
               Top = 6
               Left = 316
               Bottom = 136
               Right = 555
            End
            DisplayFlags = 280
            TopColumn = 0
         End
         Begin Table = "rc"
            Begin Extent = 
               Top = 6
               Left = 38
               Bottom = 136
               Right = 275
            End
            DisplayFlags = 280
            TopColumn = 5
         End
         Begin Table = "vis"
            Begin Extent = 
               Top = 138
               Left = 316
               Bottom = 268
               Right = 511
            End
            DisplayFlags = 280
            TopColumn = 11
         End
         Begin Table = "saa"
            Begin Extent = 
               Top = 138
               Left = 549
               Bottom = 268
               Right = 788
            End
            DisplayFlags = 280
            TopColumn = 0
  ' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'v_RegisteredMembers'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPane2', @value=N'       End
         Begin Table = "sar"
            Begin Extent = 
               Top = 138
               Left = 826
               Bottom = 268
               Right = 1099
            End
            DisplayFlags = 280
            TopColumn = 0
         End
      End
   End
   Begin SQLPane = 
   End
   Begin DataPane = 
      Begin ParameterDefaults = ""
      End
   End
   Begin CriteriaPane = 
      Begin ColumnWidths = 11
         Column = 1440
         Alias = 900
         Table = 1170
         Output = 720
         Append = 1400
         NewValue = 1170
         SortType = 1350
         SortOrder = 1410
         GroupBy = 1350
         Filter = 1350
         Or = 1350
         Or = 1350
         Or = 1350
      End
   End
End
' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'v_RegisteredMembers'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPaneCount', @value=2 , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'v_RegisteredMembers'
GO
