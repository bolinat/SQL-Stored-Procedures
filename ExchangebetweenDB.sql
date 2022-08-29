/* Exchanging info between DB's : 
   1. All the LPR_GEN_XX stored procedures must be installed 
   2. A sceondary DB must be restored and be empty from movements\organizations\departments\registeredmembers\cars
   */


/* STEP A - Import active organizations + Departments + Quotas from Source DB */


declare @OrgsDeps table (ID int identity(1,1),
						 OrgName varchar(50),
						 SiteId uniqueidentifier,
						 DepName varchar(50),
						 allowedcars int,
						 allowedvip int,
						 allowedguests int,
						 togroupaccessrestriction uniqueidentifier,
						 togroupaccessauthorization uniqueidentifier,
						 orgactive bit,
						 depactive bit,
						 OrganizationID uniqueidentifier,
						 DepartmentID uniqueidentifier,
						 processed bit
						 )

insert into @OrgsDeps (OrgName,DepName,allowedcars,allowedvip,allowedguests,orgactive,depactive,processed)
select org.OrganizationName,
		dep.Name,
		gar.ConcurrentCarsAllowedCount,
		gar.VipCarsAllowedCount,
		gar.GuestAllowedCount,
		org.Active,
		dep.Active,
		0
		from IPI_LPR_DB.dbo.Organizations org

		join IPI_LPR_DB.dbo.Departments dep on dep.OrganizationId=org.OrganizationId
		join ipi_LPR_DB.dbo.GroupAccessAuthorizations gaa on gaa.GroupAccessAuthorizationId=dep.GroupAccessAuthorizationId
		join IPI_LPR_DB.dbo.GroupAccessRestrictions gar on gar.GroupAccessRestrictionId=gaa.GroupAccessRestrictionId
		

/* Update SiteId */
update @OrgsDeps set SiteId = (select siteid from ipi_lpr_db2.dbo.sites /*in TargetDB*/)

select * from @OrgsDeps
		
/* Declaring Parameters for the rest of the process */

Declare @ID int,
		@OrgName varchar(50),
		@DepName varchar(50),
		@SiteId uniqueidentifier,
		@AllowedCars int,
		@AllowedVip int,
		@AllowedGuests int,
		@GroupAccessAuthorizationId uniqueidentifier ,
		@GroupAccessRestrictionId uniqueidentifier,
		@OrganizationID uniqueidentifier ,
		@departmentId uniqueidentifier,
		@OrganizationCode varchar(10) = (select max(OrganizationCode) from IPI_LPR_DB2.dbo.Organizations),
		@OrgActive bit,
		@DepActive bit

/* Step B - Create Organizations, Departments and Quotas in Target DB */


IF @OrganizationCode  IS NULL
BEGIN
SET @OrganizationCode='100'
END
ELSE
BEGIN
SET @OrganizationCode=(@OrganizationCode+1)
END

/* Create Orgazanizations  */
WHILE EXISTS (select top (1) ID from @OrgsDeps where processed=0)
BEGIN
SET @ID=(select top (1) ID from @OrgsDeps where processed=0)
SET @OrgName=(SELECT OrgName FROM @OrgsDeps WHERE ID=@ID) 
SET @SiteId=(SELECT SiteId FROM @OrgsDeps WHERE ID=@ID) 
SET @OrgActive=(SELECT orgactive FROM @OrgsDeps WHERE ID=@ID) 

/*  Create Only Non Existent Orgs on the Target DB) */
IF NOT EXISTS ( SELECT OrganizationName  FROM IPI_LPR_DB2.DBO.Organizations WHERE OrganizationName=@OrgName)
BEGIN
SET @GroupAccessAuthorizationId=NEWID()
SET @GroupAccessRestrictionId=NEWID()
SET @OrganizationID = NEWID()

Insert into GroupAccessRestrictions (GroupAccessRestrictionId,
									 TimeBoundsAccessRestrictionId,
									 ParkingPassageAccessRestrictionId,
									 PersistedTimeAccessRestrictionId,
									 EntrancesAccessRestrictionId,
									 StayTimeAllowed,
									 ConcurrentCarsAllowedCount,
									 CurrentCarsCount,
									 GuestAllowedCount,
									 VipCarsAllowedCount)

		values (
		@GroupAccessRestrictionId , /*GroupAccessRestrictionId*/
		null,/*TimeBoundsAccessRestrictionId*/
		null,/*ParkingPassageAccessRestrictionId*/
		null,/*PersistedTimeAccessRestrictionId*/
		null,/*EntrancesAccessRestrictionId*/
		null,/*StayTimeAllowed*/
		@AllowedCars,/*ConcurrentCarsAllowedCount*/
		0,/*CurrentCarsCount*/
		@AllowedGuests,/*GuestAllowedCount*/
		@AllowedVip/*VipCarsAllowedCount*/
		)

insert into GroupAccessAuthorizations ( GroupAccessAuthorizationId,
										StartTime,
										EndTime,
										IsTimeLimited,
										IsAuthorized,
										GroupAccessRestrictionId,
										IsRestricted,
										IsLimitValidityAlways,
										IsParentInheritance,
										IsQuotaEnabled)
values (
		@GroupAccessAuthorizationId,/*GroupAccessAuthorizationId*/
		getdate(),/*StartTime*/
		'9999-12-31 23:59:59.997',/*EndTime*/
		0,/*IsTimeLimited*/
		1,/*IsAuthorized*/
		@GroupAccessRestrictionId,/*GroupAccessRestrictionId*/
		0,/*IsRestricted*/
		1,/*IsLimitValidityAlways*/
		0,/*IsParentInheritance*/
		null/*IsQuotaEnabled*/
		)
		
SET IDENTITY_INSERT dbo.Organizations ON
insert into Organizations (
			OrganizationId,
			OrganizationCode,
			SiteId,
			OrganizationName,
			OrganizationVisualName,
			Description,
			GroupAccessAuthorizationId,
			CreationTime,
			Active,
			IsDeleted)

			values (
		@OrganizationID,/*OrganizationId*/
		cast(@OrganizationCode as int),/*OrganizationCode*/
		@SiteId ,/*SiteId*/
		@OrgName,/*OrganizationName*/
		@OrgName,/*OrganizationVisualName*/
		@OrgName,/*Description*/
		@GroupAccessAuthorizationId,/*GroupAccessAuthorizationId*/
		getdate(),/*CreationTime*/
		@OrgActive,/*Active*/
		0/*IsDeleted*/
		)

print 'Organization = ' + @OrgName + ' Created' 
print 'OrganizationId=' +cast(@OrganizationId as nvarchar(100))
print 'GroupAccessAuthorizationId=' +cast(@GroupAccessAuthorizationId as nvarchar(100))
print 'GroupAccessRestrictionId=' +cast(@GroupAccessRestrictionId as nvarchar(100))

SET IDENTITY_INSERT dbo.Organizations OFF	

UPDATE @OrgsDeps SET processed=1,OrganizationID=@OrganizationID WHERE ID=@ID
END
ELSE
BEGIN
set @OrganizationID=(select organizationID from IPI_LPR_DB2.dbo.Organizations where OrganizationName=@OrgName)
UPDATE @OrgsDeps SET processed=1,OrganizationID=@OrganizationID WHERE ID=@ID
END
END
/* Create Departments */
Update @OrgsDeps set processed=0

WHILE EXISTS (SELECT TOP (1) ID FROM @OrgsDeps WHERE processed=0)
BEGIN
SET @ID=(SELECT TOP (1) ID FROM @OrgsDeps WHERE processed=0)
SET @DepName=(SELECT DepName FROM @OrgsDeps WHERE ID=@ID)
SET @OrganizationID=(SELECT OrganizationID FROM @OrgsDeps WHERE ID=@ID)
SET @AllowedCars=(SELECT allowedcars FROM @OrgsDeps WHERE ID=@ID) 
SET @AllowedVip=(SELECT allowedvip FROM @OrgsDeps WHERE ID=@ID) 
SET @AllowedGuests=(SELECT allowedguests FROM @OrgsDeps WHERE ID=@ID) 
SET @DepActive=(SELECT depactive FROM @OrgsDeps WHERE ID=@ID) 

IF NOT EXISTS (select DepartmentID from IPI_LPR_DB2.dbo.Departments where name=@DepName and OrganizationId=@OrganizationID)
BEGIN
EXEC dbo.LPR_gen_DepartmentAdd @OrganizationId =@OrganizationID,
	@DepartmentName = @DepName,
	@Description = @DepName,
	@Active =@DepActive,
	@AllowedCars =@AllowedCars,
	@AllowedVIP =@AllowedVip,
	@AllowedGuests =@AllowedGuests

update @OrgsDeps set DepartmentID=(select DepartmentID from IPI_LPR_DB2.dbo.Departments where name=@DepName and OrganizationId=@OrganizationID), processed =1 where id=@ID
END
ELSE
BEGIN
update @OrgsDeps set DepartmentID=(select DepartmentID from IPI_LPR_DB2.dbo.Departments where name=@DepName and OrganizationId=@OrganizationID), processed =1 where id=@ID
END

END
--------------------------------------------------------------------------------------------------------------------------

/* STEP C - Fill FloatingCounters Table (if exists ) */
IF EXISTS (SELECT NAME FROM SYS.tables WHERE NAME='FloatingCounters')
BEGIN

EXEC IPI_LPR_DB2.dbo.usp_lpr_FillFloatingCountersTable
END

/* STEP D - import registered members and cars */

insert into LoadSubsInfo (FirstName,
							LastName,
							LicensePlate,
							IdNumber,
							Validation,
							Phone,
							IsVIP,
							OrganizationName,
							DepartmentName,
							CarsAllowed,
							LoadStatus,
							IsProcessed,
							IsGuest,
							CarActive,
							MemActive)

select  cast([name] as nvarchar(20)),
		cast(lastname as nvarchar(20)),
		cast(carnumber as nvarchar(15)),
		cast(IdNumber as nvarchar(20)),
		ISNULL(VSValidUntil,'9999-12-31 23:59:59.997'),
		cast(ISNULL(PhoneNumber1,'') as nvarchar(10)),
		IsVip,
		cast(ORG as nvarchar(20)),
		cast(Department as nvarchar(20)),
		ConcurrentCarsAllowedCount,
		0,
		0,
		0,
		RCActive,
		VSActive
from IPI_LPR_DB.dbo.v_RegisteredMembers
where carnumber is not null /* Import only Members with cars */
order by org,Department,VisitorId,CarNumber



/* Load Subscribers into target DB */
								
declare @Load table (id int identity(1,1),
						siteid uniqueidentifier,
						organizationid uniqueidentifier,
						departmentid uniqueidentifier,
						organizationname varchar(50),
						departmentname varchar(50),
						processed bit)
insert into @Load 
select siteId,org.organizationID,dep.departmentId,org.OrganizationVisualName,dep.Name, 0 from IPI_LPR_DB2.dbo.Organizations org
join Departments dep on dep.OrganizationId=org.OrganizationId




while exists (select top(1) id from @Load where processed=0)
begin
set @id=(select top(1) id from @Load where processed=0)
set @organizationId=(select organizationid from @Load where id=@id)
set @departmentId=(select departmentid from @Load where id=@id)
set @siteId=(select siteid from @Load where id=@id)





update @Load set processed=1 where id=@id
END


