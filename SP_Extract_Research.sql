USE [BH_RESEARCH]
GO
/****** Object:  StoredProcedure [dbo].[Sp_Extract_Research_Dev]    Script Date: 07/12/2023 14:24:32 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-------------------------------------------------------------
-- Author:		Ben Eaton
-- Create date: 07-Dec-2020
-- Description:	This SP loops through the CDS , CDE and Millennium tables
--			    required for the extract and write the contents to the 
--				JSON file.
-- Modified on 2022 September to add Powertials and NHS Number/MRN aliases as subjects and fixes to NHS_Number inconsistency.
--
-- Modified on  2021 April to report the complete Diagnosis, Careplan, Treatment etc for all the patient from SCR dataset

-- Modified on 29 June 2021 
--             Added temp tables to hold Orders, Clinical event and Blob data for all Patient encounters to improve performance     
-- Modified on 25 july 2021
--             Added below columns to the extract.
--             ENCNTR_ID -					Powerforms
--			   EVENTID -					Blobdata, Imaging, Pathology
--			   FHX_VALUE_FLG -				FamilyHistory
-- Modified on January 2022 --CDS table are joined to demographics table on person id to include all records when nhs number is missing

-- Modified on 22 June 2022
-- Description: New script added to create a local copy of [BH_IMAGING].[CSS_BI].[Tbl_NHSI_Exam_Mapping] table into our
--			   BH_Research database. This table will recreated everytime this SP executes
------------------------------------------------------------------

ALTER PROCEDURE [dbo].[Sp_Extract_Research] 
(
@EXTRACT_ID INT, @DATE DATETIME, @Anonymous INT
)
AS
BEGIN

----------------------------------------------
-- Error Handling variables
----------------------------------------------
Declare @ErrorPosition	Integer
Declare @Row_Count		Integer
Declare @ErrorModule	varchar(50)	
Declare @ErrorMessage   Varchar(200)

Set @ErrorMessage	= ''								-- Initialise Error message to blank
Set @ErrorModule	= 'Sp_Extract_Research'		        -- Set to stored procedure name 
Declare @StartDate		 DATETIME						--Get date and time of when load starts
Declare @EndDate		 DATETIME
Declare @SPstart		 DATETIME						--Get date and time of when load completes
    													--Get date and time of when load completes
Declare @time			varchar(1000)					--Get the exact time taken to complete this section		
Declare @Filetype       VARCHAR(50)						--Get the output file type for this extract

-----------------------------------------------
--Declaring CONTROL variables for each element
-----------------------------------------------
SET @SPstart=GETDATE()     
          

Declare @Demographics      int,   --(1/0)    --1
        @APCDiagnosis      int,   --(1/0)    --3
        @APCProcedures     int,   --(1/0)    --4
        @OPADiagnosis      int,   --(1/0)    --3
        @OPAProcedures     int,   --(1/0)    --5
        @Inpatient         int,   --(1/0)    --6
        @Outpatient        int,   --(1/0)    --7
        @Pathology         int,   --(1/0)    --8
        @PharmacyAria      int,   --(1/0)    --9
        @PowerForms        int,   --(1/0)    --10
        @Radiology         int,   --(1/0)    --11
        @FamilyHistory     int,   --(1/0)    --12
        @BLOBdata          int,   --(1/0)    --13
        @PCProblems        int,   --(1/0)    --14
        @PCProcedures      int,   --(1/0)    --15
        @PCDiagnosis       int,   --(1/0)    --16
        @MSDS              int,   --(1/0)    --17
        @SCR               int,   --(1/0)    --18
        @Allergy           int,   --(1/0)    --19
        @PharmacyOrders    int,    --(1/0)   --20
		@PowertrialsPart   int,     --(1/0)  --21

		@Aliases		   int,     --(1/0)  --22
		@CritCare		   int,     --(1/0)  --23
		@Measurements	   int,     --(1/0)  --24
		@Emergency		   int     --(1/0)   --25


--select * from [BH_DATAWAREHOUSE].dbo.[LKP_RESEARCH_EXTRACT_DATA_ELEMENTS]
--------------------------------------------------------------------------
--Check the elments based on the extract id provided 

IF OBJECT_ID('tempdb..#Config') IS NOT NULL DROP TABLE #Config

SELECT C.Extract_ID, C.Element_ID, E.Element_Desc INTO #Config
 FROM [BH_RESEARCH].dbo.[RESEARCH_EXTRACT_DATA_ELEMENTS_CONFIG] C
 INNER JOIN [BH_RESEARCH].dbo.[LKP_RESEARCH_EXTRACT_DATA_ELEMENTS] E
  ON C.Element_ID=E.Element_ID AND C.Extract_ID=@Extract_ID

--Select * from #Config

select @Filetype =[File_Format] from [BH_RESEARCH].DBO.[RESEARCH_EXTRACT_CONFIG] where Extract_ID=@EXTRACT_ID
print @filetype


--------------------------------------------------------------------------------
--Set the variable to 1 if they are part of the extract id provided

SELECT @Demographics= 1    FROM #Config WHERE (Element_Desc='Demographics') 
--SELECT @AttendanceType= 1  FROM #Config WHERE (Element_Desc= 'AttendanceType')
SELECT @APCDiagnosis= 1    FROM #Config WHERE (Element_Desc=  'APCDiagnosis')
SELECT @APCProcedures= 1   FROM #Config WHERE (Element_Desc= 'APCProcedure') 
SELECT @OPADiagnosis= 1    FROM #Config WHERE (Element_Desc=  'OPADiagnosis')
SELECT @OPAProcedures= 1   FROM #Config WHERE (Element_Desc=  'OPAProcedure') 
SELECT @Inpatient= 1       FROM #Config WHERE (Element_Desc= 'Inpatient') 
SELECT @Outpatient= 1      FROM #Config WHERE (Element_Desc= 'Outpatient') 
SELECT @Pathology= 1       FROM #Config WHERE (Element_Desc= 'Pathology') 
SELECT @PharmacyAria= 1    FROM #Config WHERE (Element_Desc= 'Aria') 
SELECT @PowerForms=1       FROM #Config WHERE (Element_Desc= 'Documentation') 
SELECT @Radiology=1        FROM #Config WHERE (Element_Desc= 'Imaging') 
SELECT @FamilyHistory= 1   FROM #Config WHERE (Element_Desc= 'Family History') 
SELECT @BLOBdata= 1        FROM #Config WHERE (Element_Desc= 'BLOB data') 
SELECT @PCProblems= 1      FROM #Config WHERE (Element_Desc= 'PCProblems') 
SELECT @PCProcedures= 1    FROM #Config WHERE (Element_Desc= 'PCProcedures') 
SELECT @PCDiagnosis= 1     FROM #Config WHERE (Element_Desc= 'PCDiagnosis') 
SELECT @MSDS=1             FROM #Config WHERE (Element_Desc= 'Maternity') 
SELECT @SCR=1              FROM #Config WHERE (Element_Desc= 'SCR') 
SELECT @PharmacyOrders=1   FROM #Config WHERE (Element_Desc= 'PharmacyOrders') 
SELECT @Allergy=1          FROM #Config WHERE (Element_Desc= 'Allergy') 
SELECT @PowertrialsPart=1  FROM #Config WHERE (Element_Desc= 'Powertrials') 
SELECT @Aliases=1		   FROM #Config WHERE (Element_Desc= 'Aliases')
SELECT @CritCare=1		   FROM #Config WHERE (Element_Desc = 'CritCare')
SELECT @Measurements=1	   FROM #Config WHERE (Element_Desc = 'Measurements')
SELECT @Emergency=1	   	   FROM #Config WHERE (Element_Desc = 'EmergencyDepartment')


------------------------------------------------------------------------------------------
--Error Handling

Begin Try

--In a csv filetype this function replaces null with empty string, affixes quotation marks around the strings and replaces any double quotations
--inside the string with single quotations.


--------------------------------------------------------------------------------------------
----Patient Demographic details
--------------------------------------------------------------------------------------------
----NHS number	   [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT]		 [NHS_Number]
--date of birth	   [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT]		 [Birth_Dt]
--stated gender	   [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT]		 GENDER_CD
--stated gender	   [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF]	 CODE_DESC_TXT  AS [Gender] 
--ethnicity	       [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT]		 ETHNIC_GROUP_CD
--ethnicity	       [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF]	 CODE_DESC_TXT  AS [Ethnicity] 
--date of death    [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT]		 [DECEASED_DT_TM]




Set @ErrorPosition = 10	
SET @ErrorMessage='Patient Demographics'
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Patient_Demographics', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Patient_Demographics

Set @ErrorPosition = 20	
SET @ErrorMessage='Patient Demographics temptable created'

IF @Demographics=1

  BEGIN
 
 SELECT	@StartDate = GETDATE();
 SELECT  
        REPLACE(Pat.[NHS_NBR_IDENT],'-','')							AS [NHS_Number]   
        ,CAST(Pat.BIRTH_DT_TM AS DATE)								AS [Date_of_Birth]
		,Gend.ALIAS_NHS_CD_ALIAS									AS [GENDER_CD]
        ,GEND.CODE_DISP_TXT											AS [Gender] 
		,Eth.ALIAS_NHS_CD_ALIAS										AS [ETHNIC_CD]
        ,Eth.CODE_DESC_TXT											AS [Ethnicity]
        ,Pat.DECEASED_DT_TM											AS [Date_of_Death]
        ,Pat.[PERSON_ID]
        ,Pat.LOCAL_PATIENT_IDENT									AS [MRN]
		,(SELECT TOP(1) POSTCODE_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT_ADDRESS] A WHERE A.PERSON_ID = Pat.PERSON_ID ORDER BY END_EFFECTIVE_DT_TM  DESC) AS [Postcode]
		,(SELECT TOP(1) CITY_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT_ADDRESS] A WHERE A.PERSON_ID = Pat.PERSON_ID ORDER BY END_EFFECTIVE_DT_TM  DESC) AS [City]
		,MARITAL_STATUS_CD											AS [MARITAL_STATUS_CD]
		,Mart.CODE_DESC_TXT											AS [MARITAL_STATUS]
		,LANGUAGE_CD												AS [LANGUAGE_CD]
		,lang.CODE_DESC_TXT											AS [LANGUAGE]
		,RELIGION_CD												AS [RELIGION_CD]
		,Reli.CODE_DESC_TXT											AS [RELIGION]
     INTO  BH_RESEARCH.DBO.RDE_Patient_Demographics

    FROM  [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT] Pat with (nolock)
          INNER JOIN [BH_RESEARCH].[dbo].[RESEARCH_PATIENTS] Res
               --ON  REPLACE(Pat.[NHS_NBR_IDENT],'-','')=Res.NHS_Number
			   ON PAT.PERSON_ID=RES.PERSONID
	      LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] Eth with (nolock)
               ON Pat.ETHNIC_GROUP_CD=Eth.CODE_VALUE_CD
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] Gend with (nolock)
               ON Pat.GENDER_CD=Gend.CODE_VALUE_CD
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] Mart with (nolock)
               ON Pat.MARITAL_STATUS_CD=Mart.CODE_VALUE_CD
		  LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] lang with (nolock)
               ON Pat.LANGUAGE_CD=lang.CODE_VALUE_CD
		  LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] Reli with (nolock)
               ON Pat.RELIGION_CD=Reli.CODE_VALUE_CD
    WHERE RES.EXTRACT_ID=@EXTRACT_ID


SELECT @Row_Count=@@ROWCOUNT
SELECT	@EndDate = GETDATE();

SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PatientDemograhics1', @StartDate, @EndDate,@time,@Row_Count)



UPDATE Demo SET NHS_Number = 
(SELECT TOP(1) ALIAS FROM BH_DATAWAREHOUSE.DBO.MILL_DIR_PERSON_ALIAS A 
WHERE PERSON_ALIAS_TYPE_CD = 18 AND ACTIVE_IND = 1 AND A.PERSON_ID = Demo.PERSON_ID ORDER BY END_EFFECTIVE_DT_TM  DESC) FROM BH_RESEARCH.DBO.RDE_Patient_Demographics Demo WHERE NHS_Number IS NULL

UPDATE Demo SET MRN = 
(SELECT TOP(1) ALIAS FROM BH_DATAWAREHOUSE.DBO.MILL_DIR_PERSON_ALIAS A 
WHERE PERSON_ALIAS_TYPE_CD = 10 AND ACTIVE_IND = 1 AND A.PERSON_ID = Demo.PERSON_ID ORDER BY END_EFFECTIVE_DT_TM  DESC) FROM BH_RESEARCH.DBO.RDE_Patient_Demographics Demo WHERE MRN IS NULL 

--SELECT TOP 2* FROM [BH_DATAWAREHOUSE].[dbo].[PI_CDE_ENCOUNTER]
Set @ErrorPosition = 30	
SET @ErrorMessage='Patient Demographics details added to temptable'

------------------------------------------------------------------------------------------------------
Set @ErrorPosition = 40	
SET @ErrorMessage='Encounter details'

 SELECT	@StartDate = GETDATE();

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Encounter', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Encounter

 SELECT E.PERSON_ID,E.ENCNTR_ID,D.NHS_Number,dbo.csvString(E.REASON_FOR_VISIT_TXT) AS REASON_FOR_VISIT_TXT, D.MRN
          ,E.[ENC_TYPE_CD],etype.CODE_DESC_TXT as ENC_TYPE
          ,E.ENC_STATUS_CD,estat.CODE_DESC_TXT as ENC_STATUS,E.FIN_NBR_ID
          ,E.ADMIN_CATEGORY_CD ,dbo.csvString(ADM.CODE_DESC_TXT) AS ADMIN_DESC
          ,E.TREATMENT_FUNCTION_CD,dbo.csvString(TFC.CODE_DESC_TXT) AS TFC_DESC ,E.VISIT_ID ,CREATE_DT_TM
   INTO  BH_RESEARCH.DBO.RDE_Encounter
     FROM  [BH_DATAWAREHOUSE].[dbo].[PI_CDE_ENCOUNTER]  E with (nolock)
        INNER JOIN   BH_RESEARCH.DBO.RDE_Patient_Demographics D 
           ON  E.PERSON_ID=D.PERSON_ID
        LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] ADM with (nolock)
		   ON E.ADMIN_CATEGORY_CD=ADM.CODE_VALUE_CD
	    LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] TFC with (nolock)
		   ON E.TREATMENT_FUNCTION_CD=TFC.CODE_VALUE_CD
        LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] etype with (nolock)
		   ON E.ENC_TYPE_CD=etype.CODE_VALUE_CD
	    LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[PI_LKP_CDE_CODE_VALUE_REF] estat with (nolock)
		   ON E.ENC_STATUS_CD=estat.CODE_VALUE_CD
		   where CAST(e.EXTRACT_DT_TM AS DATE)>=@DATE
		  

SELECT @Row_Count=@@ROWCOUNT
--select * from  BH_RESEARCH.DBO.RDE_Encounter
CREATE INDEX INDX_DET_ENC1 ON  BH_RESEARCH.DBO.RDE_Encounter (ENCNTR_ID)

SET @ErrorPosition = 50	
SET @ErrorMessage='Patient encounter details added to temptable'
SELECT	@EndDate = GETDATE();

SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Encounter', @StartDate, @EndDate,@time,@Row_Count)
END
------------------------------------------------------------------------------------
--Pulling ORDERS, CLINICAL EVENT, BLOB data for all patient enconter into Temp tables for better performance
--orders table and clinical events
-------------------------------------------------------------------------------------------

IF OBJECT_ID(N'BH_RESEARCH.DBO.TempOrder', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempOrder
IF OBJECT_ID(N'BH_RESEARCH.DBO.TempCE', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempCE
IF OBJECT_ID(N'BH_RESEARCH.DBO.TempBlob', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempBlob

IF OBJECT_ID(N'BH_RESEARCH.DBO.TempAlias', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempAlias

IF OBJECT_ID(N'BH_RESEARCH.DBO.TempAPC', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempAPC
IF OBJECT_ID(N'BH_RESEARCH.DBO.TempOPA', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.DBO.TempOPA

--TEMPORDER
SELECT	@StartDate = GETDATE();
SELECT ORD.* INTO BH_RESEARCH.DBO.TempOrder 
FROM [BH_DATAWAREHOUSE].DBO.PI_CDE_Order ORD with(nolock)
INNER JOIN   BH_RESEARCH.DBO.RDE_Encounter ENC with(nolock) ON ENC.encntr_id=ORD.encntr_id

SELECT @Row_Count=@@ROWCOUNT
CREATE clustered INDEX indx_Order_ID ON BH_RESEARCH.DBO.TempOrder (ORDER_ID)
CREATE  INDEX indx_Order_ENCTRID ON BH_RESEARCH.DBO.TempOrder (ENCNTR_ID)

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempOrder',@StartDate, @EndDate,@time,@Row_Count)
--------------------------------------------------------------------------------------

--TEMP CLINICAL EVENT
SELECT	@StartDate = GETDATE();
SELECT CE.* INTO BH_RESEARCH.DBO.TempCE 
FROM [BH_DATAWAREHOUSE].DBO.PI_CDE_CLINICAL_EVENT CE with(nolock)
INNER JOIN    BH_RESEARCH.DBO.RDE_Encounter ENC with(nolock) ON ENC.encntr_id=CE.encntr_id
SELECT @Row_Count=@@ROWCOUNT

CREATE clustered INDEX indx_Event_ID ON BH_RESEARCH.DBO.TempCE (EVENT_ID)
CREATE  INDEX indx_CE_ENCTRID ON BH_RESEARCH.DBO.TempCE (ENCNTR_ID)



SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempClinicalEvent',@StartDate, @EndDate,@time,@Row_Count)
--------------------------------------------------------------------------------------

--TEMP BLOB DATASET
SELECT	@StartDate = GETDATE();
SELECT B.* INTO BH_RESEARCH.DBO.TempBLOB 
FROM [BH_DATAWAREHOUSE].DBO.PI_DIR_BLOB_CONTENT B with(nolock)
INNER JOIN   BH_RESEARCH.DBO.TempCE CE with(nolock) ON CE.EVENT_ID=B.EVENT_ID
SELECT @Row_Count=@@ROWCOUNT
CREATE  INDEX indx_BEvent_ID ON BH_RESEARCH.DBO.TempBLOB (EVENT_ID)


SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempBlob', @StartDate, @EndDate,@time,@Row_Count)



--TEMP ALIAS
SELECT	@StartDate = GETDATE();
SELECT A.* INTO BH_RESEARCH.DBO.TempAlias
FROM BH_DATAWAREHOUSE.DBO.MILL_DIR_PERSON_ALIAS A with(nolock)
WHERE ACTIVE_IND = 1
AND PERSON_ID IN (SELECT PERSON_ID FROM BH_RESEARCH.DBO.RDE_Patient_Demographics)
SELECT @Row_Count=@@ROWCOUNT
CREATE NONCLUSTERED INDEX [ix_Research_PersAlias_Alias] ON BH_RESEARCH.DBO.TempAlias
(
    [ALIAS] ASC
)
INCLUDE (PERSON_ALIAS_TYPE_CD, PERSON_ID);

CREATE NONCLUSTERED INDEX tempalias_type_cd_ix
ON BH_RESEARCH.[dbo].[TempAlias] ([PERSON_ALIAS_TYPE_CD])
INCLUDE ([PERSON_ID],[ALIAS])


SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempAlias', @StartDate, @EndDate,@time,@Row_Count)


--TEMP APC
SELECT	@StartDate = GETDATE();
SELECT DISTINCT A.CDS_APC_ID, LALIAS.PERSON_ID, A.Start_dt, A.CDS_Activity_Dt 
INTO BH_RESEARCH.DBO.TempAPC
FROM BH_RESEARCH.DBO.TempAlias LALIAS
RIGHT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_APC] A with(nolock)
ON LALIAS.ALIAS = A.NHS_NUMBER AND LALIAS.PERSON_ALIAS_TYPE_CD = 18
WHERE LALIAS.PERSON_ID IS NOT NULL

UNION

SELECT DISTINCT A.CDS_APC_ID, LALIAS.PERSON_ID, A.Start_dt, A.CDS_Activity_Dt 
FROM BH_RESEARCH.DBO.TempAlias LALIAS
RIGHT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_APC] A with(nolock)
ON LALIAS.ALIAS = A.mrn AND LALIAS.PERSON_ALIAS_TYPE_CD = 10
WHERE LALIAS.PERSON_ID IS NOT NULL;


SELECT @Row_Count=@@ROWCOUNT


CREATE NONCLUSTERED INDEX tempapc_id_ix
ON BH_RESEARCH.[dbo].[TempAPC] ([CDS_APC_ID])
INCLUDE ([PERSON_ID],[Start_dt], [CDS_Activity_Dt])


SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempAPC', @StartDate, @EndDate,@time,@Row_Count)


			
--TEMP OPA
SELECT	@StartDate = GETDATE();

SELECT A.CDS_OPA_ID, LALIAS.PERSON_ID, A.Att_Dt, A.CDS_Activity_Dt
INTO BH_RESEARCH.DBO.TempOPA
FROM BH_RESEARCH.DBO.TempAlias LALIAS
RIGHT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] A WITH(NOLOCK)
ON LALIAS.ALIAS = A.NHS_NUMBER AND LALIAS.PERSON_ALIAS_TYPE_CD = 18
WHERE LALIAS.PERSON_ID IS NOT NULL

UNION

SELECT A.CDS_OPA_ID, LALIAS.PERSON_ID, A.Att_Dt, A.CDS_Activity_Dt
FROM BH_RESEARCH.DBO.TempAlias LALIAS
RIGHT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] A WITH(NOLOCK)
ON LALIAS.ALIAS = A.mrn AND LALIAS.PERSON_ALIAS_TYPE_CD = 10
WHERE LALIAS.PERSON_ID IS NOT NULL;


SELECT @Row_Count=@@ROWCOUNT



CREATE NONCLUSTERED INDEX tempopa_id_ix
ON BH_RESEARCH.[dbo].[TempOPA] ([CDS_OPA_ID])
INCLUDE ([PERSON_ID],[Att_dt], [CDS_Activity_Dt])


SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'TempOPA', @StartDate, @EndDate,@time,@Row_Count)





--------------ICD DIAGNOSIS DEATILS--------------------------------------------------
--------------------------------------------------------------------------------------
--CDS date					[BH_DATAWAREHOUSE].[dbo].[CDS_APC]				[Activity_Dt_Tm]
--diagnosis code			[BH_DATAWAREHOUSE].[dbo].[CDS_APC_ICD_DIAG] 	[ICD_Diagnosis_Cd] 
--diagnosis description		[BH_DATAWAREHOUSE].[dbo].[LKP_ICD_DIAG]			[ICD_Diag_Desc]
--diagnosis sequence		[BH_DATAWAREHOUSE].[dbo].[CDS_APC_ICD_DIAG] 	[ICD_Diagnosis_Num] 

SET @ErrorPosition=60
SET @ErrorMessage='Inaptient Diagnosis'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS
	CREATE TABLE  BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS (
		CDS_APC_ID				VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN                    VARCHAR(20)
		,[ICD_Diagnosis_Num]	INT
		,[ICD_Diagnosis_Cd]		VARCHAR(10)
		,[ICD_Diag_Desc]		VARCHAR(250)
		,NHS_NUMBER				VARCHAR(20)
		,Activity_date			VARCHAR(16)
		,[CDS_Activity_Dt]		VARCHAR(16))

SET @ErrorPosition=70
SET @ErrorMessage='Inaptient Diagnosis temp table created'
		
IF @APCDiagnosis=1
   BEGIN

  SELECT @StartDate =GETDATE()

       INSERT INTO  BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS
         SELECT DISTINCT
	     	CONVERT(VARCHAR(20),Apc.CDS_APC_ID)                         AS CDS_APC_ID
			,CONVERT(VARCHAR(20),APC.PERSON_ID)                      AS PERSONID
			,PAT.MRN													AS MRN
		    ,CONVERT(INT,[ICD_Diagnosis_Num])                           AS ICD_Diagnosis_Num
		    ,CONVERT(VARCHAR(10),[ICD_Diagnosis_Cd])                    AS ICD_Diagnosis_Cd
		    ,CONVERT(VARCHAR(250),dbo.csvString(ICDDESC.[ICD_Diag_Desc]) )             AS ICD_Diag_Desc
		    ,PAT.NHS_Number                        						AS NHS_Number
		    ,CONVERT(VARCHAR(16),Apc.Start_Dt,120)                      AS Activity_date
		    ,CONVERT(VARCHAR(16),[CDS_Activity_Dt],120)                 AS [CDS_Activity_Dt]
		
            FROM [BH_DATAWAREHOUSE].[dbo].[CDS_APC_ICD_DIAG] Icd with (nolock)
            INNER JOIN  BH_RESEARCH.DBO.TempAPC Apc with (nolock)
            ON Icd.CDS_APC_ID=APC.CDS_APC_ID
            INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = APC.PERSON_ID
			LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_ICD_DIAG] ICDDESC with (nolock)
			ON Icd.ICD_Diagnosis_Cd = ICDDESC.[ICD_Diag_Cd]
			WHERE PAT.MRN IS NOT NULL
			AND CAST(Apc.Start_Dt AS DATE)>=@DATE
			ORDER BY Activity_date

SELECT @Row_Count=@@ROWCOUNT	
		
SET @ErrorPosition=80
SET @ErrorMessage='Inpatient diagnosis details inserted into Temptable'	

--ADD DOUBLE QUOTES AROUND THE ICD DIAGNOSIS DECRIPTION FIELD

CREATE INDEX indx_CDS_APC_ID ON  BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS (CDS_APC_ID)


SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Inpatient Diagnosis', @StartDate, @EndDate,@time,@Row_Count)

    END
----------------------------------------------------------------------------------------
---------------APC -OPCS DETAILS FOR INPATIENTS
------------------------------------------------------------------------------------------
--CDS date				[BH_DATAWAREHOUSE].[dbo].[CDS_APC]					[Start_Dt]
--procedure date		[BH_DATAWAREHOUSE].[dbo].[CDS_APC_OPCS_PROC] 		[OPCS_Proc_Dt]
--procedure code		[BH_DATAWAREHOUSE].[dbo].[CDS_APC_OPCS_PROC]		OPCS_Proc_Cd
--procedure description	[BH_DATAWAREHOUSE].[dbo].[LKP_OPCS_49]				[Proc_Desc]
--procedure sequence	[BH_DATAWAREHOUSE].[dbo].[CDS_APC_OPCS_PROC] 		[OPCS_Proc_Num]

Set @ErrorPosition=90
Set @ErrorMessage='Inpatient Procedures'
 
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_APC_OPCS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_APC_OPCS
	CREATE TABLE  BH_RESEARCH.DBO.RDE_APC_OPCS (
		CDS_APC_ID			 VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN                 VARCHAR(20)
		,OPCS_Proc_Num		 INT
		,OPCS_Proc_Scheme_Cd VARCHAR(10)
		,OPCS_Proc_Cd		 VARCHAR(10)
		,Proc_Desc			 VARCHAR(300)
		,OPCS_Proc_Dt		 VARCHAR(16)
		,NHS_NUMBER			 VARCHAR(20)
		,Activity_date		 VARCHAR(16)
		,[CDS_Activity_Dt]	 VARCHAR(16))

SET @ErrorPosition=100
SET @ErrorMessage='Inpatient Procedure temp table created'
 
IF @APCProcedures=1
  BEGIN

  SELECT @StartDate =GETDATE()
  


     INSERT INTO  BH_RESEARCH.DBO.RDE_APC_OPCS
        SELECT DISTINCT
		    CONVERT(VARCHAR(20),Apc.CDS_APC_ID)						AS CDS_APC_ID
		   ,APC.PERSON_ID                                        AS PERSONID
		   ,Pat.MRN													AS MRN
		   ,CONVERT(INT,OPCS_Proc_Num)								AS OPCS_Proc_Num
		   ,CONVERT(VARCHAR(10),OPCS_Proc_Scheme_Cd)				AS OPCS_Proc_Scheme_Cd
		   ,CONVERT(VARCHAR(10),OPCS_Proc_Cd)						AS OPCS_Proc_Cd
		   ,CONVERT(VARCHAR(300),dbo.csvString( PDesc.Proc_Desc))   AS Proc_Desc			----ADD DOUBLE QUOTES AROUND THE PROC DESCRIPTION FIELD
		   ,CONVERT(VARCHAR(16),OPCS.OPCS_Proc_Dt,120)				AS OPCS_Proc_Dt
		   ,Pat.NHS_Number											AS NHS_Number
		   ,CONVERT(VARCHAR(16),Apc.Start_Dt,120)					AS Activity_date
		   ,CONVERT(VARCHAR(16),[CDS_Activity_Dt],120)				AS [CDS_Activity_Dt]
  FROM [BH_DATAWAREHOUSE].[dbo].[CDS_APC_OPCS_PROC] OPCS with (nolock)
              INNER JOIN  BH_RESEARCH.DBO.TempAPC Apc with (nolock)
            ON OPCS.CDS_APC_ID=APC.CDS_APC_ID
        LEFT JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = APC.PERSON_ID
        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_OPCS_410] PDesc with (nolock)
        ON OPCS.OPCS_Proc_Cd = PDesc.Proc_Cd
        WHERE PAT.MRN IS NOT NULL
        AND CAST(Apc.Start_Dt AS DATE)>=@DATE

SELECT @Row_Count=@@ROWCOUNT
		
CREATE INDEX indx_CDS_APCID ON  BH_RESEARCH.DBO.RDE_APC_OPCS (CDS_APC_ID)

SET @ErrorPosition=110
SET @ErrorMessage='Inpatient Procedures inserted into Temptable'	

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Inpatient Procedures', @StartDate, @EndDate,@time,@Row_Count)		
 END

-----------------------------------------------------------------------------------------
---------------ICD DEATAILS FOR OUTPATIENTS----------------------------------------------
-----------------------------------------------------------------------------------------

SET @ErrorPosition=120
SET @ErrorMessage='Outpatient Diagnosis'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_OP_DIAGNOSIS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_OP_DIAGNOSIS
	CREATE TABLE  BH_RESEARCH.DBO.RDE_OP_DIAGNOSIS (
		CDS_OPA_ID				VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN      				VARCHAR(20)
		,[ICD_Diagnosis_Num]	INT
		,[ICD_Diagnosis_Cd]		VARCHAR(10)
		,[ICD_Diag_Desc]		VARCHAR(250)
		,NHS_Number				VARCHAR(20)
		,Activity_date			VARCHAR(16)
		,[CDS_Activity_Dt]		VARCHAR(16))
		
SET @ErrorPosition=130
SET @ErrorMessage='Outpatient Diagnosis  temp table created'

IF @OPADiagnosis=1
   BEGIN

   SELECT @StartDate =GETDATE()

       INSERT INTO  BH_RESEARCH.DBO.RDE_OP_DIAGNOSIS
         SELECT DISTINCT
	     	CONVERT(VARCHAR(20),OP.CDS_OPA_ID)										AS CDS_OPA_ID
			,OP.PERSON_ID                                        AS PERSONID
			,Pat.MRN																AS MRN
		    ,CONVERT(INT,[ICD_Diag_Num])											AS ICD_Diagnosis_Num
		    ,CONVERT(VARCHAR(10),Icd.[ICD_Diag_Cd])									AS ICD_Diagnosis_Cd
		    ,CONVERT(VARCHAR(250),dbo.csvString(ICDDESC.[ICD_Diag_Desc]))           AS ICD_Diag_Desc
		    ,Pat.NHS_Number															AS NHS_Number
		    ,CONVERT(VARCHAR(16),OP.Att_Dt ,120)									AS Activity_date
		    ,CONVERT(VARCHAR(16),[CDS_Activity_Dt] ,120)							AS [CDS_Activity_Dt]
		
FROM [BH_DATAWAREHOUSE].[dbo].[CDS_OPA_ICD_DIAG] Icd with (nolock)
              INNER JOIN  BH_RESEARCH.DBO.TempOPA OP with (nolock)
            ON Icd.CDS_OPA_ID=OP.CDS_OPA_ID
LEFT JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = OP.PERSON_ID
LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_ICD_DIAG] ICDDESC with (nolock)
ON Icd.ICD_Diag_Cd = ICDDESC.[ICD_Diag_Cd]
WHERE PAT.MRN IS NOT NULL
AND CAST(OP.Att_Dt AS DATE)>=@DATE AND ICD.ICD_Diag_Cd IS NOT NULL


SELECT @Row_Count=@@ROWCOUNT

SET @ErrorPosition=140
SET @ErrorMessage='Outpatient diagnosis deatils inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Outpatient Diagnosis', @StartDate, @EndDate,@time,@Row_Count)
  END
----------------------------------------------------------------------------------------
----------------OPCS DETAILS FOR OUTPATIENTS
------------------------------------------------------------------------------------------		
--CDS date				[BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] 			[Att_Dt]     
--procedure date		[BH_DATAWAREHOUSE].[dbo].[CDS_OPA_OPCS_PROC]	[OPCS_Proc_Dt]
--procedure code		[BH_DATAWAREHOUSE].[dbo].[CDS_OPA_OPCS_PROC]	OPCS_Proc_Cd
--procedure description	[BH_DATAWAREHOUSE].[dbo].[LKP_OPCS_49]			[Proc_Desc]
--procedure sequence	[BH_DATAWAREHOUSE].[dbo].[CDS_OPA_OPCS_PROC]	[OPCS_Proc_Num]
	
SET @ErrorPosition=150	
SET @ErrorMessage='Outpatient procedure'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_OPA_OPCS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_OPA_OPCS
	CREATE TABLE  BH_RESEARCH.DBO.RDE_OPA_OPCS(
		CDS_OPA_ID				VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN                    VARCHAR(20)
	    ,OPCS_Proc_Num			INT
	    ,OPCS_Proc_Scheme_Cd	VARCHAR(10)
	    ,OPCS_Proc_Cd			VARCHAR(10)
	    ,Proc_Desc				VARCHAR(250) 
	    ,OPCS_Proc_Dt			VARCHAR(16)
	    ,NHS_Number				VARCHAR(20)
	    ,[CDS_Activity_Dt]		VARCHAR(16))

SET @ErrorPosition=160	
SET @ErrorMessage='Outpatient procedure temp table created'

IF @OPAProcedures=1
  BEGIN

  SELECT @StartDate=GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_OPA_OPCS
        SELECT DISTINCT
		    CONVERT(VARCHAR(20),OP.CDS_OPA_ID)                                                AS CDS_OPA_ID
		    ,OP.PERSON_ID                                        AS PERSONID
			,Pat.MRN																		  AS MRN
		    ,CONVERT(INT,OPCS_Proc_Num)                                                       AS OPCS_Proc_Num
		    ,CONVERT(VARCHAR(10),OPCS_Proc_Scheme_Cd)                                         AS OPCS_Proc_Scheme_Cd
		    ,CONVERT(VARCHAR(10),OPCS_Proc_Cd)                                                AS OPCS_Proc_Cd
		    ,CONVERT(VARCHAR(250),dbo.csvString(OPDesc.Proc_Desc))                            AS Proc_Desc
		    ,COALESCE(CONVERT(VARCHAR(16),OPCS_Proc_Dt,120),CONVERT(VARCHAR(16),Att_Dt,120))  AS OPCS_Proc_Dt
		    ,Pat.NHS_Number                                               					  AS NHS_Number
		    ,CONVERT(VARCHAR(16),OP.[CDS_Activity_Dt],120)                                    AS [CDS_Activity_Dt]
		
FROM [BH_DATAWAREHOUSE].[dbo].[CDS_OPA_OPCS_PROC] OPCS with (nolock)
              INNER JOIN  BH_RESEARCH.DBO.TempOPA OP with (nolock)
            ON OPCS.CDS_OPA_ID=OP.CDS_OPA_ID
LEFT JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = OP.PERSON_ID
LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_OPCS_410] OPDesc with (nolock)
ON OPCS.OPCS_Proc_Cd = OPDesc.Proc_Cd
WHERE PAT.MRN IS NOT NULL
AND CAST(OP.Att_Dt AS DATE)>=@DATE


SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_CDS_OPA ON  BH_RESEARCH.DBO.RDE_OPA_OPCS (CDS_OPA_ID)

SET @ErrorPosition=170
SET @ErrorMessage='Outpatient procedure deatils inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Outpatient Procedures', @StartDate, @EndDate,@time,@Row_Count)
  END
---------------------------------------------------------------------------------------------------
--INPATIENT DETAILS
---------------------------------------------------------------------------------------------------


--admission date	        [BH_DATAWAREHOUSE].[dbo].[CDS_APC]	                   [Start_Dt]
--discharge date	        [BH_DATAWAREHOUSE].[dbo].[CDS_APC]	                   [Disch_Dt]
--speciality/department  	[BH_DATAWAREHOUSE].[dbo].[CDS_APC] [BH_DATAWAREHOUSE].[dbo].[SLAM_APC_HRG_v4]	[Treat_Func_Cd]
--HRG code	                [BH_DATAWAREHOUSE].[dbo].[SLAM_APC_HRG_v4]	           Spell_HRG_Cd
--HRG description	        [BH_DATAWAREHOUSE].[dbo].[LKP_HRG_v4]	               [HRG_Desc]
--attendance type	        [BH_DATAWAREHOUSE].[dbo].[CDS_APC] / [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_PATIENT_CLASS]	[Ptnt_Class_Cd] /[Patient_Class_Desc]

SET @ErrorPosition=180
SET @ErrorMessage='Inpatient Attendance'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_CDS_APC', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_CDS_APC
	CREATE TABLE  BH_RESEARCH.DBO.RDE_CDS_APC (
		CDS_APC_ID				VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN					VARCHAR(20)
		,[Adm_Dt]				VARCHAR(16)
		,[Disch_Dt]				VARCHAR(16)
		,LOS					VARCHAR(500)
		,Priority_Cd			VARCHAR(100)
		,Priority_Desc          VARCHAR(500)
		,Treat_Func_Cd			VARCHAR(20)
		,Spell_HRG_Cd			VARCHAR(20)
		,HRG_Desc				VARCHAR(max)
		,[Patient_Class_Desc]   VARCHAR(max)
		,PatClass_Desc			VARCHAR(100)
		,Admin_Cat_Cd           VARCHAR(100)
		,Admin_Cat_Desc         VARCHAR(max)
		,Admiss_Srce_Cd         VARCHAR(100)
		,Admiss_Source_Desc     VARCHAR(max)
		,Disch_Dest				VARCHAR(100)
		,Disch_Dest_Desc		VARCHAR(max)
		,Ep_Num					VARCHAR(20)
		,Ep_Start_Dt			VARCHAR(16)
		,Ep_End_Dt				VARCHAR(16)
		,NHS_Number				VARCHAR(20)
		,[CDS_Activity_Dt]		VARCHAR(16)
		,ENC_DESC				VARCHAR(1000))

SET @ErrorPosition=190
SET @ErrorMessage='Inpatient Attendance temp table created'

IF @Inpatient=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_CDS_APC
        SELECT DISTINCT
		   CONVERT(VARCHAR(20),APC.CDS_APC_ID)																AS CDS_APC_ID
		   ,LALIAS.PERSON_ID                                        AS PERSONID
		   ,Pat.MRN																							AS MRN
		   ,CONVERT(VARCHAR(16),[Adm_Dt],120)																AS [Adm_Dt]
		   ,CONVERT(VARCHAR(16),APC.[Disch_Dt],120)															AS [Disch_Dt]
		   ,CONVERT(VARCHAR(500),CAST( DATEPART(DAY,  APC.[Disch_Dt] - [Adm_Dt]) AS varchar(50)))     		AS LOS
		   ,CONVERT(VARCHAR(100),WL.Priority_Type_Cd)															AS Priority_Cd
		   ,CONVERT(VARCHAR(500),dbo.csvString(PT.[Priority_Type_Desc]))									AS Priority_Desc
		   ,CONVERT(VARCHAR(20),APC.Treat_Func_Cd)															AS Treat_Func_Cd
		   ,CONVERT(VARCHAR(20),Spell_HRG_Cd)																AS Spell_HRG_Cd
		   ,CONVERT(VARCHAR(max),dbo.csvString(HRG_Desc))																	AS HRG_Desc
		   ,CONVERT(VARCHAR(max),dbo.csvString([Patient_Class_Desc]))			            								AS [Patient_Class_Desc]
		   ,CONVERT(VARCHAR(100),dbo.csvString(SUBSTRING([Patient_Class_Desc],0,CHARINDEX('-',[Patient_Class_Desc],0))))	AS PatClass_Desc
		   ,CONVERT(VARCHAR(100),APC.Admin_Cat_Cd)															AS Admin_Cat_Cd
		   ,CONVERT(VARCHAR(max),dbo.csvString(AC.Admin_Cat_Desc) )															AS Admin_Cat_Desc 
		   ,CONVERT(VARCHAR(100),APC.Admiss_Srce_Cd)														AS Admiss_Srce_Cd  
		   ,CONVERT(VARCHAR(max),dbo.csvString(Admiss_Source_Desc))														AS Admiss_Source_Desc
		   ,CONVERT(VARCHAR(100),APC.Disch_Dest)															AS Disch_Dest
		   ,CONVERT(VARCHAR(max),dbo.csvString(Disch_Dest_Desc))															AS Disch_Dest_Desc
		   ,CONVERT(VARCHAR(100),APC.Ep_Num)															    AS Ep_Num
		   ,CONVERT(VARCHAR(16),APC.Ep_Start_Dt_tm)															AS Ep_Start_Dt
		   ,CONVERT(VARCHAR(16),APC.Ep_End_Dt_tm)															AS Ep_End_Dt
		   ,Pat.NHS_Number																					AS NHS_Number
		   ,CONVERT(VARCHAR(16),APC.[CDS_Activity_Dt] ,120)													AS [CDS_Activity_Dt]
		   ,CONVERT(VARCHAR(1000),dbo.csvString(Descr.CODE_DESC_TXT) )														AS ENC_DESC
		   
FROM [BH_DATAWAREHOUSE].[dbo].[SLAM_APC_HRG_v4] HRG with (nolock)
LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_APC] APC with (nolock)
ON HRG.CDS_APC_Id=APC.CDS_APC_ID
INNER JOIN BH_RESEARCH.DBO.TempAPC LALIAS with (nolock)
ON LALIAS.CDS_APC_ID=APC.CDS_APC_ID
LEFT JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = LALIAS.PERSON_ID
LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[LKP_HRG_v4] HRGDesc with (nolock)
ON HRG.Spell_HRG_Cd = HRGDesc.[HRG_Cd] 
LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_PATIENT_CLASS] PC with (nolock)
ON HRG.[Ptnt_Class]=PC.[Patient_Class_Cd]
LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[LKP_CDS_ADMIN_CAT] AC
ON APC.Admin_Cat_Cd=AC.Admin_Cat_Cd
LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[LKP_CDS_ADMISS_SOURCE] ASrce
ON APC.Admiss_Srce_Cd=ASrce.Admiss_Source_Cd
LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.[LKP_CDS_DISCH_DEST] DS
ON APC.[Disch_Dest]=DS.DISCH_DEST_CD
LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.CDS_EAL_TAIL EalTl  
ON LALIAS.PERSON_ID=EalTl.Encounter_ID AND EalTl.Record_Type='060'
LEFT OUTER JOIN [BH_DATAWAREHOUSE].DBO.CDS_EAL_ENTRY WL
ON WL.CDS_EAL_Id = EalTl.CDS_EAL_ID
LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_PRIORITY_TYPE] PT
ON PT.[Priority_Type_Cd]=WL.[Priority_Type_Cd]
LEFT OUTER JOIN  BH_RESEARCH.DBO.RDE_Encounter Enc
ON LALIAS.PERSON_ID=Enc.ENCNTR_ID
LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Descr  with (nolock)
ON Enc.[ENC_TYPE_CD] = Descr.CODE_VALUE_CD
WHERE PAT.MRN IS NOT NULL
AND CAST(APC.Disch_Dt AS DATE)>=@DATE
ORDER BY [Adm_Dt]





SELECT @Row_Count=@@ROWCOUNT			
			--select * from  BH_RESEARCH.DBO.RDE_CDS_OPA

CREATE INDEX indx_CDS_APC ON  BH_RESEARCH.DBO.RDE_CDS_APC (CDS_APC_ID)

SET @ErrorPosition=200
SET @ErrorMessage='Inpatient details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Inpatient Attendance', @StartDate, @EndDate,@time,@Row_Count)
  END
------------------------------------------------------------------------------------------------------------
--OUTPATIENT DETAILS
------------------------------------------------------------------------------------------------------------
--appointment date	             [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] 					[CDS_Activity_Dt]
--speciality/department	         [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] 					[Treat_Func_Cd]
--HRG code	                     [BH_DATAWAREHOUSE].[dbo].[SLAM_OP_HRG]					[NAC_HRG_Cd]
--HRG description	             [BH_DATAWAREHOUSE].[dbo].[LKP_HRG_v4]					[HRG_Desc]
--outptient type	             [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] 					[Record_Type]
--attended?	                     [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] 					[Att_Or_DNA_Cd]
--outcome	                     [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL]					[Outcome_Cd] 
--                               [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_ATTENDANCE_OUTCOME]  [Attendance_Outcome_Desc]

Set @ErrorPosition=210
Set @ErrorMessage='Outpatient Attendance'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_CDS_OPA', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_CDS_OPA
	CREATE TABLE  BH_RESEARCH.DBO.RDE_CDS_OPA (
		CDS_OPA_ID					VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN						VARCHAR(20)
		,[Att_Dt]					VARCHAR(16)
		,Treat_Func_Cd				VARCHAR(10)
		,[HRG_Cd]					VARCHAR(10)
		,HRG_Desc					VARCHAR(250)
		,Att_Type					VARCHAR(200)
		,Attended_Desc				VARCHAR(100)
		,Attendance_Outcome_Desc	VARCHAR(300)
		,NHS_Number					VARCHAR(20)
		,[CDS_Activity_Dt]			VARCHAR(16)
		,Atten_TypeDesc				VARCHAR(100)
		,ENC_DESC					VARCHAR(100) )

Set @ErrorPosition=220
Set @ErrorMessage='Outpatient Attendance temp table created'

IF @Outpatient=1
  BEGIN

  SELECT @StartDate =GETDATE ()
        INSERT INTO  BH_RESEARCH.DBO.RDE_CDS_OPA
          SELECT DISTINCT 
	     	  CONVERT(VARCHAR(20),OPALL.CDS_OPA_ID)                             AS CDS_OPA_ID
			 ,LALIAS.PERSON_ID                                        AS PERSONID
			 ,Pat.MRN															AS MRN
		     ,CONVERT(VARCHAR(16),OPALL.[Att_Dt],120)							AS [Att_Dt]
		     ,CONVERT(VARCHAR(10),OPALL.Treat_Func_Cd)							AS Treat_Func_Cd
	         ,CONVERT(VARCHAR(10),[NAC_HRG_Cd])									AS [HRG_Cd]
			 ,CONVERT(VARCHAR(250),dbo.csvString(HRG_Desc))									AS HRG_Desc--TO FIND
		     ,CONVERT(VARCHAR(200),dbo.csvString(FA.First_Attend_Desc))						AS Att_Type
		     ,CONVERT(VARCHAR(100),dbo.csvString(AD.Attended_Desc))							AS Attended_Desc
		     ,CONVERT(VARCHAR(300),dbo.csvString(AO.Attendance_Outcome_Desc))					AS Attendance_Outcome_Desc
		     ,Pat.NHS_Number													AS NHS_NUMBER
		     ,CONVERT(VARCHAR(16),LALIAS.[CDS_Activity_Dt],120)						AS [CDS_Activity_Dt]
		     ,CONVERT(VARCHAR(100),dbo.csvString(AttType.[CODE_DESC_TXT]))						AS Atten_TypeDesc
		     ,CONVERT(VARCHAR(100),dbo.csvString(Descr.CODE_DESC_TXT ))						AS ENC_DESC
			 FROM [BH_DATAWAREHOUSE].[dbo].[CDS_OP_ALL] OPALL with (nolock)
			 INNER JOIN BH_RESEARCH.DBO.TempOPA LALIAS with (nolock)
			ON LALIAS.CDS_OPA_ID=OPALL.CDS_OPA_ID
			LEFT JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics Pat ON Pat.PERSON_ID = LALIAS.PERSON_ID
		    INNER JOIN [BH_DATAWAREHOUSE].[dbo].[SLAM_OP_HRG] HRG with (nolock)
		        ON HRG.MRN = OPALL.MRN AND HRG.CDS_OPA_Id=OPALL.CDS_OPA_ID 
		    LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].PI_CDE_OP_ATTENDANCE CDE  with (nolock)
                ON OPALL.[Attendance_Id]=CDE.ATTENDANCE_IDENT
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[LKP_HRG_v4] HRGDesc with (nolock)
		        ON HRG.[NAC_HRG_Cd] = HRGDesc.[HRG_Cd]
		    LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_FIRST_ATTEND] FA with (nolock)
	            ON OPALL.First_Attend_Cd=fa.First_Attend_Cd
		    LEFT OUTER JOIN [BH_DATAWAREHOUSE].dbo.[LKP_CDS_ATTENDED] AD with (nolock)
		        ON OPALL.Att_Or_DNA_Cd=AD.Attended_Cd
		    LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_ATTENDANCE_OUTCOME] AO with (nolock)
		        ON OPALL.Outcome_Cd=AO.Attendance_Outcome_Cd
		    LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] AttType with (nolock)
                ON CDE.[APPT_TYPE_CD] = AttType.[CODE_VALUE_CD]
			LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].CDS_OP_ALL_TAIL OPATail with (nolock)
                ON OPATail.CDS_OPA_ID=OPALL.CDS_OPA_ID AND OPALL.CDS_Activity_Dt=CAST (OPATail.Activity_Dt_Tm AS DATE)
			LEFT OUTER JOIN  BH_RESEARCH.DBO.RDE_Encounter Enc
                ON OPATail.Encounter_ID=Enc.ENCNTR_ID
            LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Descr  with (nolock)
                ON Enc.[ENC_TYPE_CD] = Descr.CODE_VALUE_CD
			WHERE CAST(OPALL.Att_Dt AS DATE)>=@date

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_CDS_OPA_ID ON  BH_RESEARCH.DBO.RDE_CDS_OPA (CDS_OPA_ID)

Set @ErrorPosition=220
Set @ErrorMessage='Outpatient Attendance details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Outpatient Attendance',@StartDate, @EndDate,@time,@Row_Count)
  END
  --select * from  BH_RESEARCH.DBO.RDE_CDS_OPA
---------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
----PATHOLOGY
------------------------------------------------------------------------------------------------------
--request date	           	PI_CDE_ORDER	[ORDER_DT_TM]        [REQUESTED_START_DT_TM]
--report date	         	PI_CDE_CLINICAL EVENT	[VALID_FROM_DT_TM]/ [EVENT_PERFORMED_DT_TM]
--test code	            	PI CDE_ORDER	[ORDER_KEY]/[ORDER_ID]
--test description	    	PI CDE_ORDER	[ORDER_MNEM_TXT]
--result 	            	PI_CDE_CLINICAL EVENT	EVENT_RESULT_TXT, EVENT_RESULT_NBR
--result unit	         	PI_CDE_CLINICAL EVENT	[EVENT_RESULT_UNITS_CD]
--result upper limit	 	PI_CDE_CLINICAL EVENT	[NORMAL_VALUE_HIGH_TXT]
--result lower limit		PI_CDE_CLINICAL EVENT	[NORMAL_VALUE_LOW_TXT]
--result finding	    	PI_CDE_CLINICAL EVENT	[EVENT_RESULT_TXT]        [EVENT_RESULT_NBR]

Set @ErrorPosition=230
Set @ErrorMessage='Pathology details'
 
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Pathology', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Pathology

	CREATE TABLE  BH_RESEARCH.DBO.RDE_Pathology (
	     ENCNTR_ID			VARCHAR(20)
		,PERSONID				VARCHAR(40)
		,MRN                    VARCHAR(20)
		,NHS_Number				VARCHAR(40)
		,[RequestDate]			VARCHAR(16)
		,[TestCode]				VARCHAR(50)
		,TestName				VARCHAR(200)
		,TestDesc				VARCHAR(350)
		,Result_nbr				VARCHAR(30)
		,ResultTxt				VARCHAR(350)
		,ResultNumeric			BIT
		,[ResultUnit]			VARCHAR(20)
		,[ResUpper]				VARCHAR(20)
		,[ResLower]				VARCHAR(20)
		,Resultfinding			VARCHAR(50)
		,[ReportDate]			VARCHAR(16)
		,Report					VARCHAR(MAX)
		,OrderStatus			VARCHAR(50)
		,ResStatus				VARCHAR(50)
		,SnomedCode				VARCHAR(100)
		,EventID                VARCHAR(50)
		,LabNo                  VARCHAR(50))

Set @ErrorPosition=240
Set @ErrorMessage='Pathology Temp table created'

IF @Pathology=1
  BEGIN
   
   SELECT @StartDate =GETDATE()

	INSERT INTO  BH_RESEARCH.DBO.RDE_Pathology
       SELECT DISTINCT 
	        
            Enc.ENCNTR_ID
		   ,CONVERT(VARCHAR(40),Enc.PERSON_ID)                         AS PERSONID
		   ,Enc.MRN
		   ,Enc.NHS_Number												AS NHS_Number
		   ,CONVERT(VARCHAR(16),ORD.[REQUESTED_START_DT_TM] ,120)      AS [RequestDate]
           ,CONVERT(VARCHAR(50),dbo.csvString(ORD.[ORDER_MNEM_TXT]))                  AS [TestCode]
           ,CONVERT(VARCHAR(200),dbo.csvString(TESTnm.CODE_DESC_TXT))                 AS [TestName]                   --PARENT EVENT DESC WITH MAIN TEXT 
           ,CONVERT(VARCHAR(350),dbo.csvString(EVNTdes.CODE_DESC_TXT))                AS TestDesc                --CHILD EVENT(DETAILS)
           ,CONVERT(VARCHAR(30),EVE.EVENT_RESULT_NBR )                 AS Result_nbr
           ,CONVERT(VARCHAR(350),dbo.csvString(EVE.EVENT_RESULT_TXT))                 AS ResultTxt
		   ,CASE WHEN ISNUMERIC(EVE.EVENT_RESULT_TXT) <> 1 THEN 0 ELSE 1 END			AS ResultNumeric		   
           ,CONVERT(VARCHAR(20),dbo.csvString(Evres.CODE_DESC_TXT))                   AS [ResultUnit]
           ,CONVERT(VARCHAR(20),dbo.csvString(EVE.[NORMAL_VALUE_HIGH_TXT]))           AS [ResUpper]
           ,CONVERT(VARCHAR(20),dbo.csvString(EVE.NORMAL_VALUE_LOW_TXT))              AS [ResLower]
           ,CONVERT(VARCHAR(50),dbo.csvString(RESFind.CODE_DESC_TXT))                 AS Resultfinding
           ,CONVERT(VARCHAR(16),EVE.EVENT_START_DT_TM ,120)            AS [ReportDate]                 --BEST OPTION 
		   ,CONVERT(VARCHAR(MAX),dbo.csvString(d.BLOB_CONTENTS))                      AS Report           
           ,CONVERT(VARCHAR(50),dbo.csvString(ORDStat.CODE_DESC_TXT))                 AS OrderStatus
	       ,CONVERT(VARCHAR(50),dbo.csvString(RESstat.CODE_DESC_TXT) )                AS ResStatus
		   ,CONVERT(VARCHAR(100),ORD.CONCEPT_CKI_IDENT)				   AS SnomedCode
		   ,CONVERT(VARCHAR(150),EVE.EVENT_ID)						   AS EventID
		   ,CONVERT(VARCHAR(50), LEFT(EVE.REFERENCE_NBR, 11))		   AS LabNo
		   FROM BH_RESEARCH.DBO.TempCE  EVE  with (nolock)
		   LEFT JOIN BH_RESEARCH.DBO.RDE_Encounter ENC
		   ON EVE.ENCNTR_ID=ENC.ENCNTR_ID 
		   LEFT JOIN  BH_RESEARCH.DBO.TempOrder ORD  with (nolock)
		   ON ENC.ENCNTR_ID=ORD.ENCNTR_ID AND ORD.ORDER_ID=EVE.ORDER_ID
		   AND ord.LAST_ORDER_STATUS_CD=2543 AND ord.ORDERABLE_TYPE_CD=2513

	        LEFT OUTER JOIN BH_RESEARCH.DBO.TempCE  EVNT2  with (nolock)  
	            ON EVE.PARENT_EVENT_ID=EVNT2.EVENT_ID
            LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF Evres with (nolock)
	            ON EVE.EVENT_RESULT_UNITS_CD = Evres.CODE_VALUE_CD 
	        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF EVNTdes with (nolock)
	            ON eve.EVENT_CD=EVNTdes.CODE_VALUE_CD
	        LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF ACTtype with (nolock)
	            ON ORD.ACTIVITY_TYPE_CD = ACTtype.CODE_VALUE_CD 
	        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF RESFind with (nolock)
	            ON EVE.NORMALCY_CD=RESFind.CODE_VALUE_CD
	        LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. PI_LKP_CDE_CODE_VALUE_REF TESTnm with (nolock)
	 	        ON EVNT2.EVENT_CD = TESTnm.CODE_VALUE_CD	
	        LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF ORDStat with (nolock)
	            ON ORD.LAST_ORDER_STATUS_CD = ORDStat.CODE_VALUE_CD  
	        LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].PI_LKP_CDE_CODE_VALUE_REF RESstat with (nolock)
	            ON eve.EVENT_RESULT_STATUS_CD = RESstat.CODE_VALUE_CD 
			LEFT OUTER JOIN  BH_RESEARCH.DBO.TempBLOB D with (nolock)
				ON EVE.EVENT_ID=d.EVENT_ID or EVNT2.EVENT_ID=d.EVENT_ID
			WHERE EVE.CONTRIBUTOR_SYSTEM_CD = '6378204' and EVE.CONTRIBUTOR_SYSTEM_CD is not null 
--	        ORDER BY [RequestDate] 


SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_Patho ON  BH_RESEARCH.DBO.RDE_Pathology (NHS_Number)

SET @ErrorPosition=250
SET @ErrorMessage='Pathology details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Pathology', @StartDate, @EndDate,@time,@Row_Count)


--------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------
---New Pathology
-------------------------------------------------------------------------
--Update the research tables with the latest values.

SET @ErrorPosition=255
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_RAW_PATHOLOGY', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_RAW_PATHOLOGY
SELECT
    Demo.PERSON_ID,
	Demo.NHS_Number,
	Demo.MRN,
    PRES.LabNo,
	PRES.TLCCode,
	PMOR.CSpecTypeCode AS Specimen,
	PMOR.SnomedCTCode AS TLCSnomed,
	dbo.csvString(PMOR.TLCDesc_Full) AS TLCDesc,
    PRES.TFCCode,
    PRES.LegTFCCode AS Subcode,
    PRES.WkgCode,
	CASE WHEN(PRES.NotProcessed = 1) THEN 0 ELSE 1 END AS Processed,
    dbo.csvString(PRES.Result1stLine) AS Result,
    CASE WHEN PRES.Result1stLine IS NOT NULL AND PRES.Result1stLine != '.' AND ISNUMERIC(LEFT(PRES.Result1stLine, 100)) = 1 THEN 1 ELSE 0 END AS ResultNumeric,
    PRES.ResultIDNo,
    PMRT.SectionCode,
    dbo.csvString(PMRT.TFCDesc_Full) AS TFCDesc,
    PSL.RequestDT,
    PSL.SampleDT,
    PSL.ReportDate,
    PSL.Fasting,
    PSL.Pregnant,
    PSL.RefClinCode,
    PSL.RefSourceCode,
    dbo.csvString(PSL.ClinicalDetails) AS ClinicalDetails
    INTO [BH_RESEARCH].[dbo].[RDE_RAW_PATHOLOGY]
FROM [BH_RESEARCH].[dbo].[PATH_Patient_ResultableLevel] PRES WITH (NOLOCK)
LEFT OUTER JOIN [BH_RESEARCH].[dbo].[PATH_Master_Resultables] PMRT WITH (NOLOCK)
    ON PRES.TFCCode = PMRT.TFCCode
LEFT OUTER JOIN [BH_RESEARCH].[dbo].[PATH_Master_ORDERABLES] PMOR WITH (NOLOCK)
    ON PRES.TLCCode = PMOR.TLCCode
LEFT OUTER JOIN [BH_RESEARCH].[dbo].[PATH_Patient_SampleLevel] PSL WITH (NOLOCK)
    ON PRES.LabNo = PSL.LabNo
LEFT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] Demo WITH (NOLOCK)
ON PSL.PERSON_ID = Demo.PERSON_ID
WHERE Demo.PERSON_ID IS NOT NULL
ORDER BY PRES.LabNo ASC, PRES.TFCCode ASC, PRES.ResultIDNo ASC;


SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_Patho ON  BH_RESEARCH.DBO.RDE_RAW_Pathology (NHS_Number)

SET @ErrorPosition=251
SET @ErrorMessage='Raw athology details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Raw Pathology', @StartDate, @EndDate,@time,@Row_Count)
  END


--------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------
---ARIA Pharmacy data
-------------------------------------------------------------------------
Set @ErrorPosition=260
Set @ErrorMessage='Pharmacy ARIA'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_ARIAPharmacy', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_ARIAPharmacy

	CREATE TABLE  BH_RESEARCH.DBO.RDE_ARIAPharmacy (
        NHS_Number				VARCHAR(10)
		,MRN                    VARCHAR(30)
	    ,AdmnStartDate			VARCHAR(16)
		,TreatPlan				VARCHAR(250)
		,ProductDesc			VARCHAR(250)
	    ,DosageForm				VARCHAR(100)
		,RxDose					INT
		,RxTotal				INT
		,SetDateTPInit			VARCHAR(16)
		,DoseLevel				INT
		,AdmnDosageUnit			INT
		,AdmnRoute				INT
	    ,Pharmacist_Approved	VARCHAR(16)
	    )

SET @ErrorPosition=270
SET @ErrorMessage='ARIA temp table created'


--table [BH_DATAWAREHOUSE].[dbo].[ARIA_AGT_RX] does not exist in D02
IF @PharmacyAria=1
  BEGIN

  SELECT @StartDate =GETDATE ()
     INSERT INTO  BH_RESEARCH.DBO.RDE_ARIAPharmacy
         SELECT 

              D.NHS_Number									 			AS NHS_Number
			  ,D.MRN
			  ,CONVERT(VARCHAR(16),[ARX].[ADMN_START_DATE] ,120)			 AS AdmnStartDate
			  ,dbo.csvString(ARX.tp_name )											 AS TreatPlan
              ,dbo.csvString(ARX.AGT_NAME )											 AS ProductDesc
              ,CONVERT(VARCHAR(100),dbo.csvString(arx.dosage_form))						 AS DosageForm
			  ,CONVERT(INT,ARX.rx_dose)										 AS RxDose
			  ,CONVERT(INT, ARX.rx_total )									 AS RxTotal
			  ,CONVERT(VARCHAR(16),ARX.set_date_tp_init,120)				 AS SetDateTPInit
			  ,CONVERT(INT,ARX.dose_level)									 AS DoseLevel
			  ,CONVERT(INT,ARX.admn_dosage_unit)							 AS AdmnDosageUnit
			  ,CONVERT(INT,ARX.admn_route)									 AS AdmnRoute
              ,CONVERT(VARCHAR(16),[pharm_appr_tstamp],120)					 AS Pharmacist_Approved
			 

        FROM  [BH_DATAWAREHOUSE].[dbo].[ARIA_PT_INST_KEY] Ptkey  with (nolock)
            INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics D  
		         ON (D.NHS_Number=REPLACE(ptkey.pt_key_value,' ',''))--OR  (ptkey.pt_key_value=D.MRN))
            INNER JOIN [BH_DATAWAREHOUSE].[dbo].[ARIA_AGT_RX] Arx  with (nolock)
                 ON Arx.pt_id=Ptkey.pt_id 
	        INNER JOIN [BH_DATAWAREHOUSE].[dbo].[ARIA_RX] Rx  with (nolock)
	             ON Arx.pt_id=Rx.pt_id AND Arx.rx_id=Rx.rx_id
            WHERE pt_key_cd = 24 --OR pt_key_cd = 2--and Arx.valid_entry_ind='Y' AND Rx.valid_entry_ind='Y'  --24 NHSNumber and check the entry is valid
	          AND CAST([date_time_sent] AS DATE)>=@DATE
			--ORDER BY AdmnStartDate

SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_Aria ON  BH_RESEARCH.DBO.RDE_ARIAPharmacy (NHS_Number)

SET @ErrorPosition=280
SET @ErrorMessage='Pharmacy details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'ARIA', @StartDate, @EndDate,@time,@Row_Count)





--------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------
---iQemo update Pharmacy data
-------------------------------------------------------------------------

Set @ErrorPosition=262
Set @ErrorMessage='Pharmacy iQemo'

IF OBJECT_ID(N'BH_RESEARCH.dbo.RDE_iQEMO', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.dbo.RDE_iQEMO
SELECT DEM.PERSON_ID, PT.[PrimaryIdentifier] AS MRN
      ,PT.[NHSNumber] AS NHS_Number, TC.TreatmentCycleID, TC.PrescribedDate, TemplateName, RG.Name, RG.DefaultCycles, RG.ChemoRadiation, RG.OPCSProcurementCode, RG.OPCSDeliveryCode, RG.SactName, RG.Indication
	  INTO BH_RESEARCH.dbo.RDE_iQEMO
	  FROM [IQEMO].[iQemo].[dbo].[TreatmentCycle] TC
LEFT JOIN [IQEMO].[iQemo].[dbo].[ChemotherapyCourse] CC ON (CC.ChemoTherapyCourseID = TC.ChemoTherapyCourseID)
LEFT JOIN [IQEMO].[iQemo].[dbo].[Regimen] RG ON (CC.RegimenID = RG.RegimenID)
LEFT JOIN [IQEMO].[iQemo].[dbo].[Patient] PT ON TC.PatientID = PT.PatientID
LEFT JOIN [BH_RESEARCH].[dbo].RDE_Patient_Demographics DEM  ON (PT.[PrimaryIdentifier] = DEM.MRN)
WHERE TC.PrescribedDate IS NOT NULL
AND PERSON_ID IS NOT NULL


SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_iqemo ON  BH_RESEARCH.dbo.RDE_iQEMO (NHS_Number)

SET @ErrorPosition=280
SET @ErrorMessage='Pharmacy details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'iQemo', @StartDate, @EndDate,@time,@Row_Count)

  END




--------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
------------------------POWER FORMS
-------------------------------------------------------------------------------------------------------------
Set @ErrorPosition=290
Set @ErrorMessage='Power Forms'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Powerforms', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Powerforms
	
	CREATE TABLE  BH_RESEARCH.DBO.RDE_Powerforms 
        (NHS_Number			VARCHAR(10)
		,MRN				VARCHAR(20)
		,ENCNTR_ID			VARCHAR(20)
		,[PerformDate]		VARCHAR(16)
		,DOC_RESPONSE_KEY	VARCHAR(50)
		,[Form]				VARCHAR(300)
		,[FormID]			BIGINT
		,[Section]			VARCHAR(350)
		,[SectionID]		BIGINT
		,[Element]			VARCHAR(300)
		,[ElementID]		BIGINT
		,[Component]		VARCHAR(300)
		,[ComponentDesc]	VARCHAR(300)
		,[ComponentID]		BIGINT
		,[Response]			VARCHAR(350)
		,[ResponseNumeric]	BIT
        ,[Status]			VARCHAR(100))


Set @ErrorPosition=300
Set @ErrorMessage='Power Forms temp table created'

IF @PowerForms=1
  BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_Powerforms
         SELECT  
    
	        ENC.NHS_Number															AS NHS_Number
			,ENC.MRN
	        ,Enc.ENCNTR_ID
	        ,CONVERT(VARCHAR(16),[PERFORMED_DT_TM],120)							AS [PerformDate]
			,DOC.DOC_RESPONSE_KEY
	        ,dbo.csvString(Dref.FORM_DESC_TXT)													AS [Form]
	        ,DOC.FORM_EVENT_ID															AS [FormID]
	        ,dbo.csvString(Dref.SECTION_DESC_TXT)											    AS [Section]
			,DOC.SECTION_EVENT_ID														AS [SectionID]
	        ,dbo.csvString(Dref.ELEMENT_LABEL_TXT)												AS [Element]
			,DOC.ELEMENT_EVENT_ID														AS [ElementID]
			,DREF.GRID_NAME_TXT															AS [Component]
	        ,dbo.csvString(Dref.GRID_COLUMN_DESC_TXT)											AS [ComponentDesc]
	        ,DOC.GRID_EVENT_ID															AS [ComponentID]
	        ,dbo.csvString([RESPONSE_VALUE_TXT])												AS [Response]
			,CASE WHEN ISNUMERIC([RESPONSE_VALUE_TXT]) <> 1 THEN 0 ELSE 1 END					AS [ResponseNumeric]
	        ,dbo.csvString(Cref.CODE_DESC_TXT)													AS [Status]
	  	 
     FROM [BH_DATAWAREHOUSE].[dbo].[PI_CDE_DOC_RESPONSE]DOC  with (nolock)
             INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter Enc
                  ON Enc.ENCNTR_ID=doc.ENCNTR_ID
             LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo]. PI_LKP_CDE_DOC_REF Dref with (nolock)
		          ON DOC.DOC_INPUT_ID = Dref.DOC_INPUT_KEY
		     LEFT OUTER JOIN BH_DATAWAREHOUSE.DBO.PI_LKP_CDE_CODE_VALUE_REF Cref with (nolock)
		          ON DOC.FORM_STATUS_CD=Cref.CODE_VALUE_CD
				  ORDER BY [PerformDate]

SELECT @Row_Count=@@ROWCOUNT

CREATE INDEX indx_PF ON  BH_RESEARCH.DBO.RDE_Powerforms (NHS_Number)	
 
SET @ErrorPosition=310
SET @ErrorMessage='PowerForms details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PowerForms', @StartDate, @EndDate,@time,@Row_Count)
  END


  -------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
-------------------RADIOLOGY
--------------------------------------------------------------------------------------------------------
SET @ErrorPosition=320
SET @ErrorMessage='Radiology'

--IF OBJECT_ID('Tbl_NHSI_Exam_Mapping') IS NOT NULL DROP TABLE Tbl_NHSI_Exam_Mapping

--SELECT * INTO Tbl_NHSI_Exam_Mapping  FROM [BH_IMAGING].[CSS_BI].[Tbl_NHSI_Exam_Mapping]

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Radiology', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Radiology
    
	CREATE TABLE  BH_RESEARCH.DBO.RDE_Radiology (
	    --ORDER_ID				VARCHAR(30)
		PERSON_ID				VARCHAR(30)
		,MRN                    VARCHAR(20)
		,ENCNTR_ID				VARCHAR(30)
		,NHS_Number				VARCHAR(10)
		,[Acitvity type]		VARCHAR(450)
		,TFCode					VARCHAR(40)
		,TFCdesc				VARCHAR(450)
		,ExamName				VARCHAR(550)
		,EventName				VARCHAR(500)
		,EVENT_TAG_TXT			VARCHAR(500)
		,ResultNumeric			BIT
		,ExamStart				VARCHAR(16)
		,ExamEnd				VARCHAR(16)
		--,EVENT_TITLE_TXT		VARCHAR(500)
		,ReportText				VARCHAR(MAX)
		,LastOrderStatus		VARCHAR(30)
		,RecordStatus			VARCHAR(100)
		--,EClassDesc				VARCHAR(100)
		,ResultStatus			VARCHAR(100)
		--,EVENT_PERFORMED		VARCHAR(16)
		--,EVENT_VERIFIED			VARCHAR(16)
		,[ExaminationTypecode]  VARCHAR(100)
		,Modality				VARCHAR(100)
		,SubModality			VARCHAR(100)
		,[ExaminationTypeName]	VARCHAR(350)
		,EventID				VARCHAR(35))

SET @ErrorPosition=330
SET @ErrorMessage='Radiology temp table created'

IF @Radiology=1
  BEGIN

  SELECT @StartDate =GETDATE()
      INSERT INTO  BH_RESEARCH.DBO.RDE_Radiology
	     SELECT 
	         --ORD.ORDER_ID
	          EVE.PERSON_ID															AS PERSON_ID
			 ,ENC.MRN
	         ,EVE.ENCNTR_ID															AS ENCNTR_ID
	         ,ENC.NHS_Number															AS NHS_Number
	         ,ENC.ENC_TYPE															AS [Acitvity type]
	         ,ENC.TREATMENT_FUNCTION_CD												AS TFCode
	         ,dbo.csvString(ENC.TFC_DESC)											AS TFCdesc
	         ,dbo.csvString(ORD.ORDER_MNEM_TXT)										AS ExamName
	         ,dbo.csvString(CD.CODE_DESC_TXT)										AS EventName
	         ,dbo.csvString(EVE.EVENT_TAG_TXT)
			 ,CASE WHEN ISNUMERIC(EVE.EVENT_RESULT_TXT) <> 1 THEN 0 ELSE 1 END		AS ResultNumeric
	         --,EVE.EVENT_TITLE_TXT
	         ,CONVERT(VARCHAR(16),EVE.EVENT_START_DT_TM,120)						AS ExamStart
	         ,CONVERT(VARCHAR(16),EVE.EVENT_END_DT_TM,120)							AS ExamEnd
			 ,dbo.csvString(B.BLOB_CONTENTS)										AS ReportText
			 ,dbo.csvString(LO.CODE_DESC_TXT)										AS LastOrderStatus
			 ,dbo.csvString(R.CODE_DESC_TXT)										AS RecordStatus
	         --,ECLASS.CODE_DESC_TXT													AS EClassDesc
	         ,dbo.csvString(ER.CODE_DESC_TXT)										AS ResultStatus
	         --,CONVERT(VARCHAR(16),EVE.EVENT_PERFORMED_DT_TM,120)					AS EVENT_PERFORMED
	         --,CONVERT(VARCHAR(16),EVE.EVENT_VERIFIED_DT_TM,120)						AS EVENT_VERIFIED
	         ,M.[ExaminationTypecode]
	         ,dbo.csvString(M.[EX_Modality])										AS Modality
	         ,dbo.csvString(M.[EX_Sub_Modality])									AS SubModality
	         ,dbo.csvString(M.[ExaminationTypeName])
			 ,EVE.EVENT_ID                                                          AS EventID


			FROM BH_RESEARCH.DBO.TempCE  EVE  with (nolock)
		   LEFT JOIN BH_RESEARCH.DBO.RDE_Encounter ENC
		   ON EVE.ENCNTR_ID=ENC.ENCNTR_ID 
		   LEFT JOIN  BH_RESEARCH.DBO.TempOrder ORD  with (nolock)
		   ON ENC.ENCNTR_ID=ORD.ENCNTR_ID AND ORD.ORDER_ID=EVE.ORDER_ID
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] R with (nolock)
	              ON EVE.RECORD_STATUS_CD=R.CODE_VALUE_CD
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] EC with (nolock)
	              ON EVE.ENTRY_MODE_CD=EC.CODE_VALUE_CD
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] ER with (nolock)
	              ON EVE.EVENT_RESULT_STATUS_CD=ER.CODE_VALUE_CD
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] ECLASS with (nolock)
	              ON EVE.EVENT_CLASS_CD=ECLASS.CODE_VALUE_CD
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] CD with (nolock)
	              ON EVE.EVENT_CD=CD.CODE_VALUE_CD
	         LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] LO with (nolock)
	              ON ORD.LAST_ORDER_STATUS_CD=LO.CODE_VALUE_CD
	         LEFT OUTER JOIN BH_RESEARCH.DBO.TempBLOB B with (nolock)
	              ON EVE.EVENT_ID=B.EVENT_ID
             LEFT OUTER JOIN  [BH_RESEARCH].dbo.[Tbl_NHSI_Exam_Mapping] M with  (nolock)--EXAM CODE, MODALITY, SUB-MODALITY LOOK UP TABLE
	              ON EVE.EVENT_TITLE_TXT=M.[ExaminationTypeName] OR EVE.EVENT_TAG_TXT=M.[ExaminationTypeName]
		WHERE EVE.CONTRIBUTOR_SYSTEM_CD = '6141416' and EVE.CONTRIBUTOR_SYSTEM_CD is not null 
		 ORDER BY EVE.EVENT_START_DT_TM

SELECT @Row_Count=@@ROWCOUNT
		  
CREATE INDEX indx_Rdio ON  BH_RESEARCH.DBO.RDE_Radiology (NHS_Number)	
	
SET @ErrorPosition=320
SET @ErrorMessage='Radiology details inserted into Temptable'

SELECT	@EndDate = GETDATE();
SELECT @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Radiology', @StartDate, @EndDate,@time,@Row_Count)
  END
--SELECT  * FROM  BH_RESEARCH.DBO.RDE_Radiology
--------------------------------------------------------------------------------------------------------
--FAMILY HISTORY
--------------------------------------------------------------------------------------------------------
Set @ErrorPosition=330
Set @ErrorMessage='Family history'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_FamilyHistory', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_FamilyHistory

   CREATE TABLE  BH_RESEARCH.DBO.RDE_FamilyHistory (
       PERSON_ID			VARCHAR(14)
	   ,MRN                 VARCHAR(20)
	   ,NHS_Number			VARCHAR(14)
	   --,RELATED_PERSON_ID	VARCHAR(14)
	   ,RELATION_CD			VARCHAR(14)
	   ,RelationDesc		VARCHAR(100)
	   ,RELATION_TYPE		VARCHAR(14)
	   ,RelationType		VARCHAR(100)
	   ,ACTIVITY_NOMEN		VARCHAR(14)
	   ,NomenDesc			VARCHAR(100)
	   ,NomenVal			VARCHAR(100)
	   ,VOCABULARY_CD		VARCHAR(20)
	   ,VocabDesc			VARCHAR(100)
	   ,[TYPE]				VARCHAR(100)
	   ,BegEffectDate		VARCHAR(16)
	   ,EndEffectDate		VARCHAR(16)
	   ,FHX_VALUE_FLG       VARCHAR(10))

Set @ErrorPosition=340
Set @ErrorMessage='Family history temp table created'
 
IF @FamilyHistory=1
   BEGIN

   SELECT @StartDate =GETDATE()

    INSERT INTO  BH_RESEARCH.DBO.RDE_FamilyHistory
          SELECT 
             CONVERT(VARCHAR(14),F.[PERSON_ID])                              AS PERSON_ID
			 ,E.MRN
			 ,CONVERT(VARCHAR(14),E.NHS_Number)                               AS NHS_Number
             --,CONVERT(VARCHAR(14),F.[RELATED_PERSON_ID])                     AS RELATED_PERSON_ID
   	         ,CONVERT(VARCHAR(14),REL.RELATION_CD)                           AS RELATION_CD
			 ,CONVERT(VARCHAR(100),dbo.csvString(REF.CODE_DESC_TXT))         AS RelationDesc
			 ,CONVERT(VARCHAR(14),REL.RELATION_TYPE_CD)                      AS RELATION_TYPE
			 ,CONVERT(VARCHAR(100),dbo.csvString(RELTYPE.CODE_DESC_TXT))     AS RelationType
             ,CONVERT(VARCHAR(14),F.[ACTIVITY_NOMEN])                        AS ACTIVITY_NOMEN
             ,CONVERT(VARCHAR(100),dbo.csvString(R.DESCRIPTION_TXT))         AS NomenDesc
	         ,CONVERT(VARCHAR(100),dbo.csvString(R.VALUE_TXT))               AS NomenVal
	         ,CONVERT(VARCHAR(20),R.VOCABULARY_CD)                           AS VOCABULARY_CD
	         ,CONVERT(VARCHAR(100),dbo.csvString(VOCAB.CODE_DESC_TXT))       AS VocabDesc
             ,CONVERT(VARCHAR(100),dbo.csvString(F.[TYPE_MEAN]))             AS [TYPE]
             ,CONVERT(VARCHAR(16),F.[SRC_BEG_EFFECT_DT_TM],120)              AS BegEffectDate
             ,CONVERT(VARCHAR(16),F.[SRC_END_EFFECT_DT_TM],120)              AS EndEffectDate
             ,CONVERT(VARCHAR(14),F.FHX_VALUE_FLG)                           AS FHX_VALUE_FLG
	  --INTO  BH_RESEARCH.DBO.RDE_FamilyHistory
     FROM [BH_DATAWAREHOUSE].[dbo].[PI_DIR_FAMILY_HISTORY_ACTIVITY]  F
          INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter E
               ON F.PERSON_ID=E.PERSON_ID 
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT_PERSON_RELTN] REL
               ON F.RELATED_PERSON_ID=REL.RELATED_PERSON_ID
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_NOMENCLATURE_REF]  R
               ON F.ACTIVITY_NOMEN=R.NOMENCLATURE_ID
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF]  REF
               ON REL.RELATION_CD=REF.CODE_VALUE_CD
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] RELTYPE
               ON REL.RELATION_TYPE_CD=RELTYPE.CODE_VALUE_CD
          LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF]  VOCAB
               ON R.VOCABULARY_CD=VOCAB.CODE_VALUE_CD
           --WHERE  F.FHX_VALUE_FLG=1 --This field Indicates wether the condition for a Family member is positive, negative or unknown. 1 is positive 
		   WHERE CAST(F.SRC_BEG_EFFECT_DT_TM AS DATE)>=@DATE
		   ORDER BY BegEffectDate

Select @Row_Count=@@ROWCOUNT

  CREATE INDEX indx_FHist ON  BH_RESEARCH.DBO.RDE_FamilyHistory (NHS_Number)

Set @ErrorPosition=350
Set @ErrorMessage='Family history details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Family History', @StartDate, @EndDate,@time,@Row_Count)   
	END
---------------------------------------------------------------------------------------------------------
--BLOB DATA
---------------------------------------------------------------------------------------------------------

Set @ErrorPosition=360
Set @ErrorMessage='Blob data'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_BLOBDataset', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_BLOBDataset
   CREATE TABLE  BH_RESEARCH.DBO.RDE_BLOBDataset (
         NHS_Number			VARCHAR(14)
		,MRN				VARCHAR(20)
		,ClinicalSignificantDate VARCHAR(16)
		,MainEventDesc		VARCHAR(MAX)
		,MainTitleText		VARCHAR(MAX)
		,MainTagText		VARCHAR(MAX)
		,ChildEvent			VARCHAR(MAX)
		,ChildTagText		VARCHAR(MAX)
		,BlobContents		VARCHAR(MAX)
		,EventDesc			VARCHAR(MAX)
		,EventResultText	VARCHAR(MAX)
		,EventResultNBR		VARCHAR(20)
		,EventReltnDesc		VARCHAR(20)
		,[Status]			VARCHAR(20)
		,SourceSys			VARCHAR(20)
		,ClassDesc			VARCHAR(20)
		,ParentEventID		VARCHAR(20)
				)

Set @ErrorPosition=370
Set @ErrorMessage='Blob dataset temp table created'

IF @BLOBdata=1
   BEGIN
     
	 SELECT @StartDate =GETDATE()

	    INSERT INTO  BH_RESEARCH.DBO.RDE_BLOBDataset
  
          SELECT 
	        CONVERT(VARCHAR(14),E.NHS_Number)                                          AS NHS_Number
			,E.MRN
			,CONVERT(VARCHAR(16),CE.CLIN_SIGNIFICANCE_DT_TM,120)                       AS ClinicalSignificantDate
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(PEvent.CODE_DESC_TXT))                                AS MainEventDesc
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(CE2.EVENT_TITLE_TXT))                                 AS MainTitleText
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(CE2.EVENT_TAG_TXT))                                   AS MainTagText 
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(CE.EVENT_TITLE_TXT))                                  AS ChildEvent
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(CE.EVENT_TAG_TXT))                                    AS ChildTagText  
			,CONVERT(VARCHAR(MAX),dbo.csvString(B.BLOB_CONTENTS))                                      AS BlobContents
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(Evntcd.CODE_DISP_TXT))                                AS EventDesc
	        ,CONVERT(VARCHAR(MAX),dbo.csvString(CE.EVENT_RESULT_TXT))                                 AS EventResultText
	        ,CONVERT(VARCHAR(20),CE.EVENT_RESULT_NBR)                                  AS EventResultNBR
	        ,CONVERT(VARCHAR(20),dbo.csvString(EReltn.CODE_DESC_TXT))                                 AS EventReltnDesc
	        ,CONVERT(VARCHAR(20),dbo.csvString(RecStat.CODE_DESC_TXT))                                AS [Status]
	        ,CONVERT(VARCHAR(20),dbo.csvString(ConSys.CODE_DESC_TXT))                                 AS SourceSys
	        ,CONVERT(VARCHAR(20),dbo.csvString(EvntCls.CODE_DESC_TXT))                                AS ClassDesc
	        ,CONVERT(VARCHAR(20),CE.PARENT_EVENT_ID)                                   AS ParentEventID
	        --,CONVERT(VARCHAR(20),CE.EVENT_ID)                                          AS ChildEventID
    FROM BH_RESEARCH.DBO.TempBLOB B WITH(NOLOCK)
            INNER JOIN BH_RESEARCH.DBO.TEMPCE CE WITH(NOLOCK)
                 ON B.EVENT_ID = CE.EVENT_ID
            INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter E WITH(NOLOCK) 
                 ON  CE.ENCNTR_ID=E.ENCNTR_ID
	        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] EvntCls with (nolock)
	             ON ce.EVENT_CLASS_CD = EvntCls.CODE_VALUE_CD	 
	        LEFT OUTER JOIN BH_RESEARCH.DBO.TempCE  CE2  with (nolock)
	             ON CE.PARENT_EVENT_ID = CE2.EVENT_ID
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] Evntcd with (nolock)
		         ON CE.EVENT_CD = Evntcd.CODE_VALUE_CD
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] EReltn with (nolock)
		         ON CE.EVENT_RELTN_CD = EReltn.CODE_VALUE_CD
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] RecStat with (nolock)
		         ON CE.RECORD_STATUS_CD = RecStat.CODE_VALUE_CD
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] ConSys with (nolock)
		         ON CE.CONTRIBUTOR_SYSTEM_CD = ConSys.CODE_VALUE_CD
		    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. [PI_LKP_CDE_CODE_VALUE_REF] PEvent with (nolock)
		         ON CE2.EVENT_CD = PEvent.CODE_VALUE_CD
	 WHERE BLOB_CONTENTS IS NOT NULL AND E.NHS_Number IS NOT NULL 
	 AND CAST(B.EXTRACT_DT_TM AS DATE)>=@Date
	 ORDER BY ClinicalSignificantDate

Select @Row_Count=@@ROWCOUNT


CREATE INDEX indx_BLOB ON  BH_RESEARCH.DBO.RDE_BLOBDataset (NHS_Number)

Set @ErrorPosition=380
Set @ErrorMessage='Blob data is inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'BLOB data', @StartDate, @EndDate,@time,@Row_Count)
	END
------------------------------------------------------------------------------------------------------
---PC PROCEDURES
----------------------------------------------------------------------------------------------------------
Set @ErrorPosition=390
Set @ErrorMessage='PC PROCEDURES'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_PC_PROCEDURES', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_PC_PROCEDURES
   CREATE TABLE  BH_RESEARCH.DBO.RDE_PC_PROCEDURES (
        MRN				VARCHAR(14)
		,NHS_Number		VARCHAR(14)
		,AdmissionDT	VARCHAR(16)
		,DischargeDT	VARCHAR(16)
		,TreatmentFunc  VARCHAR(100)
		,Specialty		VARCHAR(100)
		,ProcDt			VARCHAR(16)
		,ProcDetails	VARCHAR(300)
		,ProcCD			VARCHAR(20)
		,ProcType		VARCHAR(100)
		,EncType		VARCHAR(50)
		--,EncntrID		VARCHAR(20)
		--,FinNbr			VARCHAR(20)
		,Comment		VARCHAR(1000))

Set @ErrorPosition=400
Set @ErrorMessage='PC PROCEDURES temp table created'

IF @PCProcedures=1
   BEGIN

   SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_PC_PROCEDURES
	   SELECT  
           E.MRN                                                         		AS MRN
           ,E.NHS_Number                                                         AS NHS_Number
           ,CONVERT(VARCHAR(16),[Admit_Dt_Tm],120)                              AS AdmissionDT
           ,CONVERT(VARCHAR(16),[Disch_Dt_Tm],120)                              AS DischargeDT
           ,CONVERT(VARCHAR(100),dbo.csvString([Trtmt_Func]))                                  AS TreatmentFunc              
           ,CONVERT(VARCHAR(100),dbo.csvString([Specialty]))                                   AS Specialty
           ,CONVERT(VARCHAR(16),[Proc_Dt_Tm],120)                               AS ProcDt
           ,CONVERT(VARCHAR(300),dbo.csvString([Proc_Txt]))                                   AS ProcDetails
           ,CONVERT(VARCHAR(20),[Proc_Cd])                                      AS ProcCD
           ,CONVERT(VARCHAR(100),dbo.csvString([Proc_Cd_Type]))                                AS ProcType
           ,CONVERT(VARCHAR(50),[Encounter_Type])                               AS EncType
           --,CONVERT(VARCHAR(20),[Encounter_Id])                                 AS EncntrID
           --,CONVERT(VARCHAR(20),[FIN_Nbr])			                            AS FinNbr
	       ,CONVERT(VARCHAR(1000),dbo.csvString(PCPROC.Comment))                               AS Comment
 
       FROM [BH_DATAWAREHOUSE].[dbo].[PC_PROCEDURES] PCProc  with (nolock)
       INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter E 
            ON PCproc.MRN=E.MRN --AND E.ENCNTR_ID=PCProc.Encounter_Id
       WHERE CAST(PCProc.Proc_Dt_Tm AS DATE) >=@DATE
	   ORDER BY AdmissionDT

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_Proc ON  BH_RESEARCH.DBO.RDE_PC_PROCEDURES (NHS_Number)
 
Set @ErrorPosition=410
Set @ErrorMessage='PCProcedures details is inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PCProcedures', @StartDate, @EndDate,@time,@Row_Count) 
	END
 --------------------------------------------------------------------------------------------------------------------
  --PC DIAGNOSIS
----------------------------------------------------------------------------------------------------------------------
Set @ErrorPosition=420
Set @ErrorMessage='PC Diagnosis'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS

    CREATE TABLE  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS (
        DiagID			VARCHAR(15)
		,Person_ID		VARCHAR(20)
		,NHS_Number		VARCHAR(20)
		--,EncntrID		VARCHAR(20)
		,MRN			VARCHAR(20)
		--,FinNBR			VARCHAR(20)
		,Diagnosis		VARCHAR(1000)
		,Confirmation	VARCHAR(100)
		,DiagDt			VARCHAR(16)
		,Classification VARCHAR(100)
		,ClinService	VARCHAR(100)
		,DiagType		VARCHAR(40)
		,DiagCode		VARCHAR(15)
		,Vocab			VARCHAR(100)
		,Axis			VARCHAR(100))
 
Set @ErrorPosition=430
Set @ErrorMessage='PC Diagnosis temp table created'

IF @PCDiagnosis =1
   BEGIN

   SELECT @StartDate =GETDATE()

    INSERT INTO  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS
          SELECT 
              CONVERT(VARCHAR(15),[Diagnosis_Id])								AS DiagID
             ,CONVERT(VARCHAR(20),PR.[Person_Id])								AS Person_ID
	         ,CONVERT(VARCHAR(20),E.NHS_Number)									AS NHS_Number
             --,CONVERT(VARCHAR(20),[Encounter_Id])								AS Encntr_ID
			 ,CONVERT(VARCHAR(20),E.[MRN])										AS MRN
			 --,CONVERT(VARCHAR(20),[Fin_Nbr])                                    AS FinNBR
			 ,CONVERT(VARCHAR(1000),dbo.csvString(Diagnosis))                                 AS Diagnosis
			 ,CONVERT(VARCHAR(100),dbo.csvString([Confirmation]))                              AS Confirmation             
			 ,CONVERT(VARCHAR(16),[Diag_Dt],120)                                AS DiagDt
			 ,CONVERT(VARCHAR(100),dbo.csvString([Classification]))                            AS Classification
			 ,CONVERT(VARCHAR(100),dbo.csvString([Clin_Service]))                              AS ClinService
			 ,CONVERT(VARCHAR(40),dbo.csvString([Diag_Type]))                                  AS DiagType
			 ,CONVERT(VARCHAR(15),[Diag_Code])                                  AS DiagCode
			 ,CONVERT(VARCHAR(100),dbo.csvString([Vocab]))                                      AS Vocab
			 ,CONVERT(VARCHAR(100),dbo.csvString([Axis]))                                       AS Axis
	
     
  FROM [BH_DATAWAREHOUSE].[dbo].[PC_DIAGNOSES] PR
        INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter E
            ON PR.PERSON_ID=E.PERSON_ID AND PR.Encounter_Id=E.ENCNTR_ID 
		WHERE CAST(PR.Diag_Dt AS DATE)>=@DATE
		ORDER BY DiagDt

Select @Row_Count=@@ROWCOUNT

-------------------------------------------------------------------------------------------
--UPDATE TEMP TABLE when the column is blank but not null
--To avoid creating blank strings in the JSON file
------------------------------------------------------------------------------------------


CREATE INDEX indx_Diag ON  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS (NHS_Number)

Set @ErrorPosition=440
Set @ErrorMessage='PC diagnosis details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PCDiagnosis', @StartDate, @EndDate,@time,@Row_Count)     
	END
--------------------------------------------------------------------------------------------------
  --PC PROBLEMS
--------------------------------------------------------------------------------------------------
Set @ErrorPosition=450
Set @ErrorMessage='PC Problems'

 IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_PC_PROBLEMS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_PC_PROBLEMS

	CREATE TABLE  BH_RESEARCH.DBO.RDE_PC_PROBLEMS (
		ProbID				VARCHAR(14)
		,Person_ID			VARCHAR(14)
		,MRN				VARCHAR(20)
		,NHS_Number			VARCHAR(20)
		,Problem			VARCHAR(200)
		,Annot_Disp			VARCHAR(200)
		,Confirmation		VARCHAR(100)
		,Classification		VARCHAR(100)
		,OnsetDate			VARCHAR(16)
		,StatusDate			VARCHAR(16)
		,Stat_LifeCycle		VARCHAR(30)
		,LifeCycleCancReson VARCHAR(30)
		,Vocab				VARCHAR(20)
		,Axis				VARCHAR(30)
		,SecDesc			VARCHAR(MAX)
		,ProbCode			VARCHAR(20))

Set @ErrorPosition=460
Set @ErrorMessage='PC Problems temp table created'

IF @PCProblems =1
   BEGIN

   SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_PC_PROBLEMS
        SELECT  
             CONVERT(VARCHAR(14), [Problem_Id])								   AS ProbID
			,CONVERT(VARCHAR(14),PCP.[Person_Id])							   AS Person_ID
			,CONVERT(VARCHAR(20),E.[MRN])								       AS MRN
			,CONVERT(VARCHAR(20),E.NHS_Number)								   AS NHS_Number
			,CONVERT(VARCHAR(200),dbo.csvString([Problem]))                                   AS Problem
			,CONVERT(VARCHAR(200),dbo.csvString([Annotated_Disp]))                            AS Annot_Disp
			,CONVERT(VARCHAR(100),dbo.csvString([Confirmation]))                              AS Confirmation
			,CONVERT(VARCHAR(100),dbo.csvString([Classification]))                            AS Classification
			,CONVERT(VARCHAR(16),[Onset_Date],120)                             AS OnsetDate
			,CONVERT(VARCHAR(16),[Status_Date],120)							   AS StatusDate
			,CONVERT(VARCHAR(30),dbo.csvString([Status_Lifecycle]))						   AS Stat_LifeCycle
			,CONVERT(VARCHAR(30),dbo.csvString([Lifecycle_Cancelled_Rsn]))					   AS LifeCycleCancReson
			
			,CONVERT(VARCHAR(30),dbo.csvString([Vocab]))									   AS Vocab
			,CONVERT(VARCHAR(30),dbo.csvString([Axis]))                                       AS Axis
			,CONVERT(VARCHAR(MAX),dbo.csvString([Secondary_Descriptions]))                     AS SecDesc
			,CONVERT(VARCHAR(20),[Problem_Code])							   AS ProbCode
    

  FROM [BH_DATAWAREHOUSE].[dbo].[PC_PROBLEMS] pcp WITH (NOLOCK)

        INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter E
          ON PCP.MRN=E.MRN AND PCP.Person_Id=E.PERSON_ID
	WHERE CAST(PCP.Onset_Date AS DATE)>=@DATE
	ORDER BY OnsetDate

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_Prob ON  BH_RESEARCH.DBO.RDE_PC_PROBLEMS (NHS_Number)


Set @ErrorPosition=470
Set @ErrorMessage='PCProblems details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PCProblems',@StartDate, @EndDate,@time,@Row_Count)     
	END
-- *****************************************************************************************************


---------------------------------------------------------------------------------------------------------
--------------MSDS
---------------------------------------------------------------------------------------------------------
--PREGNANCY BOOKING DETAILS
---------------------------------------------------------------------------------------------------------
Set @ErrorPosition=480
Set @ErrorMessage='MSDS MotherBooking'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MSDS_Booking', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MSDS_Booking

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MSDS_Booking (
		Person_ID								VARCHAR(14)
		,PregnancyID							    VARCHAR(14)
		,MRN								    VARCHAR(14)
		,NHS_Number								VARCHAR(14)
		,FirstAntenatalAPPTDate					VARCHAR(16)
		,AlcoholUnitsPerWeek					VARCHAR(14)
		,SmokingStatusBooking					VARCHAR(1000)
		,SmokingStatusDelivery					VARCHAR(1000)
		,SubstanceUse							VARCHAR(1000)
		,DeliveryDate							VARCHAR(16)
		,PostCode								VARCHAR(14)
		,Height_CM								FLOAT
		,Weight_KG								FLOAT
		,BMI									FLOAT
		,LaborOnsetMethod						VARCHAR(1000)
		,Augmentation 							VARCHAR(1000)
		,AnalgesiaDelivery						VARCHAR(1000)
		,AnalgesiaLabour						VARCHAR(1000)
		,AnaesthesiaDelivery					VARCHAR(1000)
		,AnaesthesiaLabour						VARCHAR(1000)
		,PerinealTrauma							VARCHAR(1000)
		,EpisiotomyDesc							VARCHAR(1000)
		,BloodLoss							    FLOAT
		,MSDS_AntenatalAPPTDate						VARCHAR(16)
		,MSDS_CompSocialFactor						VARCHAR(14)
		,MSDS_DisabilityMother						VARCHAR(14)
		,MSDS_MatDischargeDate						VARCHAR(16)
		,MSDS_DischReason							VARCHAR(100)
		,[MSDS_EST_DELIVERYDATE(AGREED)]				VARCHAR(16)
		,[MSDS_METH_OF_EST_DELIVERY_DATE(AGREED)]	VARCHAR(100)
		,MSDS_FolicAcidSupplement					VARCHAR(14)
		,MSDS_LastMensturalPeriodDate				VARCHAR(16)
		,MSDS_PregConfirmed							VARCHAR(16)
		,MSDS_PrevC_Sections							VARCHAR(14)
		,MSDS_PrevLiveBirths							VARCHAR(14)
		,MSDS_PrevLossesLessThan24Weeks				VARCHAR(14)
		,MSDS_PrevStillBirths						VARCHAR(14)
		,MSDS_MothSuppStatusIND						VARCHAR(14)
)

Set @ErrorPosition=490
Set @ErrorMessage='MSDS MotherBooking temp table created'

IF @MSDS=1
BEGIN

SELECT @StartDate =GETDATE()

   INSERT INTO  BH_RESEARCH.DBO.RDE_MSDS_Booking
       SELECT DISTINCT
	       CONVERT(VARCHAR(14),PREG.PERSON_ID)                               AS Person_ID 
          ,CONVERT(VARCHAR(14),PREG.PREGNANCY_ID)                               AS PregnancyID 
		  ,CONVERT(VARCHAR(14),DEM.MRN)                                        AS MRN   
		  ,CONVERT(VARCHAR(14),DEM.NHS_Number)                                 AS NHS_Number
		  ,CONVERT(VARCHAR(16),PREG.FIRST_ANTENATAL_ASSESSMENT_DT_TM ,120)       AS FirstAntenatalAPPTDate
		  ,CONVERT(VARCHAR(14),PREG.ALCOHOL_USE_NBR)							AS AlcoholUnitsPerWeek
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.SMOKE_BOOKING_DESC))                          AS SmokingStatusBooking
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.SMOKING_STATUS_DEL_DESC))                    AS SmokingStatusDelivery
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.REC_SUB_USE_DESC))                           AS SubstanceUse
		  ,CONVERT(VARCHAR(16),PREG.ROM_DT_TM,120)								AS DeliveryDate
		  ,(SELECT TOP(1) Postcode_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_CDE_PERSON_PATIENT_ADDRESS] AS ADDR WHERE ADDR.PERSON_ID = DEM.PERSON_ID) AS PostCode
		  ,PREG.HT_BOOKING_CM													AS Height_CM
		  ,PREG.WT_BOOKING_KG													AS Weight_KG
		  ,PREG.BMI_BOOKING_DESC												AS BMI
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.LAB_ONSET_METHOD_DESC))                    AS LaborOnsetMethod
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.AUGMENTATION_DESC))							AS Augmentation
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.ANALGESIA_DEL_DESC))							AS AnalgesiaDelivery
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.ANALGESIA_LAB_DESC))							AS AnalgesiaLabour
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.ANAESTHESIA_DEL_DESC))						AS AnaesthesiaDelivery
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.ANAESTHESIA_LAB_DESC))						AS AnaesthesiaLabour
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.PERINEAL_TRAUMA_DESC))							AS PerinealTrauma
		  ,CONVERT(VARCHAR(1000),dbo.csvString(PREG.EPISIOTOMY_DESC))							AS EpisiotomyDesc
		  ,TOTAL_BLOOD_LOSS														AS BloodLoss
		  ,CONVERT(VARCHAR(16),MSDS.ANTENATALAPPDATE ,120)                     AS MSDS_AntenatalAPPTDate
		  ,CONVERT(VARCHAR(14),MSDS.COMPLEXSOCIALFACTORSIND)                   AS MSDS_CompSocialFactor
		  ,CONVERT(VARCHAR(14),MSDS.DISABILITYINDMOTHER )                      AS MSDS_DisabilityMother
		  ,CONVERT(VARCHAR(16),MSDS.DISCHARGEDATEMATSERVICE,120)               AS MSDS_MatDischargeDate
		  ,CONVERT(VARCHAR(100),dbo.csvString(MSDS.DISCHREASON ))              AS MSDS_DischReason
		  ,CONVERT(VARCHAR(16),MSDS.EDDAGREED,120)                             AS [MDDS_EST_DELIVERYDATE(AGREED)]
		  ,CONVERT(VARCHAR(100),dbo.csvString(MSDS.EDDMETHOD ))                AS [MSDS_METH_OF_EST_DELIVERY_DATE(AGREED)]
		  ,CONVERT(VARCHAR(14),MSDS.FOLICACIDSUPPLEMENT)                       AS MSDS_FolicAcidSupplement                                        
		  ,CONVERT(VARCHAR(16),MSDS.LASTMENSTRUALPERIODDATE,120)               AS MSDS_LastMensturalPeriodDate
		  ,CONVERT(VARCHAR(16),MSDS.PREGFIRSTCONDATE,120)                      AS MSDS_PregConfirmed
		  ,CONVERT(VARCHAR(14),MSDS.PREVIOUSCAESAREANSECTIONS)                 AS MSDS_PrevC_Sections
		  ,CONVERT(VARCHAR(14),MSDS.PREVIOUSLIVEBIRTHS)                        AS MSDS_PrevLiveBirths
		  ,CONVERT(VARCHAR(14),MSDS.PREVIOUSLOSSESLESSTHAN24WEEKS)             AS MSDS_PrevLossesLessThan24Weeks
		  ,CONVERT(VARCHAR(14),MSDS.PREVIOUSSTILLBIRTHS)                       AS MSDS_PrevStillBirths
		  ,CONVERT(VARCHAR(14),MSDS.SUPPORTSTATUSINDMOTHER)                    AS MSDS_MothSuppStatusIND

	  
	 FROM [BH_DATAWAREHOUSE].[dbo].[MAT_PREGNANCY] PREG with (nolock)          
           INNER JOIN [BH_RESEARCH].[dbo].RDE_Patient_Demographics DEM       
              ON DEM.PERSON_ID=PREG.PERSON_ID
			  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MSD101PREGBOOK] MSDS with (nolock)
			  ON PREG.PREGNANCY_ID = MSDS.PREGNANCYID
			  ORDER BY PregnancyID

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_MB ON  BH_RESEARCH.DBO.RDE_MSDS_Booking (NHS_Number)
  
Set @ErrorPosition=500
Set @ErrorMessage='Pregnancy booking details inserted into Temptable'
   

    
  ----------------------------------------------------------------------------------
  --CARE CONTACT DETILS
 ----------------------------------------------------------------------------------
Set @ErrorPosition=510
Set @ErrorMessage='MSDS Care contact'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MSDS_CareContact', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MSDS_CareContact

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MSDS_CareContact 
		(NHS_Number			VARCHAR(14)
		,MRN       		    VARCHAR(14)
		,PregnancyID		VARCHAR(14)
		,CareConID			VARCHAR(14)
		,CareConDate		VARCHAR(16)
		,AdminCode			VARCHAR(14)
		,Duration			VARCHAR(14)
		,ConsultType		VARCHAR(14)
		,[Subject]			VARCHAR(14)
		,Medium				VARCHAR(14)
		,GPTherapyIND		VARCHAR(14)
		,AttendCode			VARCHAR(14)
		,CancelReason		VARCHAR(100)
		,CancelDate			VARCHAR(16)
		,RepAppOffDate		VARCHAR(16))

Set @ErrorPosition=520
Set @ErrorMessage='MSDS Care contact temp table created'



    INSERT INTO  BH_RESEARCH.DBO.RDE_MSDS_CareContact
       SELECT 
         CONVERT(VARCHAR(14),  MB.NHS_Number)                                   AS NHS_Number
		,MB.MRN																   AS MRN
        ,CONVERT(VARCHAR(14),CON.PREGNANCYID)                                  AS PregnancyID
	    ,CONVERT(VARCHAR(14),CON.[CARECONID])                                  AS CareConID
        ,CONVERT(VARCHAR(16),CON.[CCONTACTDATETIME],120)                       AS CareConDate
        ,CONVERT(VARCHAR(14),CON.[ADMINCATCODE])                               AS AdminCode
        ,CONVERT(VARCHAR(14),CON.[CONTACTDURATION])                            AS Duration
        ,CONVERT(VARCHAR(14),CON.[CONSULTTYPE])                                AS ConsultType
        ,CONVERT(VARCHAR(14),CON.[CCSUBJECT])                                  AS [Subject]
        ,CONVERT(VARCHAR(14),CON.[MEDIUM])                                     AS Medium
        ,CONVERT(VARCHAR(14),CON.[GPTHERAPYIND])                               AS GPTherapyIND
        ,CONVERT(VARCHAR(14),CON.[ATTENDCODE])                                 AS AttendCode
        ,CONVERT(VARCHAR(100),dbo.csvString(CON.[CANCELREASON]))                              AS CancelReason
        ,CONVERT(VARCHAR(16),CON.[CANCELDATE],120)                             AS CancelDate
        ,CONVERT(VARCHAR(16),CON.[REPLAPPTOFFDATE],120)                        AS RepAppOffDate
     
 FROM  [BH_DATAWAREHOUSE].[dbo].[MSD201CARECONTACTPREG] CON with (nolock)      --JOIN TO   BH_RESEARCH.DBO.RDE_MSDS_Booking1 INSTEAD OF THESE TWO
           INNER JOIN  BH_RESEARCH.DBO.RDE_MSDS_Booking MB
             ON MB.PREGNANCYID=CON.PREGNANCYID

Select @Row_Count=@Row_Count+@@ROWCOUNT

CREATE INDEX indx_CC ON  BH_RESEARCH.DBO.RDE_MSDS_CareContact (NHS_Number)


Set @ErrorPosition=530
Set @ErrorMessage='Care contact details inserted into Temptable'
   

------------------------------------------------------------------------------------------
  --PATIENT DELIVERY DETAILS
------------------------------------------------------------------------------------------
Set @ErrorPosition=540
Set @ErrorMessage='MSDS Delivery'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MSDS_Delivery', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MSDS_Delivery

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MSDS_Delivery (
		Person_ID					VARCHAR(14)
		,PregnancyID				VARCHAR(14)
		,NHS_Number					VARCHAR(14)
		,MRN					    VARCHAR(14)
		,BabyPerson_ID				VARCHAR(14)
		,Baby_MRN					VARCHAR(14)
		,Baby_NHS					VARCHAR(14)
		,BirthOrder					INTEGER
		,BirthNumber				INTEGER
		,BirthLocation				VARCHAR(1000)
		,BirthDateTime				VARCHAR(16)
		,DeliveryMethod				VARCHAR(1000)
		,DeliveryOutcome 		  VARCHAR(1000)
		,NeonatalOutcome			VARCHAR(1000)
		,PregOutcome				VARCHAR(1000)
		,PresDelDesc				VARCHAR(1000)
		,BirthWeight				VARCHAR(14)
		,BirthSex					VARCHAR(14)
		,APGAR1Min					INTEGER
		,APGAR5Min					INTEGER
		,FeedingMethod				VARCHAR(1000)
		,MotherComplications		VARCHAR(1000)
		,FetalComplications			VARCHAR(1000)
		,NeonatalComplications		VARCHAR(1000)
		,ResMethod					VARCHAR(1000)
		,MSDS_LabourDelID			VARCHAR(14)
		,MSDS_DeliverySite		VARCHAR(14)
		,MSDS_BirthSetting 		INTEGER
		,MSDS_BabyFirstFeedCode 	INTEGER
		,MSDS_SettingIntraCare 		VARCHAR(14)
		,MSDS_ReasonChangeDelSettingLab 	VARCHAR(14)
		,MSDS_LabourOnsetMeth			VARCHAR(14)
		,MSDS_LabOnsetDate				VARCHAR(16)
		,MSDS_CSectionDate				VARCHAR(16)
		,MSDS_DecDeliveryDate			VARCHAR(16)
		,MSDS_AdmMethCodeMothDelHSP		VARCHAR(14)
		,MSDS_DischDate					VARCHAR(16)
		,MSDS_DischMeth					VARCHAR(14)
		,MSDS_DischDest					VARCHAR(14)
		,MSDS_RomDate					VARCHAR(16) 
		,MSDS_RomMeth					VARCHAR(14)
		,MSDS_RomReason					VARCHAR(14)
		,MSDS_EpisiotomyReason			VARCHAR(100)
		,MSDS_PlancentaDelMeth			VARCHAR(14)
		,MSDS_LabOnsetPresentation		VARCHAR(100)

		)

Set @ErrorPosition=550
Set @ErrorMessage='MSDS Delivery temp table created'


INSERT INTO  BH_RESEARCH.DBO.RDE_MSDS_Delivery
  SELECT DISTINCT
  	       CONVERT(VARCHAR(14),MOTHER.PERSON_ID)                        			AS Person_ID 
          ,CONVERT(VARCHAR(14),BIRTH.PREGNANCY_ID)                      			AS PregnancyID 
		  ,CONVERT(VARCHAR(14),DEM.NHS_Number)                                 	    AS NHS_Number  
		  ,CONVERT(VARCHAR(14),DEM.MRN)                                 			AS MRN   
		  ,CONVERT(VARCHAR(14),BIRTH.BABY_PERSON_ID)                    			AS BabyPerson_ID
		  ,CONVERT(VARCHAR(14),BIRTH.MRN)											AS Baby_MRN
		  ,CONVERT(VARCHAR(14),REPLACE(BIRTH.[NHS],'-',''))                         AS Baby_NHS
		  ,BIRTH.BIRTH_ODR_NBR														AS BirthOrder
		  ,BIRTH.BIRTH_NBR															AS BirthNumber
          ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[BIRTH_LOC_DESC]))             AS BirthLocation
	      ,CONVERT(VARCHAR(16),BIRTH.[BIRTH_DT_TM],120)								AS BirthDateTime
          ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[DEL_METHOD_DESC]))            AS DeliveryMethod
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[DEL_OUTCOME_DESC]))           AS DeliveryOutcome
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[NEO_OUTCOME_DESC]))           AS NeonatalOutcome
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[PREG_OUTCOME_DESC]))          AS PregOutcome
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[PRES_DEL_DESC]))              AS PresDelDesc
		  ,CONVERT(VARCHAR(14),BIRTH.BIRTH_WT)										AS BirthWeight
		  ,CONVERT(VARCHAR(14),BIRTH.NB_SEX_DESC)									AS BirthSex
		  ,BIRTH.APGAR_1MIN															AS APGAR1Min
		  ,BIRTH.APGAR_5MIN															AS APGAR5Min
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[FEEDING_METHOD_DESC]))        AS FeedingMethod
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[MOTHER_COMPLICATION_DESC]))        AS MotherComplications
		  ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[FETAL_COMPLICATION_DESC]))        AS FetalComplications
	      ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[NEONATAL_COMPLICATION_DESC]))        AS NeonatalComplications
	      ,CONVERT(VARCHAR(1000),dbo.csvString(BIRTH.[RESUS_METHOD_DESC]))			AS ResMethod
		  ,CONVERT(VARCHAR(14),MSDS.LABOURDELIVERYID)                                AS MSDS_LabourDelID         
		  ,CONVERT(VARCHAR(14),MSDBABY.ORGSITEIDACTUALDELIVERY)                      AS MSDS_DeliverySite
		  ,MSDBABY.SETTINGPLACEBIRTH												AS MSDS_BirthSetting
		  ,MSDBABY.BABYFIRSTFEEDINDCODE												AS MSDS_BabyFirstFeedCode
	     ,CONVERT(VARCHAR(14),MSDS.[SETTINGINTRACARE])                              AS MSDS_SettingIntraCare
         ,CONVERT(VARCHAR(14),MSDS.[REASONCHANGEDELSETTINGLAB])                     AS MSDS_ReasonChangeDelSettingLab
         ,CONVERT(VARCHAR(14),MSDS.[LABOURONSETMETHOD])                             AS MSDS_LabourOnsetMeth
         ,CONVERT(VARCHAR(16),MSDS.[LABOURONSETDATETIME],120)                       AS MSDS_LabOnsetDate
         ,CONVERT(VARCHAR(16),MSDS.[CAESAREANDATETIME],120)                         AS MSDS_CSectionDate
         ,CONVERT(VARCHAR(16),MSDS.[DECISIONTODELIVERDATETIME],120)                 AS MSDS_DecDeliveryDate
         ,CONVERT(VARCHAR(14),MSDS.[ADMMETHCODEMOTHDELHSP])                         AS MSDS_AdmMethCodeMothDelHSP
         ,CONVERT(VARCHAR(16),MSDS.[DISCHARGEDATETIMEMOTHERHSP],120)                AS MSDS_DischDate                        
         ,CONVERT(VARCHAR(14),MSDS.[DISCHMETHCODEMOTHPOSTDELHSP])                   AS MSDS_DischMeth
         ,CONVERT(VARCHAR(14),MSDS.[DISCHDESTCODEMOTHPOSTDELHSP])                   AS MSDS_DischDest             
         ,CONVERT(VARCHAR(16),MSDS.[ROMDATETIME],120)                               AS MSDS_RomDate
         ,CONVERT(VARCHAR(14),MSDS.[ROMMETHOD])                                     AS MSDS_RomMeth
         ,CONVERT(VARCHAR(100),dbo.csvString(MSDS.[ROMREASON]))                     AS MSDS_RomReason
         ,CONVERT(VARCHAR(100),dbo.csvString(MSDS.[EPISIOTOMYREASON]))              AS MSDS_EpisiotomyReason
         ,CONVERT(VARCHAR(14),MSDS.[PLACENTADELIVERYMETHOD])                        AS MSDS_PlancentaDelMeth
         ,CONVERT(VARCHAR(100),dbo.csvString(MSDS.[LABOURONSETPRESENTATION]))       AS MSDS_LabOnsetPresentation

		  FROM [BH_DATAWAREHOUSE].[dbo].[MAT_BIRTH] BIRTH with (nolock)
		  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MAT_PREGNANCY] MOTHER with (nolock)
		  ON BIRTH.PREGNANCY_ID = MOTHER.PREGNANCY_ID
		  INNER JOIN [BH_RESEARCH].[dbo].RDE_Patient_Demographics DEM       
           ON DEM.PERSON_ID=MOTHER.PERSON_ID
		  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MSD301LABDEL] MSDS with (nolock)
			  ON BIRTH.PREGNANCY_ID = MSDS.PREGNANCYID
			  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].MSD401BABYDEMO MSDBABY with (nolock)
			  ON MSDS.LABOURDELIVERYID = MSDBABY.LABOURDELIVERYID


Select @Row_Count=@Row_Count+@@ROWCOUNT

CREATE INDEX indx_Lab ON  BH_RESEARCH.DBO.RDE_MSDS_Delivery (NHS_Number)

Set @ErrorPosition=560
Set @ErrorMessage='Delivery details inserted into Temptable'
   

  ----------------------------------------------------------------------------------
 -------------------DIAGNOSIS
 -----------------------------------------------------------------------------------
Set @ErrorPosition=570
Set @ErrorMessage='MSDS Diagnosis'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MSDS_Diagnosis', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MSDS_Diagnosis

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MSDS_Diagnosis (
		NHS_Number			VARCHAR(14)
		,MRN                VARCHAR(14)
		,DiagPregID			VARCHAR(14)
		,DiagScheme			VARCHAR(14)
		,Diagnosis			VARCHAR(14)
		,DiagDate			VARCHAR(16)
		,LocalFetalID		VARCHAR(14)
		,FetalOrder			VARCHAR(14)
		--,Valid				INT
		,SnomedCD			VARCHAR(14)
		,DiagDesc			VARCHAR(2000))

Set @ErrorPosition=580
Set @ErrorMessage='MSDS Diagnosis temp table created'


INSERT INTO  BH_RESEARCH.DBO.RDE_MSDS_Diagnosis
      SELECT 
          CONVERT(VARCHAR(14),PREG.NHS_Number)                                 AS NHS_Number
		 ,PREG.MRN
		 ,CONVERT(VARCHAR(14),DIAG.pregnancyID)                               AS DiagPregID
         ,CONVERT(VARCHAR(14),DIAG.[DIAGSCHEME])                              AS DiagScheme
         ,CONVERT(VARCHAR(14),DIAG.[DIAG])                                    AS Diagnosis
         ,CONVERT(VARCHAR(16),DIAG.[DIAGDATE],120)                            AS DiagDate
         ,CONVERT(VARCHAR(14),DIAG.[LOCALFETALID])                            AS LocalFetalID
         ,CONVERT(VARCHAR(14),DIAG.FETALORDER)                                AS FetalOrder
         --,CONVERT(int,DIAG.IS_VALID)                                          AS Valid
         ,CONVERT(VARCHAR(14),S.SNOMED_CD )                                   AS SnomedCD
		 ,CONVERT(VARCHAR(2000),dbo.csvString(S.[SOURCE_STRING]) )                             AS DiagDesc
  FROM [BH_DATAWAREHOUSE].[dbo].[MSD106DIAGNOSISPREG] Diag with (nolock)
	     INNER JOIN  BH_RESEARCH.DBO.RDE_MSDS_Booking PREG with (nolock)
             ON PREG.PREGNANCYID=Diag.PREGNANCYID
         LEFT OUTER JOIN  (SELECT *, ROW_NUMBER() OVER ( PARTITION BY SNOMED_CD ORDER BY[UPDT_DT_TM] DESC ) LastUpdt
                           FROM  [BH_DATAWAREHOUSE].[dbo].[LKP_MILL_DIR_SNOMED] )S
             ON DIAG.DIAG=S.SNOMED_CD and LastUpdt=1
  ORDER BY DIAG.PREGNANCYID

Select @Row_Count=@Row_Count+@@ROWCOUNT

CREATE INDEX indx_MSD ON  BH_RESEARCH.DBO.RDE_MSDS_Diagnosis (NHS_Number) 

Set @ErrorPosition=590
Set @ErrorMessage='MSDS Diagnosis details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'MSDS', @StartDate, @EndDate,@time,@Row_Count)    



--------------------------------------------------------------------------------------------------------
 -- NEW MATERNITY TABLES
----------------------------------------------------------------------------------

/****** [BadgerNetReporting].[bnf_dbsync].[NNURoutineExamination] NNUExam  ******/

Set @ErrorPosition=595
Set @ErrorMessage='Badgernet Exam'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MAT_NNU_Exam', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MAT_NNU_Exam

SELECT PDEM.Person_ID,
	  PDEM.MRN,
      (NIE.nationalid) AS NHS_Number
      ,coalesce([DateOfExamination], [RecordTimestamp]) AS ExamDate
      ,[HeadCircumference]
      ,[Skin]
      ,[SkinComments]
      ,[Cranium]
      ,[CraniumComments]
      ,[Fontanelle]
      ,[FontanelleComments]
      ,[Sutures]
      ,[SuturesComments]
      ,[RedReflex]
      ,[RedReflexComments]
      ,[RedReflexRight]
      ,[RedReflexCommentsRight]
      ,[Ears]
      ,[EarsComments]
      ,[PalateSuck]
      ,[PalateSuckComments]
      ,[Spine]
      ,[SpineComments]
      ,[Breath]
      ,[BreathComments]
      ,[Heart]
      ,[HeartComments]
      ,[Femoral]
      ,[FemoralComments]
      ,[FemoralRight]
      ,[FemoralCommentsRight]
      ,[Abdomen]
      ,[AbdomenComments]
      ,[Genitalia]
      ,[GenitaliaComments]
      ,[Testicles]
      ,[TesticlesComments]
      ,[Anus]
      ,[AnusComments]
      ,[Hands]
      ,[HandsComments]
      ,[Feet]
      ,[FeetComments]
      ,[Hips]
      ,[HipsComments]
      ,[HipsRight]
      ,[HipRightComments]
      ,[Tone]
      ,[ToneComments]
      ,[Movement]
      ,[MovementComments]
      ,[Moro]
      ,[MoroComments]
      ,[Overall]
      ,[OverallComments]
      ,[NameOfExaminer]
      ,[Palate]
      ,[PalateComments]
      ,[SuckingReflex]
      ,[SuckingReflexComments]
      ,[EarsLeft]
      ,[EarsCommentsLeft]
      ,[EarsRight]
      ,[EarsCommentsRight]
      ,[Eyes]
      ,[EyesComments]
      ,[Chest_NZ]
      ,[ChestComments_NZ]
      ,[Mouth_NZ]
      ,[MouthComments_NZ]
      ,[Growth_NZ]
      ,[GrowthComments_NZ]
      ,[Grasp]
      ,[GraspComments]
      ,[Femorals_NZ]
      ,[FemoralsComments_NZ]
      ,[InguinalHernia]
      ,[InguinalHerniaComments]
      ,[GeneralComments]
      ,[SyncScope]
  INTO BH_RESEARCH.dbo.RDE_MAT_NNU_Exam
  FROM [BadgerNetReporting].[bnf_dbsync].[NNURoutineExamination] NNUExam
  LEFT JOIN [BadgerNetReporting].[dbo].[tblNationalIdEpIdx] NIE ON NIE.EntityID = NNUExam.entityid
  LEFT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] PDEM
  ON NIE.nationalid = PDEM.NHS_Number
  WHERE PERSON_ID IS NOT NULL


Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_MSD ON  BH_RESEARCH.DBO.RDE_MAT_NNU_Exam (NHS_Number) 

Set @ErrorPosition=590
Set @ErrorMessage='Mat NNU Exam details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'MAT NNU Exam', @StartDate, @EndDate,@time,@Row_Count)     






IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes



/****** [BadgerNetReporting].[bnf_dbsync].[NNUEpisodes] ******/
SELECT
      PDEM.Person_ID,
      [NationalIDBaby] AS NHS_Number
      ,PDEM.MRN AS MRN
      ,[CareLocationName]
      ,[EpisodeType]
      ,[Sex]
      ,[BirthTimeBaby]
      ,[GestationWeeks]
      ,[GestationDays]
      ,[Birthweight]
      ,[BirthLength]
      ,[BirthHeadCircumference]
      ,[BirthOrder]
      ,[FetusNumber]
      ,[BirthSummary]
      ,[EpisodeNumber]
      ,[AdmitTime]
      ,[AdmitFromName]
      ,[AdmitFromNHSCode]
      ,[ProviderName]
      ,[ProviderNHSCode]
      ,[NetworkName]
      ,[AdmitTemperature]
      ,[AdmitTemperatureTime]
      ,[AdmitBloodPressure]
      ,[AdmitHeartRate]
      ,[AdmitRespiratoryRate]
      ,[AdmitSaO2]
      ,[AdmitBloodGlucose]
      ,[AdmitWeight]
      ,[AdmitHeadCircumference]
      ,[DischTime]
      ,[DischargeHospitalName]
      ,[DischargeHospitalCode]
      ,[DischargeWeight]
      ,[DischargeHeadCircumference]
      ,[DischargeMilk]
      ,[DischargeFeeding]
      ,[HomeTubeFeeding]
      ,[DischargeOxygen]
      ,[EpisodeSummary]
      ,[VentilationDays]
      ,[CPAPDays]
      ,[OxygenDays]
      ,[OxygenDaysNoVent]
      ,[OxygenLastTime]
      ,[ICCareDays]
      ,[HDCareDays]
      ,[SCCareDays]
      ,[ICCareDays2011]
      ,[HDCareDays2011]
      ,[SCCareDays2011]
      ,[NormalCareDays2011]
      ,[HRG1]
      ,[HRG2]
      ,[HRG3]
      ,[HRG4]
      ,[HRG5]
      ,[LocnNNUDays]
      ,[LocnTCDays]
      ,[LocnPNWDays]
      ,[LocnOBSDays]
      ,[LocnNNUPortion]
      ,[LocnTCPoriton]
      ,[LocnPNWPortion]
      ,[DrugsDuringStay]
      ,[DiagnosisDuringStay]
      ,[NationalIDMother]
      ,[BloodGroupMother]
      ,[BirthDateMother]
      ,[AgeMother]
      ,[HepBMother]
      ,[HepBMotherHighRisk]
      ,[HivMother]
      ,[RubellaScreenMother]
      ,[SyphilisScreenMother]
      ,[MumHCV]
      ,[HepCPCRMother]
      ,[MumVDRL]
      ,[MumTPHA]
      ,[MaternalPyrexiaInLabour38c]
      ,[IntrapartumAntibioticsGiven]
      ,[MeconiumStainedLiquor]
      ,[MembraneRuptureDate]
      ,[MembranerupturedDuration]
      ,[ParentsConsanguinous]
      ,[DrugsAbusedMother]
      ,[SmokingMother]
      ,[CigarettesMother]
      ,[AlcoholMother]
      ,[PreviousPregnanciesNumber]
      ,[AgeFather]
      ,[EthnicityFather]
      ,[GestationWeeksCalculated]
      ,[GestationDaysCalculated]
      ,[BookingName]
      ,[BookingNHSCode]
      ,[SteroidsAntenatalGiven]
      ,[SteroidsName]
      ,[SteroidsAntenatalCourses]
      ,[PlaceOfBirthName]
      ,[PlaceOfBirthNHSCode]
      ,[Apgar1]
      ,[Apgar5]
      ,[Apgar10]
      ,[BabyBloodType]
      ,[Crib2Score]
      ,[FinalNNUOutcome]
      ,[VitaminKGiven]
      ,[CordArterialpH]
      ,[CordVenouspH]
      ,[CordPcO2Arterial]
      ,[CordPcO2Venous]
      ,[CordArterialBE]
      ,[CordVenousBE]
      ,[CordClamping]
      ,[CordClampingTimeMinute]
      ,[CordClampingTimeSecond]
      ,[CordStripping]
      ,[ResusSurfactant]
      ,[Seizures]
      ,[HIEGrade]
      ,[Anticonvulsants]
      ,[Pneumothorax]
      ,[NecrotisingEnterocolitis]
      ,[NeonatalAbstinence]
      ,[ROPScreenDate]
      ,[ROPSurgeryDate]
      ,[Dexamethasone]
      ,[PDAIndomethacin]
      ,[PDAIbuprofen]
      ,[PDASurgery]
      ,[PDADischarge]
      ,[UACTime]
      ,[UVCTime]
      ,[LongLineTime]
      ,[PeripheralArterialLineTime]
      ,[SurgicalLineTime]
      ,[ParenteralNutritionDays]
      ,[HeadScanFirstTime]
      ,[HeadScanFirstResult]
      ,[HeadScanLastTime]
      ,[HeadScanLastResult]
      ,[CongenitalAnomalies]
      ,[VPShuntTime]
      ,[BloodCultureFirstTime]
      ,[BloodCultureFirstResult]
      ,[CSFCultureFirstTime]
      ,[CSFCultureFirstResult]
      ,[UrineCultureFirstTime]
      ,[UrineCultureFirstResult]
      ,[ExchangeTransfusion]
      ,[Tracheostomy]
      ,[PulmonaryVasodilatorTime]
      ,[PulmonaryVasodilatorDrugs]
      ,[Inotropes]
      ,[InotropesFirstTime]
      ,[PeritonealDialysis]
      ,[DischargeApnoeaCardioSat]
      ,[gastroschisis]
      ,[Cooled]
      ,[FirstConsultationWithParents]
      ,[ReceivedMothersMilkDuringAdmission]
      ,[DischargeLength]
      ,[PrincipalDiagnosisAtDischarge]
      ,[ActiveProblemsAtDischarge]
      ,[PrincipleProceduresDuringStay]
      ,[RespiratoryDiagnoses]
      ,[CardiovascularDiagnoses]
      ,[GastrointestinalDiagnoses]
      ,[NeurologyDiagnoses]
      ,[ROPDiagnosis]
      ,[HaemDiagnoses]
      ,[RenalDiagnoses]
      ,[SkinDiagnoses]
      ,[MetabolicDiagnoses]
      ,[InfectionsDiagnoses]
      ,[SocialIssues]
      ,[DayOneLocationOfCare]
      ,[BirthCareLocationName]
      ,[UnitResponsibleFor2YearFollowUp]
      ,[CordLactate]
      ,[ROPScreenFirstDateDueStart]
      ,[ROPScreenFirstDateDueEnd]
      ,[ROPFirstScreenStart]
      ,[ROPFirstScreenEnd]
      ,[LSOA]
      ,[DateOfFirstExamination]
      ,[DateOfRoutineNeonatalExamination]
      ,[MotherIntendToBreastFeed]
      ,[MagnesiumSulphate]
      ,[ReasonMagnesiumSulphateNotGiven]
      ,[LabourWardDeath]
      ,[AdmitPrincipalReason_Other]
      ,[TwoYearFollowUpPerformedAnyEpisode]
      ,[CauseOfDeath1A]
      ,[CauseOfDeath1B]
      ,[CauseOfDeath2]
      ,[DateTimeLeftHospital]
      ,[ReasonMagnesiumSulphateGiven]
      ,[TwoYearFollowUpPerformedAnyEpisode_Date]
      ,[MaternalMedicalNotes]
      ,[AnomalyScanComments]
      ,[ReceivedAntenatalCare]
      ,[DateFirstUltrasound]
      ,[FollowUp]
      ,[timeReady]
      ,[BabyAwaiting]
      ,[TransferDestinationHospital]
      ,[EPOCDischargeLetterSent]
      ,[ParentEducationHandExpress]
      ,[ParentEducationBreastPump]
      ,[DischargeSummaryReferredToOutreachTeam]
      ,[DischargeSummaryReferredToOutreachTeam_Date]
      ,[NECDiagnosis]
      ,[NECDiagBasedOn]
      ,[clinicalFeatures]
      ,[radiographicFeatures]
      ,[FinalSummaryText]
      ,[DateTimeOfDeath]
      ,[SteroidsLastDose]
      ,[WaterBirth]
      ,[BCGImmunisationIndicated]
      ,[BCGGivenDuringStay]
      ,[MotherFirstLanguage]
      ,[MetabolicDiagnoses1]
      ,[MaternalCoronaVirusAtBirth]
      ,[EthnicityBaby]
      ,[SyncScope]
      ,[GestationWeeksCorrected_NowOrAtDisch]
      ,[GestationDaysCorrected_NowOrAtDisch]
  INTO BH_RESEARCH.dbo.RDE_MAT_NNU_Episodes
  FROM [BadgerNetReporting].[bnf_dbsync].[NNUEpisodes] Nep
  LEFT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] PDEM
  ON Nep.NationalIDBaby = PDEM.NHS_Number
  WHERE PERSON_ID IS NOT NULL

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_MSD ON  BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes (NHS_Number) 

Set @ErrorPosition=592
Set @ErrorMessage='Mat NNU Episode details inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'MAT NNU Episodes', @StartDate, @EndDate,@time,@Row_Count)     




IF OBJECT_ID(N'BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS', N'U') IS NOT NULL DROP TABLE BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS



/****** Script for SelectTopNRows command from SSMS  ******/
SELECT 
PDEM.Person_ID,
      [NHSNumberBaby] AS NHS_Number
      ,PDEM.MRN AS MRN
      ,[WardLocation]
      ,[DOB]
      ,[CriticalCareStartDate]
      ,[CriticalCareStartTime]
      ,[CriticalCareDischargeDate]
      ,[CriticalCareDischargeTime]
      ,[Gestation]
      ,[PersonWeight]
      ,[CCAC1]
      ,[CCAC2]
      ,[CCAC3]
      ,[CCAC4]
      ,[CCAC5]
      ,[CCAC6]
      ,[CCAC7]
      ,[CCAC8]
      ,[CCAC9]
      ,[CCAC10]
      ,[CCAC11]
      ,[CCAC12]
      ,[CCAC13]
      ,[CCAC14]
      ,[CCAC15]
      ,[CCAC16]
      ,[CCAC17]
      ,[CCAC18]
      ,[CCAC19]
      ,[CCAC20]
      ,[HCDRUG1]
      ,[HCDRUG2]
      ,[HCDRUG3]
      ,[HCDRUG4]
      ,[HCDRUG5]
      ,[HCDRUG6]
      ,[HCDRUG7]
      ,[HCDRUG8]
      ,[HCDRUG9]
      ,[HCDRUG10]
      ,[HCDRUG11]
      ,[HCDRUG12]
      ,[HCDRUG13]
      ,[HCDRUG14]
      ,[HCDRUG15]
      ,[HCDRUG16]
      ,[HCDRUG17]
      ,[HCDRUG18]
      ,[HCDRUG19]
      ,[HCDRUG20]
	INTO BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS
	FROM [BadgerNetReporting].[bnf_dbsync].[NNU_NCCMDS] MDS
    LEFT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] PDEM
  ON MDS.NHSNumberBaby = PDEM.NHS_Number
  WHERE PERSON_ID IS NOT NULL

Select @Row_Count=@@ROWCOUNT

CREATE INDEX indx_MSD ON  BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS (NHS_Number) 

Set @ErrorPosition=595
Set @ErrorMessage='Mat NNU NCCMDS inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'MAT NNU NCCMDS', @StartDate, @EndDate,@time,@Row_Count)     

END

--------------------------------------------------------------------------------------------------------
 -- PHARMACY ORDER
----------------------------------------------------------------------------------


Set @ErrorPosition=600
Set @ErrorMessage='Pharmacy Orders(Drugs)'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_PharmacyOrders', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_PharmacyOrders

	CREATE TABLE  BH_RESEARCH.DBO.RDE_PharmacyOrders (
		OrderID						VARCHAR(20)
		,MRN                        VARCHAR(20)
		,NHS_Number					VARCHAR(14)
		,ENCNTRID					VARCHAR(14)
		,EncType					VARCHAR(50)
		,PERSONID					VARCHAR(14)
		,OrderDate					VARCHAR(16)
		,LastOrderStatusDateTime	VARCHAR(16)
		,ReqStartDateTime			VARCHAR(16)
		,OrderText					VARCHAR(200)
		,Comments				    VARCHAR(MAX)
		,OrderDetails				VARCHAR(max)
		,LastOrderStatus			VARCHAR(50)
		,ClinicalCategory			VARCHAR(50)
		,ActivityDesc				VARCHAR(50)
		,OrderableType				VARCHAR(50)
		,PriorityDesc				VARCHAR(50)
		,CancelledReason			VARCHAR(50)
		, CancelledDT				VARCHAR(16) 
		,CompletedDT				VARCHAR(16)
		,DiscontinuedDT				VARCHAR(16)
		,ConceptIdent				VARCHAR(50))

Set @ErrorPosition=610
Set @ErrorMessage='Pharmacy Orders temp table created'

IF @PharmacyOrders=1
BEGIN

SELECT @StartDate =GETDATE()

   INSERT INTO  BH_RESEARCH.DBO.RDE_PharmacyOrders
       SELECT 
        CONVERT(VARCHAR(20),O.ORDER_ID)                                        AS OrderID
	   ,ENC.MRN
       ,CONVERT(VARCHAR(14),ENC.NHS_Number)                                     AS NHS_Number
       ,CONVERT(VARCHAR(14),O.[ENCNTR_ID])                                     AS ENCNTRID
	   ,CONVERT(VARCHAR(50),ENC.ENC_TYPE)                                      AS EncType
       ,CONVERT(VARCHAR(14),O.[PERSON_ID])                                     AS PERSONID
       ,CONVERT(VARCHAR(16),[ORDER_DT_TM],120)                                 AS OrderDate
	   ,CONVERT(VARCHAR(16),[LAST_ORDER_STATUS_DT_TM],120)                     AS LastOrderStatusDateTime
	   ,CONVERT(VARCHAR(16),[REQUESTED_START_DT_TM],120)                       AS ReqStartDateTime
       ,CONVERT(VARCHAR(200),dbo.csvString([ORDER_MNEM_TXT] ))                                AS OrderText
	   ,CONVERT(VARCHAR(MAX),dbo.csvString([ORDER_COMMENTS_TXT]))                           AS Comments 
	   ,CONVERT(VARCHAR(MAX),dbo.csvString(T.ORDER_DETAIL_DISPLAY_LINE))					   AS OrderDetails
	   ,CONVERT(VARCHAR(50),dbo.csvString(LastOStat.CODE_DESC_TXT))                           AS LastOrderStatus
	   ,CONVERT(VARCHAR(50),dbo.csvString(ClinicCat.CODE_DESC_TXT))                           AS ClinicalCategory
       ,CONVERT(VARCHAR(50),dbo.csvString(Activity.CODE_DESC_TXT))                            AS ActivityDesc
       ,CONVERT(VARCHAR(50),dbo.csvString(OrderTyp.CODE_DESC_TXT))                            AS OrderableType
       ,CONVERT(VARCHAR(50),dbo.csvString(Prio.CODE_DESC_TXT))                                AS PriorityDesc
	   ,CONVERT(VARCHAR(50),dbo.csvString(Cancel.CODE_DESC_TXT))                              AS CancelledReason
       ,CONVERT(VARCHAR(16),[CANCELED_DT_TM] ,120)                             AS CancelledDT
       ,CONVERT(VARCHAR(16),[COMPLETED_DT_TM] ,120)                            AS CompletedDT
       ,CONVERT(VARCHAR(16),[DISCONTINUE_DT_TM] ,120)                          AS DiscontinuedDT
       ,CONVERT(VARCHAR(50),[CONCEPT_CKI_IDENT])                               AS ConceptIdent
         
  FROM BH_RESEARCH.DBO.TempOrder O
 
        INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter ENC WITH (NOLOCK)
		   ON O.ENCNTR_ID=ENC.ENCNTR_ID
		   INNER JOIN BH_DATAWAREHOUSE.DBO.MILL_DIR_ORDER_TAILS T WITH (NOLOCK)
		   ON T.ORDER_ID=O.ORDER_ID AND T.ORIGINATING_ENCNTR_ID=O.ENCNTR_ID
 	    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Activity WITH (NOLOCK)
		   ON O.ACTIVITY_TYPE_CD = Activity.CODE_VALUE_CD
		LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Cancel WITH (NOLOCK)
		   ON O.CANCELED_REASON_CD = Cancel.CODE_VALUE_CD
	    LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF]  ClinicCat WITH (NOLOCK)
		   ON O.CLINICAL_CATEGORY_CD= ClinicCat.CODE_VALUE_CD
		LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF]  OrderTyp WITH (NOLOCK)
		   ON O.ORDERABLE_TYPE_CD = OrderTyp.CODE_VALUE_CD
		LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] LastOStat WITH (NOLOCK)
		   ON O.LAST_ORDER_STATUS_CD = LastOStat.CODE_VALUE_CD
		LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Prio WITH (NOLOCK)
		   ON O.PRIORITY_CD = Prio.CODE_VALUE_CD                                                      --10577 medications only
  WHERE ORDERABLE_TYPE_CD=2516 AND o.LAST_ORDER_STATUS_CD in  ('2543','2545','2547','2548','2550','2552','643466')
AND CLINICAL_CATEGORY_CD=10577 and o.ACTIVITY_TYPE_CD='705'--2516 pharmacy, 2550 order status as ordered
AND O.ACTIVE_IND=1 

Select @Row_Count=@@ROWCOUNT



CREATE INDEX indx_PO ON  BH_RESEARCH.DBO.RDE_PharmacyOrders (NHS_Number) 

--705  Pharmacy
--10577 Medications
--643466  Pending Complete
--2552  Suspended
--2550  ordered
--2547 Incomplete
--2548  InProcess
--2546  Future
--2543 completed
--2545  Discontinued
--2542 Cancelled
 

Set @ErrorPosition=620
Set @ErrorMessage='Pharmacy order details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PharmacyOrders', @StartDate, @EndDate,@time,@Row_Count) 
	END

	--SELECT TOP 10* FROM  BH_RESEARCH.DBO.RDE_PharmacyOrders
--------------------------------------------------------------------------------------------------------
  --ALLERGY
---------------------------------------------------------------------------------------------------------
Set @ErrorPosition=630
Set @ErrorMessage='Allergy Details'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_AllergyDetails', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_AllergyDetails

	CREATE TABLE  BH_RESEARCH.DBO.RDE_AllergyDetails (
		AllergyID			BIGINT
		,NHS_Number			VARCHAR(14)
		,MRN                VARCHAR(20)
		,SubstanceFTDesc	VARCHAR(1000)
		,SubstanceDesc		VARCHAR(1000)
		,SubstanceDispTxt	VARCHAR(1000)
		,SubstanceValueTxt  VARCHAR(50)
		,SubstanceType		VARCHAR(50)
		,ReactionType		VARCHAR(50)
		,Severity			VARCHAR(50)
		,SourceInfo			VARCHAR(50)
		,OnsetDT			VARCHAR(16)
		,ReactionStatus		VARCHAR(50)
		,CreatedDT			VARCHAR(16) 
		,CancelReason		VARCHAR(50)
		,CancelDT			VARCHAR(16)
		,ActiveStatus		VARCHAR(50)
		,ActiveDT			VARCHAR(16)
		,BegEffecDT			VARCHAR(16)
		,EndEffecDT			VARCHAR(16)
		,DataStatus			VARCHAR(50)
		,DataStatusDT		VARCHAR(16)
		,VocabDesc			VARCHAR(50)
		,PrecisionDesc		VARCHAR(50)
		)

Set @ErrorPosition=630
Set @ErrorMessage='Allergy Details temp table created'

IF @Allergy=1
BEGIN

SELECT @StartDate=GETDATE()

INSERT INTO  BH_RESEARCH.DBO.RDE_AllergyDetails
  SELECT 
        [ALLERGY_ID]                                                           AS AllergyID
	  ,CONVERT(VARCHAR(14),ENC.NHS_Number)                                      AS NHS_Number
	  ,ENC.MRN                   
      ,CONVERT(VARCHAR(1000),dbo.csvString([SUBSTANCE_FTDESC]))                                AS SubstanceFTDesc
	  ,CONVERT(VARCHAR(1000),dbo.csvString(Det.DESCRIPTION_TXT))                               AS SubstanceDesc
	  ,CONVERT(VARCHAR(1000),dbo.csvString(Det.DISPLAY_TXT ))                                  AS SubstanceDispTxt
	  ,CONVERT(VARCHAR(50),dbo.csvString(Det.VALUE_TXT ))                                     AS SubstanceValueTxt
	  ,CONVERT(VARCHAR(50),dbo.csvString(Sub.CODE_DESC_TXT))                                  AS SubstanceType
      ,CONVERT(VARCHAR(50),dbo.csvString(Reac.CODE_DESC_TXT))                                 AS ReactionType
      ,CONVERT(VARCHAR(50),dbo.csvString(Seve.CODE_DESC_TXT))                                 AS Severity
      ,CONVERT(VARCHAR(50),dbo.csvString(Sorc.CODE_DESC_TXT))                                 AS SourceInfo
      ,CONVERT(VARCHAR(16),[ONSET_DT_TM],120)                                  AS OnsetDT
      ,CONVERT(VARCHAR(50),dbo.csvString(ReacStat.CODE_DESC_TXT))                             AS ReactionStatus
      ,CONVERT(VARCHAR(16),[CREATED_DT_TM],120)                                AS CreatedDT
      ,CONVERT(VARCHAR(50),dbo.csvString(Creas.CODE_DESC_TXT))                                AS CancelReason
      ,CONVERT(VARCHAR(16),[CANCEL_DT_TM],120)                                 AS CancelDT
      ,CONVERT(VARCHAR(50),dbo.csvString(Activ.CODE_DESC_TXT))                                AS ActiveStatus
      ,CONVERT(VARCHAR(16),[ACTIVE_STATUS_DT_TM],120)                          AS ActiveDT
      ,CONVERT(VARCHAR(16),A.[BEG_EFFECTIVE_DT_TM],120  )                      AS BegEffecDT
      ,CONVERT(VARCHAR(16),A.[END_EFFECTIVE_DT_TM],120)                        AS EndEffecDT
      ,CONVERT(VARCHAR(50),dbo.csvString(Stat.CODE_DESC_TXT))                                 AS DataStatus
      ,CONVERT(VARCHAR(16),[DATA_STATUS_DT_TM],120)                            AS DataStatusDT   
      ,CONVERT(VARCHAR(50),dbo.csvString(Vocab.CODE_DESC_TXT))                                AS VocabDesc
      ,CONVERT(VARCHAR(50),dbo.csvString(Prec.CODE_DESC_TXT))                                 AS PrecisionDesc 
   FROM [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ALLERGY] A
        INNER JOIN  BH_RESEARCH.DBO.RDE_Encounter ENC 
		   ON A.ENCNTR_ID=ENC.ENCNTR_ID AND A.PERSON_ID=ENC.PERSON_ID 
        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Stat
		   ON CONVERT(VARCHAR(20), A.DATA_STATUS_CD) = Stat.CODE_VALUE_CD
        LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Prec
           ON CONVERT(VARCHAR(20),A.ONSET_PRECISION_CD)=Prec.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Reac
           ON CONVERT(VARCHAR(20),A.REACTION_CLASS_CD)=Reac.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] ReacStat
           ON CONVERT(VARCHAR(20),A.REACTION_STATUS_CD)=ReacStat.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Vocab
           ON CONVERT(VARCHAR(20),A.REC_SRC_VOCAB_CD)=Vocab.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Sub
           ON CONVERT(VARCHAR(20),A.SUBSTANCE_TYPE_CD)=Sub.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Seve
           ON CONVERT(VARCHAR(20),A.[SEVERITY_CD])=Seve.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Sorc
           ON CONVERT(VARCHAR(20),A.[SOURCE_OF_INFO_CD])=Sorc.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Creas
		   ON CONVERT(VARCHAR(20),A.[CANCEL_REASON_CD])=Creas.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] Activ
		   ON CONVERT(VARCHAR(20),A.[ACTIVE_STATUS_CD])=Activ.CODE_VALUE_CD
		LEFT OUTER JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_NOMENCLATURE_REF] Det
           ON A.SUBSTANCE_NOM_ID=Det.NOMENCLATURE_ID
		ORDER BY CAST([CREATED_DT_TM] AS DATE)

Select @Row_Count=@@ROWCOUNT


CREATE INDEX indx_Allergy ON  BH_RESEARCH.DBO.RDE_AllergyDetails (NHS_Number) 

Set @ErrorPosition=640
Set @ErrorMessage='Allergy details inserted into Temptable'
 

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Allergy',@StartDate, @EndDate,@time,@Row_Count)   
	END
-------------------------------------------------------------------------------------------------------
--somerset cancer registery
-------------------------------------------------------------------------------------------------------

Set @ErrorPosition=650
Set @ErrorMessage='Somerset Cancer Registry'

------------Patient demographics from somerset table TO EXTRACT SCR patient_id

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Demogrphics', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Demogrphics

CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Demogrphics (
	PATIENTID					VARCHAR(20)
	,NHS_Number					VARCHAR(10)
    ,MRN						VARCHAR(20)
	,DeathDate				    VARCHAR(40)
	,DeathCause					VARCHAR(MAX)
	,PT_AT_RISK					VARCHAR(MAX)
	,REASON_RISK				VARCHAR(MAX)
)


----------------------------------------------------------------------------------------------------------------
--MAIN REFERRALS TABLE SCR
----------------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Referrals', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Referrals

   CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Referrals (
		 CareID						 VARCHAR(10)
		,MRN                        VARCHAR(20)
		,NHS_Number					VARCHAR(10)
		,PATIENT_ID					VARCHAR(12)
		,CancerSite					VARCHAR(50)
		,PriorityDesc				VARCHAR(20)
		,DecisionDate				VARCHAR(16) 
		,ReceiptDate				VARCHAR(16) 
		,DateSeenFirst				VARCHAR(16) 		
		,CancerType					VARCHAR(200) 
		,StatusDesc					VARCHAR(50) 
		,FirstAppt					VARCHAR(16) 
		,DiagDate					VARCHAR(16) 
		,DiagCode					VARCHAR(20) 
		,DiagDesc					VARCHAR(200) 
		,OtherDiagDate				VARCHAR(16) 
		,Laterality					VARCHAR(100) 
		,DiagBasis					VARCHAR(50) 
		,Histology					VARCHAR(50) 
		,Differentiation			VARCHAR(100) 
		,ClinicalTStage				VARCHAR(100) 
		,ClinicalTCertainty			VARCHAR(100) 
		,ClinicalNStage				VARCHAR(100) 
		,ClinicalNCertainty			VARCHAR(100) 
		,ClinicalMStage				VARCHAR(100) 
		,ClinicalMCertainty			VARCHAR(100) 
		,PathologicalTCertainty		VARCHAR(100) 
		,PathologicalTStage			VARCHAR(100) 
		,PathologicalNCertainty		VARCHAR(100) 
		,PathologicalNStage			VARCHAR(100) 
		,PathologicalMCertainty		VARCHAR(100) 
		,PathologicalMStage			VARCHAR(100) 
		,TumourStatus				VARCHAR(50) 
		,TumourDesc					VARCHAR(100) 
		,NonCancer					VARCHAR(1000) 
		,CRecurrence				VARCHAR(100) 
		,RefComments				VARCHAR(Max) 
		,DecisionReason				VARCHAR(MAX) 
		,TreatReason				VARCHAR(2000) 
		,RecSiteID					VARCHAR(20) 
		,NewTumourSite				VARCHAR(20) 
		,ActionID					VARCHAR(20) 
		,SnomedCD					VARCHAR(20) 
		,SubSiteID					VARCHAR(20) 
	  )

Set @ErrorPosition=660
Set @ErrorMessage='Somerset Cancer Registry Referrals temp table created'


IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_TrackingComments', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_TrackingComments
  
	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_TrackingComments (
	    MRN                         VARCHAR(20),
		COM_ID						VARCHAR(10),
		CareID						VARCHAR(10),
		NHS_Number					VARCHAR(10),
        Date_Time					VARCHAR(16),
        Comments					VARCHAR(MAX)
		)


Set @ErrorPosition=671
Set @ErrorMessage='SCR Tracking Comments Temptable created'



----------------------------------------------------------------------------------------------------------
----SCR Care plan details (Data accuracy less than 60% for this table)
-----------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_CarePlan', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_CarePlan

	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_CarePlan(
	    PlanID						VARCHAR(10),
		MRN                         VARCHAR(20),
		CareID						VARCHAR(10),
		NHS_Number					VARCHAR(10),
		MDTDate						VARCHAR(16),
		CareIntent					VARCHAR(10),
		TreatType					VARCHAR(50),
		WHOStatus					VARCHAR(10),
		PlanType					VARCHAR(10),
		Network						VARCHAR(10),
		NetworkDate					VARCHAR(16),
		AgreedCarePlan				VARCHAR(10),
		MDTSite						VARCHAR(10),
		MDTComments					VARCHAR(MAX),
		NetworkFeedback				VARCHAR(MAX),
		NetworkComments				VARCHAR(MAX)
		)

Set @ErrorPosition=673
Set @ErrorMessage='SCR care plan Temptable created'


-----------------------------------------------------------------------------------------------------------
----SCR Definitive treatment details
-----------------------------------------------------------------------------------------------------------

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_DefTreatment', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_DefTreatment

	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_DefTreatment(
	    TreatmentID					VARCHAR(10),
		MRN                         VARCHAR(20),
		CareID						VARCHAR(10),
		NHS_Number					VARCHAR(10),
		DecisionDate				VARCHAR(16),
		StartDate					VARCHAR(16),
		Treatment					VARCHAR(100),
		TreatEvent					VARCHAR(50),
		TreatSetting				VARCHAR(10),
		TPriority					VARCHAR(10),
		Intent						VARCHAR(10),
		TreatNo						VARCHAR(16),
		TreatID						VARCHAR(20),
		ChemoRT						VARCHAR(100),
		DelayComments				VARCHAR(MAX),
		DEPRECATEDComments			VARCHAR(MAX),
		DEPRECATEDAllComments       VARCHAR(MAX),
		RootTCIComments				VARCHAR(MAX),
		ROOT_DATE_COMMENTS          VARCHAR(MAX)
		)
		

Set @ErrorPosition=675
Set @ErrorMessage='SCR Treatment Temptable created'



IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Diagnosis', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Diagnosis

	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Diagnosis(
	    CareID						VARCHAR(20),
		MRN							VARCHAR(20),
		CancerSite					VARCHAR(40),
		NHS_Number					VARCHAR(10),
		HospitalNumber				VARCHAR(10),
		PatientStatus				VARCHAR(MAX),
		TumourStatus				VARCHAR(MAX),
		NewTumourSite               VARCHAR(100),
		DiagDate					VARCHAR(16),
		DatePatInformed				VARCHAR(16),
		PrimDiagICD					VARCHAR(200),
		PrimDiagSnomed				VARCHAR(200),
		SecDiag						VARCHAR(200),
		Laterality					VARCHAR(2000),
		NonCancerdet				VARCHAR(2000),
		DiagBasis					VARCHAR(500),
		Histology					VARCHAR(500),
		Differentiation				VARCHAR(300),
		Comments					VARCHAR(MAX),
		PathwayEndFaster			VARCHAR(16),
		PathwayEndReason			VARCHAR(300),
		PrimCancerSite				VARCHAR(100)
		)

Set @ErrorPosition=677
Set @ErrorMessage='SCR Diagnosis Temptable created'

-----------------------------------------------------------------------------------------------------------
----SCR Definitive treatment details
-----------------------------------------------------------------------------------------------------------

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Investigations', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Investigations

	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Investigations(
	    CareID						VARCHAR(20),
		MRN                         VARCHAR(20),
		CancerSite					VARCHAR(40),
		NHS_Number					VARCHAR(10),
		HospitalNumber				VARCHAR(10),
		DiagInvestigation			VARCHAR(2000),
		ReqDate						VARCHAR(16),
		DatePerformed				VARCHAR(16),
		DateReported				VARCHAR(16),
		BiopsyTaken					VARCHAR(100),
		Outcome						VARCHAR(100),
		Comments					VARCHAR(MAX),
		NICIPCode					VARCHAR(200),
		SnomedCT					VARCHAR(200),
		AnotomicalSite				VARCHAR(50),
		AnatomicalSide				VARCHAR(200),
		ImagingReport				VARCHAR(MAX),
		StagingLaproscopyPerformed	VARCHAR(100)
		)


Set @ErrorPosition=679
Set @ErrorMessage='SCR Investigations Temptable created'

-----------------------------------------------------------------------------------------------------------
----SCR Pathology  details (incomplete) complete details available in pathology tables
-----------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Pathology', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Pathology

	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Pathology(
	    PathologyID						VARCHAR(20),
		MRN                             VARCHAR(20),
		CareID							VARCHAR(40),
		NHS_Number						VARCHAR(10),
		PathologyType					VARCHAR(10),
		ResultDate						VARCHAR(16),
		ExcisionMargins					VARCHAR(16),
		Nodes							VARCHAR(16),
		PositiveNodes					VARCHAR(50),
		PathTstage						VARCHAR(50),
		PathNstage						VARCHAR(50),
		PathMstage						VARCHAR(50),
		Comments						VARCHAR(MAX),
		SampleDate						VARCHAR(16),
	    PathologyReport					VARCHAR(MAX),
		SNomedCT						VARCHAR(50),
		SNomedID						VARCHAR(50)
)


Set @ErrorPosition=681
Set @ErrorMessage='SCR Pathology Temptable created'


-----------------------------------------------------------------------------------------------------------
----SCR Imaging  details (incomplete) better option to look into esctra tables for imaging
-----------------------------------------------------------------------------------------------------------


IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Imaging', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Imaging
	
	CREATE TABLE  BH_RESEARCH.DBO.RDE_SCR_Imaging(
	    ImageID							VARCHAR(20),
		MRN                             VARCHAR(20),
		CareID							VARCHAR(40),
		NHS_Number						VARCHAR(10),
		RequestDate						VARCHAR(16),
		ImagingDate 					VARCHAR(16),
		ReportDate						VARCHAR(16),
		AnatomicalSite					VARCHAR(50),
		AnatomicalSide					VARCHAR(50),
		ImageResult						VARCHAR(MAX),
		Contrast						VARCHAR(50),
		Result							VARCHAR(MAX),
	    Report							VARCHAR(MAX),
		StagingProc						VARCHAR(50),
		ImageCD							VARCHAR(50)
)


Set @ErrorPosition=683
Set @ErrorMessage='SCR Iamging Temptable created'
















-----------------------------------------------------------------------------------
--SCR is not enabled in MOCK as we do not have the linked server to the do so
------------------------------------------------------------------------------------



IF @SCR=1
	BEGIN

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_SCR_Demogrphics', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_SCR_Demogrphics

    SELECT [PATIENT_ID] AS PATIENTID
      ,[N1_1_NHS_NUMBER] AS NHS_Number
      ,[N1_2_HOSPITAL_NUMBER]  AS MRN
      ,[N15_1_DATE_DEATH]  AS DeathDate
      ,dbo.csvString([N15_3_DEATH_CAUSE]) AS DeathCause
      ,dbo.csvString([PT_AT_RISK]) AS PT_AT_RISK
      ,dbo.csvString([REASON_RISK]) AS REASON_RISK
	  
     INTO  BH_RESEARCH.DBO.RDE_SCR_Demogrphics
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblDEMOGRAPHICS] SCR WITH (NOLOCK)
  INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics PAT  
  ON --SCR.[N1_2_HOSPITAL_NUMBER]=PAT.MRN
  SCR.N1_1_NHS_NUMBER=PAT.NHS_Number


Select @Row_Count=@Row_Count+@@ROWCOUNT

Set @ErrorPosition=655
Set @ErrorMessage='Somerset Cancer Registry demographics temp table created'


	SELECT @StartDate=GETDATE()
    
INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_Referrals
    SELECT 
       CONVERT(VARCHAR(10),CARE_ID)                                                    AS CareID
	  ,D.MRN
      ,CONVERT(VARCHAR(10),D.NHS_Number)                                                AS NHS_Number
      ,CONVERT(VARCHAR(12),REF.[PATIENT_ID])                                           AS PATIENT_ID
	  ,CONVERT(VARCHAR(10),[L_CANCER_SITE])                                            AS CancerSite
      ,CONVERT(VARCHAR(20),dbo.csvString(PRIORITY_DESC))                                              AS PriorityDesc
      ,CONVERT(VARCHAR(16),[N2_5_DECISION_DATE],120)                                   AS DecisionDate      
      ,CONVERT(VARCHAR(16),[N2_6_RECEIPT_DATE],120)                                    AS ReceiptDate
      ,CONVERT(VARCHAR(16),[N2_9_FIRST_SEEN_DATE],120)                                 AS DateSeenFirst
      ,CONVERT(VARCHAR(100),dbo.csvString(CANCER_TYPE_DESC))                                          AS CancerType
      ,CONVERT(VARCHAR(16),STATUS_DESC)                                                AS StatusDesc
      ,CONVERT(VARCHAR(16),[L_FIRST_APPOINTMENT])                                      AS FirstAppt
      ,CONVERT(VARCHAR(16),N4_1_DIAGNOSIS_DATE,120)                                    AS DiagDate
	  ,CONVERT(VARCHAR(10),N4_2_DIAGNOSIS_CODE)                                        AS DiagCode
	  ,CONVERT(VARCHAR(200),dbo.csvString([DIAG_DESC]))                                               AS DiagDesc
      ,CONVERT(VARCHAR(16),L_OTHER_DIAG_DATE,120)                                      AS OtherDiagDate
      ,CONVERT(VARCHAR(50),(REF.N4_3_LATERALITY+'- '+[LAT_DESC]))                      AS Laterality
      ,CONVERT(VARCHAR(50),[N4_4_BASIS_DIAGNOSIS])                                     AS DiagBasis
      ,CONVERT(VARCHAR(50),[N4_5_HISTOLOGY])                                           AS Histology
      ,CONVERT(VARCHAR(50),(REF.N4_6_DIFFERENTIATION+'- '+[GRADE_DESC]))               AS Differentiation
      ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalTStage))                                            AS ClinicalTStage
	  ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalTCertainty))                                        AS ClinicalTCertainty
      ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalNStage))							 				   AS ClinicalNStage
	  ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalNCertainty))                                        AS ClinicalNCertainty
	  ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalMStage))                                            AS ClinicalMStage
	  ,CONVERT(VARCHAR(100),dbo.csvString(ClinicalMCertainty))                                        AS ClinicalMCertainty
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalTCertainty))                                    AS PathologicalTCertainty
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalTStage))                                        AS PathologicalTStage
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalNCertainty))                                    AS PathologicalNCertainty
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalNStage))                                        AS PathologicalNStage
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalMCertainty))                                    AS PathologicalMCertainty
	  ,CONVERT(VARCHAR(100),dbo.csvString(PathologicalMStage))                                        AS PathologicalMStage
      ,CONVERT(VARCHAR(10),L_TUMOUR_STATUS)                                            AS TumourStatus
	  ,CONVERT(VARCHAR(100),dbo.csvString(TS.[TUMOUR_DESC]))                                          AS TumourDesc
      ,CONVERT(VARCHAR(1000),dbo.csvString(L_NON_CANCER))                                              AS NonCancer
	  ,CONVERT(VARCHAR(100),dbo.csvString(L_RECURRENCE))                                              AS CRecurrence
	  ,CONVERT(VARCHAR(MAX),dbo.csvString(REF.L_COMMENTS))                                           AS RefComments
      ,CONVERT(VARCHAR(MAX),dbo.csvString(N16_7_DECISION_REASON))                                     AS DecisionReason
	  ,CONVERT(VARCHAR(2000),dbo.csvString(N16_8_TREATMENT_REASON))                                   AS TreatReason
      ,CONVERT(VARCHAR(10),RECURRENCE_CANCER_SITE_ID)                                  AS RecSiteID
      ,CONVERT(VARCHAR(10),TUMOUR_SITE_NEW)                                            AS NewTumourSite
      ,CONVERT(VARCHAR(10),[ACTION_ID])                                                AS ActionID
      ,CONVERT(VARCHAR(20),[SNOMed_CT])                                                AS SnomedCD
      ,CONVERT(VARCHAR(20),[SubsiteID])                                                AS SubSiteID
     
      
    FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblMAIN_REFERRALS] REF WITH (NOLOCK)
        INNER join   BH_RESEARCH.DBO.RDE_SCR_Demogrphics d
				ON REF.Patient_id=d.patientid
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblPRIORITY_TYPE] PT         --Priority type
				ON REF.N2_4_PRIORITY_TYPE=PT.[PRIORITY_CODE]
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblCA_STATUS] CA             --current Cancer status
				ON REF.N2_13_CANCER_STATUS=CA.[STATUS_CODE]
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].dbo.ltblCANCER_TYPE  TYP          --Lookup table for cancer type
				ON TYP.CANCER_TYPE_CODE = REF.N2_12_CANCER_TYPE
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblDIAGNOSIS] DIA            --Daiagnosis lookup table
				ON REF.N4_2_DIAGNOSIS_CODE=DIA.[DIAG_CODE]
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblLATERALITY] LA            --Laterality 
				ON REF.N4_3_LATERALITY=LA.[LAT_CODE]
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblDIFFERENTIATION] DIF      --Diffrentiation lookup table
				ON REF.N4_6_DIFFERENTIATION=DIF.[GRADE_CODE]
		LEFT OUTER JOIN [SCR_NEW].[CancerRegisterMerged].[dbo].[ltblTUMOUR_STATUS] TS         --Tumour status
				ON REF.L_TUMOUR_STATUS=TS.[TUMOUR_CODE]

Select @Row_Count=@Row_Count+@@ROWCOUNT


Set @ErrorPosition=670
Set @ErrorMessage='SCR Referrals data inserted into Temptable'
 
-----------------------------------------------------------------------------------------------------------
----SCR Tracking Comments
-----------------------------------------------------------------------------------------------------------


	INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_TrackingComments  
  SELECT 
       R.MRN 
	  ,[COM_ID]										    AS COM_ID
      ,C.[CARE_ID]  									AS CareID
      ,R.[NHS_Number]									AS NHS_Number
      ,CONVERT(VARCHAR(16),[DATE_TIME],120)				AS Date_Time
      ,dbo.csvString([COMMENTS])										AS Comments
     
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblTRACKING_COMMENTS] C 
  inner JOIN  BH_RESEARCH.DBO.RDE_SCR_Referrals R
  ON C.CARE_ID=R.CareID 

Select @Row_Count=@Row_Count+@@ROWCOUNT


Set @ErrorPosition=672
Set @ErrorMessage='SCR Tracking Comments data inserted into Temptable'



	INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_CarePlan
    SELECT 
	   [PLAN_ID]												AS PlanID
	  ,R.MRN
      ,CP.[CARE_ID]												AS CareID
	  ,R.[NHS_Number]											AS NHS_Number
      ,CONVERT(VARCHAR(16),[N5_2_MDT_DATE],120)					AS MDTDate
      ,[N5_5_CARE_INTENT]										AS CareIntent
      ,[N5_6_TREATMENT_TYPE_1]									AS TreatType
      ,[N5_10_WHO_STATUS]										AS WHOStatus
      ,[N_L28_PLAN_TYPE]										AS PlanType
      ,[L_NETWORK]												AS Network
      ,CONVERT(VARCHAR(16),[L_DATE_NETWORK_MEETING],120)		AS NetworkDate
      ,[L_CARE_PLAN_AGREED]										AS AgreedCarePlan
      ,[L_MDT_SITE]												AS MDTSite
      ,dbo.csvString([L_MDT_COMMENTS])											AS MDTComments
      ,dbo.csvString([L_NETWORK_FEEDBACK])										AS NetworkFeedback
      ,dbo.csvString([L_NETWORK_COMMENTS])										AS NetworkComments
     
     FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblMAIN_CARE_PLAN] CP WITH (NOLOCK)
  INNER JOIN  BH_RESEARCH.DBO.RDE_SCR_Referrals R
  ON CP.CARE_ID=R.CAREID 

Select @Row_Count=@Row_Count+@@ROWCOUNT

Set @ErrorPosition=674
Set @ErrorMessage='SCR care plan data inserted into Temptable'



	INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_DefTreatment
     SELECT 
	  [TREATMENT_ID]									AS TreatmentID
	  ,R.MRN
      ,DT.[CARE_ID]										AS CareID
	  ,R.[NHS_Number]									AS NHS_Number
      ,CONVERT(VARCHAR(16),[DECISION_DATE],120)			AS DecisionDate
      ,CONVERT(VARCHAR(16),[START_DATE],120)			AS StartDate
      ,dbo.csvString([TREATMENT])										AS Treatment
      ,[TREATMENT_EVENT]								AS TreatEvent
      ,[TREATMENT_SETTING]								AS TreatSetting
      ,[RT_PRIORITY]									AS TPriority
      ,[RT_INTENT]										AS Intent
      ,[TREAT_NO]										AS TreatNo
      ,[TREAT_ID]										AS TreatID
      --,[COMMENTS]										AS Comments
      --,[ALL_COMMENTS]									AS AllComments
	  ,dbo.csvString([CHEMO_RT])										AS ChemoRT
	  ,dbo.csvString([DELAY_COMMENTS])                                 AS DelayComments
	  ,dbo.csvString([DEPRECATED_21_01_COMMENTS])                      AS [DEPRECATEDComments]
	  ,dbo.csvString([DEPRECATED_21_01_ALL_COMMENTS])                  AS [DEPRECATEDAllComments]
	  ,dbo.csvString([ROOT_TCI_COMMENTS])								AS [RootTCIComments]
	  ,dbo.csvString([ROOT_DTT_DATE_COMMENTS])							AS [ROOT_DATE_COMMENTS]
    
    
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblDEFINITIVE_TREATMENT] DT WITH (NOLOCK)
   INNER JOIN  BH_RESEARCH.DBO.RDE_SCR_Referrals R
  ON DT.CARE_ID=R.CAREID 

Select @Row_Count=@Row_Count+@@ROWCOUNT

Set @ErrorPosition=676
Set @ErrorMessage='SCR Treatment data inserted into Temptable'

-----------------------------------------------------------------------------------------------------------
----SCR Definitive treatment details
-----------------------------------------------------------------------------------------------------------


	

INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_Diagnosis
SELECT [CARE_ID]															AS CareID
      ,D.MRN
      ,[Cancer Site]														AS CancerSite
      ,D.[NHS_Number]															AS NHS_Number
      ,[Hospital Number]													AS HospitalNumber
      ,dbo.csvString([Patient Status])														AS PatientStatus
      ,dbo.csvString([Tumour Status])														AS TumourStatus
	  ,dbo.csvString([New Tumour Site])													AS NewTumourSite
      ,CONVERT(VARCHAR(16),[Date of Diagnosis],120)							AS DiagDate
      ,CONVERT(VARCHAR(16),[Date Patient Informed],120)						AS DatePatInformed
      ,dbo.csvString([Primary Diagnosis (ICD)])											AS PrimDiagICD
      ,dbo.csvString([Primary Diagnosis (SNOMED)])											AS PrimDiagSnomed
      ,dbo.csvString([Secondary Diagnosis])												AS SecDiag
      ,dbo.csvString([Laterality])															AS Laterality
      ,dbo.csvString([Non-cancer details])													AS NonCancerdet
      ,dbo.csvString([Basis of Diagnosis])													AS DiagBasis
      ,dbo.csvString([Histology])															AS Histology
      ,dbo.csvString([Grade of Differentiation])											AS Differentiation
      ,dbo.csvString([Comments])															AS Comments
      ,CONVERT(VARCHAR(16),[Pathway End Date (Faster Diagnosis)],120)		AS PathwayEndFaster
      ,dbo.csvString([Pathway End Reason (Faster Diagnosis)])								AS PathwayEndReason
      ,dbo.csvString([Primary Cancer Site])												AS PrimCancerSite

  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[BIvwDiagnosis] diag WITH (NOLOCK)
  join  BH_RESEARCH.DBO.RDE_SCR_Demogrphics D
  on Diag.[NHS Number]=d.NHS_Number

Select @Row_Count=@Row_Count+@@ROWCOUNT

Set @ErrorPosition=678
Set @ErrorMessage='SCR Diagnosis data inserted into Temptable'





	INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_Investigations  
SELECT [CARE_ID]												AS CareID
      ,D.MRN
      ,[Cancer Site]											AS CancerSite
      ,D.[NHS_Number]												AS NHS_Number
      ,[Hospital Number]										AS HospitalNumber
      ,dbo.csvString([Diagnostic Investigation])								AS DiagInvestigation
      ,CONVERT(VARCHAR(16),[Date Requested],120)				AS ReqDate
      ,CONVERT(VARCHAR(16),[Date Performed],120)				AS DatePerformed
      ,CONVERT(VARCHAR(16),[Reported Date],120)					AS DateReported
      ,dbo.csvString([Biopsy Taken])											AS BiopsyTaken
      ,dbo.csvString([Outcome])											AS Outcome
      ,dbo.csvString([Comments])												AS Comments
      ,[Imaging Code(NICIP)]									AS NICIPCode
      ,[Imaging Code (SNOMed CT)]								AS SnomedCT
      ,dbo.csvString([Anatomical Site 1])										AS AnotomicalSite
      ,dbo.csvString([Anatomical Side])										AS AnatomicalSide
      ,dbo.csvString([Imaging Report Text])									AS ImagingReport
      ,dbo.csvString([Staging Laparoscopy Performed])							AS StagingLaproscopyPerformed
    
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[BIvwInvestigations] inv
  join  BH_RESEARCH.DBO.RDE_SCR_Demogrphics D
  on inv.[NHS Number]=d.NHS_Number

Select @Row_Count=@Row_Count+@@ROWCOUNT


Set @ErrorPosition=680
Set @ErrorMessage='SCR Investigations data inserted into Temptable'





	INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_Pathology
SELECT [PATHOLOGY_ID]								AS PathologyID
	  ,R.MRN
      ,p.[CARE_ID]									AS CareID
	  ,R.NHS_Number									AS NHS_Number
      ,[N8_1_PATHOLOGY_TYPE]						AS PathologyType
      ,CONVERT(VARCHAR(16),[N8_3_RESULT_DATE],120)	AS ResultDate
      ,[N8_13_EXCISION_MARGINS]						AS ExcisionMargins
      ,[N8_14_NODES]								AS Nodes
      ,[N8_15_POSITIVE_NODES]						AS PositiveNodes
      ,[N8_16_PATH_T_STAGE]							AS PathTstage
      ,[N8_17_PATH_N_STAGE]							AS PathNstage
      ,[N8_18_PATH_M_STAGE]							AS PathMstage
      ,dbo.csvString(p.[L_COMMENTS])								AS Comments
      ,CONVERT(VARCHAR(16),[SAMPLE_DATE],120)       AS SampleDate
      ,dbo.csvString([L_PATHOLOGY_TEXT])							AS PathologyReport
      ,[SNOMedCT]									AS SNomedCT
      ,[SNOMEDDiagnosisID]							AS SNomedID
	  	
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblMAIN_PATHOLOGY] P WITH (NOLOCK)
  join  BH_RESEARCH.DBO.RDE_SCR_Referrals R
  on P.CARE_ID=R.CareID
  
  
Select @Row_Count=@Row_Count+@@ROWCOUNT


Set @ErrorPosition=682
Set @ErrorMessage='SCR Pathology data inserted into Temptable'


	
INSERT INTO  BH_RESEARCH.DBO.RDE_SCR_Imaging
  SELECT [IMAGE_ID]									AS ImageID
      ,R.MRN
      ,i.[CARE_ID]									AS CareID
	  ,R.NHS_Number									AS NHS_Number
      ,CONVERT(VARCHAR(16),[L_REQUEST_DATE],120)	AS RequestDate
      ,CONVERT(VARCHAR(16),[N3_2_IMAGING_DATE],120) AS ImagingDate
      ,CONVERT(VARCHAR(16),[L_REPORT_DATE],120)		AS ReportDate
      ,[N3_4_ANATOMICAL_SITE]						AS AnatomicalSite
      ,[L_ANATOMICAL_SIDE_CODE]						AS AnatomicalSide
      ,dbo.csvString([L_IM_RESULT])								AS ImageResult
      ,[L_CONTRAST]									AS Contrast
      ,dbo.csvString([L_RESULTS])									AS Result
      ,dbo.csvString([L_IMAGING_REPORT_TEXT])						AS Report
      ,[UGI_STAGING_PROCEDURE]						AS StagingProc
      ,[L_IMAGING_CODE]								AS ImageCD
      
  FROM [SCR_NEW].[CancerRegisterMerged].[dbo].[tblMAIN_IMAGING] I WITH (NOLOCK)
  join  BH_RESEARCH.DBO.RDE_SCR_Referrals R
  on I.CARE_ID=R.CareID


Select @Row_Count=@Row_Count+@@ROWCOUNT

Set @ErrorPosition=684
Set @ErrorMessage='SCR Radiology data inserted into Temptable'

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'SCR Data', @StartDate, @EndDate,@time,@Row_Count) 
	END


---------------------------------------------------------------------------------------------------------
	

	--STUDY PARTICIPATION
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=700
SET @ErrorMessage='Powertrials participation'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MILL_Powertrials', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MILL_Powertrials

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MILL_Powertrials (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		Study_Code							VARCHAR(16),
		Study_Name							VARCHAR(500),
		Study_Participant_ID				VARCHAR(40),
		On_Study_Date						VARCHAR(30),
		Off_Study_Date						VARCHAR(30),
		Off_Study_Code						VARCHAR(40),
		Off_Study_Reason					VARCHAR(200),
		Off_Study_Comment					VARCHAR(MAX),
		rn									INTEGER
     )

SET @ErrorPosition=710
SET @ErrorMessage='Powertrials Participant temp table created'

IF @PowertrialsPart=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_MILL_Powertrials
        SELECT DISTINCT * FROM (SELECT
	CONVERT(VARCHAR(14),[RES].[PERSON_ID])                                     AS PERSONID,
	CONVERT(VARCHAR(20), [PDEM].MRN)									AS MRN,
	CONVERT(VARCHAR(20), [PDEM].[NHS_Number])								AS NHS_Number,
	CONVERT(VARCHAR(16),[RES].[PROT_MASTER_ID])                                     AS Study_Code,
	CONVERT(VARCHAR(500),dbo.csvString([PRIMARY_MNEMONIC]))                                     AS Study_Name,
	CONVERT(VARCHAR(40),[PROT_ACCESSION_NBR])                                     AS Study_Participant_ID,
	CONVERT(VARCHAR(30),[ON_STUDY_DT_TM],120)                     AS On_Study_Date,
	CONVERT(VARCHAR(30),[OFF_STUDY_DT_TM],120)                     AS Off_Study_Date,
	CONVERT(VARCHAR(40),[REMOVAL_REASON_CD])                                     AS Off_Study_Code,
	CONVERT(VARCHAR(200),dbo.csvString([CODE_DESC_TXT]))                                     AS Off_Study_Reason,
	CONVERT(VARCHAR(MAX),dbo.csvString([REMOVAL_REASON_DESC]))                                     AS Off_Study_Comment,
    ROW_NUMBER() OVER (PARTITION BY RES.PROT_MASTER_ID, RES.PERSON_ID ORDER BY RES.BEG_EFFECTIVE_DT_TM DESC) rn

        FROM [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_PT_PROT_REG] RES 
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] LOOK 
		ON CAST(RES.REMOVAL_REASON_CD AS VARCHAR) = CAST(LOOK.code_value_cd AS VARCHAR) 
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_PT_PROT_MASTER] STUDYM
		ON CAST(RES.PROT_MASTER_ID AS VARCHAR) = CAST(STUDYM.PROT_MASTER_ID AS VARCHAR)
		RIGHT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] PDEM
		ON CAST(RES.PERSON_ID AS VARCHAR) = CAST(PDEM.PERSON_ID AS VARCHAR)
--		WHERE CAST(RES.PROT_MASTER_ID AS VARCHAR) = '613882' -- Tag for Barts BioResource Study
        ) x
WHERE   x.rn = 1

Select @Row_Count=@@ROWCOUNT

ALTER TABLE  BH_RESEARCH.DBO.RDE_MILL_Powertrials DROP COLUMN rn


Set @ErrorPosition=720
Set @ErrorMessage='Powertrials Participation details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'PowertrialsParticipant', @StartDate, @EndDate,@time,@Row_Count) 
	END




---------------------------------------------------------------------------------------------------------
	

	--ALIASES
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=750
SET @ErrorMessage='Aliases'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Aliases', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Aliases

	CREATE TABLE  BH_RESEARCH.DBO.RDE_Aliases (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		CodeType							VARCHAR(16),
		Code								VARCHAR(20),
		IssueDate							VARCHAR(30)
     )

SET @ErrorPosition=760
SET @ErrorMessage='Aliases temp table created'

IF @Aliases=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_Aliases
        SELECT 
	CONVERT(VARCHAR(14),[PAT].[PERSON_ID])                                     AS PERSONID,
	CONVERT(VARCHAR(20), [PAT].MRN)									AS MRN,
	CONVERT(VARCHAR(20), [PAT].[NHS_Number])								AS NHS_Number,
	CASE PERSON_ALIAS_TYPE_CD WHEN 18 THEN 'NHS_Number' WHEN 10 THEN 'MRN' ELSE NULL END AS CodeType,
	CONVERT(VARCHAR(20), ALIAS) AS Code,
	CONVERT(VARCHAR(30), [AL].BEG_EFFECTIVE_DT_TM) AS IssueDate
        FROM [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_PERSON_ALIAS] AL
		LEFT JOIN [BH_RESEARCH].[dbo].[RDE_Patient_Demographics] PAT
		ON CAST(AL.PERSON_ID AS VARCHAR) = CAST(PAT.PERSON_ID AS VARCHAR)
        WHERE ALIAS != PAT.MRN AND ALIAS != PAT.NHS_Number 
		AND (PERSON_ALIAS_TYPE_CD = 18 OR PERSON_ALIAS_TYPE_CD = 10)

Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=780
Set @ErrorMessage='Alias details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Aliases', @StartDate, @EndDate,@time,@Row_Count) 
	END







---------------------------------------------------------------------------------------------------------
	

	--Critical Care
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=850
SET @ErrorMessage='CritActivity'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_CritActivity', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_CritActivity

	CREATE TABLE  BH_RESEARCH.DBO.RDE_CritActivity (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		Period_ID							VARCHAR(40),
		CDS_APC_ID							VARCHAR(100),
		ActivityDate						VARCHAR(30),
		ActivityCode						integer,
		ActivityDesc						VARCHAR(1000)
     )

SET @ErrorPosition=860
SET @ErrorMessage='CritActivity temp table created'

IF @CritCare=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_CritActivity
        SELECT 
	CONVERT(VARCHAR(14),[DEM].[PERSON_ID])                                     AS PERSONID,
	CONVERT(VARCHAR(20), [DEM].MRN)									AS MRN,
	CONVERT(VARCHAR(20), [DEM].[NHS_Number])								AS NHS_Number,
	CONVERT(VARCHAR(40), [CC_Period_Local_Id])								AS Period_ID,
	CONVERT(VARCHAR(100), [CDS_APC_ID])								AS CDS_APC_ID,
	CONVERT(VARCHAR(30), [Activity_Date])							AS ActivityDate,
	Activity_Code AS ActivityCode,
	CONVERT(VARCHAR(1000), dbo.csvString([ref].[NHS_DATA_DICT_DESCRIPTION_TXT])) AS ActivityDesc
 FROM [BH_DATAWAREHOUSE].[dbo].[CRIT_CARE_activity] a
left join  [BH_DATAWAREHOUSE].[dbo].[PI_LKP_NHS_DATA_DICT_REF] ref with (nolock) on a.Activity_Code = ref.NHS_DATA_DICT_NHS_CD_ALIAS
AND ref.[NHS_DATA_DICT_ELEMENT_NAME_KEY_TXT]='CRITICALCAREACTIVITY'
INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics DEM       
ON DEM.MRN=a.mrn


Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=880
Set @ErrorMessage='CritActivity details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'CritActivity', @StartDate, @EndDate,@time,@Row_Count) 
	END








	
SET @ErrorPosition=900
SET @ErrorMessage='CritPeriod'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_CritPeriod', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_CritPeriod

	CREATE TABLE  BH_RESEARCH.DBO.RDE_CritPeriod (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		Period_ID							VARCHAR(40),
		StartDate							VARCHAR(30),
		DischargeDate						VARCHAR(30),
		Level_2_Days						INTEGER,
		Level_3_Days						INTEGER,
		Dischage_Dest_CD					INTEGER,
		Discharge_destination				VARCHAR(MAX),
		Adv_Cardio_Days						INTEGER,
		Basic_Cardio_Days					INTEGER,
		Adv_Resp_Days						INTEGER,
		Basic_Resp_Days						INTEGER,
		Renal_Days							INTEGER,
		Neuro_Days							INTEGER,
		Gastro_Days							INTEGER,
		Derm_Days							INTEGER,
		Liver_Days							INTEGER,
		No_Organ_Systems					INTEGER
     )

SET @ErrorPosition=960
SET @ErrorMessage='CritPeriod temp table created'

IF @CritCare=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_CritPeriod
        SELECT 
	CONVERT(VARCHAR(14),[DEM].[PERSON_ID])                                     AS PERSONID,
	CONVERT(VARCHAR(20), [DEM].MRN)									AS MRN,
	CONVERT(VARCHAR(20), [DEM].[NHS_Number])								AS NHS_Number,
	CONVERT(VARCHAR(40), [CC_Period_Local_Id])								AS Period_ID,
	CONVERT(VARCHAR(30), [CC_Period_Start_Dt_Tm])							AS StartDate,
	CONVERT(VARCHAR(30), [CC_Period_Disch_Dt_Tm])							AS DischargeDate,
	[CC_Level2_Days]															AS Level_2_Days,
	[CC_Level3_Days]														AS Level_3_Days,
	[CC_Disch_Dest_Cd]														AS Discharge_Dest_CD,
	CONVERT(VARCHAR(MAX), dbo.csvString([ref].[NHS_DATA_DICT_DESCRIPTION_TXT]))		AS Discharge_destination,
	[CC_Adv_Cardio_Days]												AS Adv_Cardio_Days,
	[CC_Basic_Cardio_Days]												AS Basic_Cardio_Days,
	[CC_Adv_Resp_Days]													AS Adv_Resp_Days,
	[CC_Basic_Resp_Days]												AS Basic_Resp_Days,
	[CC_Renal_Days]														AS Renal_Days,
	[CC_Neuro_Days]														AS Neuro_Days,
	[CC_Gastro_Days]													AS Gastro_Days,
	[CC_Derm_Days]														AS Derm_Days,
	[CC_Liver_Days]														AS Liver_Days,
	[CC_No_Organ_Systems]												AS No_Organ_Systems


FROM [BH_DATAWAREHOUSE].[dbo].[CRIT_CARE_period] a
left join [BH_DATAWAREHOUSE].[dbo].[PI_LKP_NHS_DATA_DICT_REF] ref with (nolock) on a.CC_Disch_Dest_Cd = ref.NHS_DATA_DICT_NHS_CD_ALIAS
AND ref.[NHS_DATA_DICT_ELEMENT_NAME_KEY_TXT]='CRITICALCAREDISCHDESTINATION'
INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics DEM       
ON DEM.MRN=a.mrn


Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=980
Set @ErrorMessage='CritPeriod details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'CritPeriod', @StartDate, @EndDate,@time,@Row_Count) 
	END





SET @ErrorPosition=1000
SET @ErrorMessage='CritOPCS'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_CritOPCS', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_CritOPCS

	CREATE TABLE  BH_RESEARCH.DBO.RDE_CritOPCS (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		Period_ID							VARCHAR(40),
		ProcDate							VARCHAR(30),
		ProcCode						    VARCHAR(30)
     )

SET @ErrorPosition=1060
SET @ErrorMessage='CritOPCS temp table created'

IF @CritCare=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_CritOPCS
        SELECT DISTINCT
	CONVERT(VARCHAR(14),[DEM].[PERSON_ID])                                     AS PERSONID,
	CONVERT(VARCHAR(20), [DEM].MRN)									AS MRN,
	CONVERT(VARCHAR(20), [DEM].[NHS_Number])								AS NHS_Number,
	CONVERT(VARCHAR(40), [CC_Period_Local_Id])								AS Period_ID,
	CONVERT(VARCHAR(30), [OPCS_Proc_Dt])							AS StartDate,
	CONVERT(VARCHAR(30), [OPCS_Proc_Code])							AS ProcCode
FROM [BH_DATAWAREHOUSE].[dbo].[CRIT_CARE_OPCS] a
INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics DEM       
ON DEM.MRN=a.mrn


Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=1080
Set @ErrorMessage='CritOPCS details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'CritOPCS', @StartDate, @EndDate,@time,@Row_Count) 
	END




---------------------------------------------------------------------------------------------------------
	

	--Measurements
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=1100
SET @ErrorMessage='Measurements'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_Measurements', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_Measurements

	CREATE TABLE  BH_RESEARCH.DBO.RDE_Measurements (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		SystemLookup						VARCHAR(200),
		ClinicalSignificanceDate			VARCHAR(30),
		ResultNumeric						BIT,
		EventResult							VARCHAR(100),
		UnitsCode							INTEGER,
		UnitsDesc							VARCHAR(100),
		NormalCode							INTEGER,
		NormalDesc							VARCHAR(100),
		LowValue							VARCHAR(100),
		HighValue							VARCHAR(100),
		EventText 							VARCHAR(100),
		EventType							VARCHAR(100),
		EventParent							VARCHAR(100)
	
	 )

SET @ErrorPosition=1150
SET @ErrorMessage='Measurements temp table created'

IF @CritCare=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_Measurements
        SELECT 
			CONVERT(VARCHAR(14),[cce].[PERSON_ID])                                     AS PERSONID,
			Enc.MRN,
		    Enc.NHS_Number																AS NHS_Number, 
			CONVERT(VARCHAR(200), srf.code_desc_txt) 									AS SystemLookup,
  			CONVERT(VARCHAR(30), cce.CLIN_SIGNIFICANCE_DT_TM)							AS ClinicalSignificanceDate, 
			CASE WHEN ISNUMERIC(cce.EVENT_RESULT_TXT) <> 1 THEN 0 ELSE 1 END			AS ResultNumeric,
			CONVERT(VARCHAR(100), cce.EVENT_RESULT_TXT)									AS EventResult,  
			cce.EVENT_RESULT_UNITS_CD													AS UnitsCode, 
			CONVERT(VARCHAR(100), urf.code_desc_txt) 									AS UnitsDesc, 
			cce.NORMALCY_CD															    AS NormalCode, 
			CONVERT(VARCHAR(100), nrf.code_desc_txt)						 			AS normalDesc,
  			CONVERT(VARCHAR(100), cce.NORMAL_VALUE_LOW_TXT)								AS LowValue,
			CONVERT(VARCHAR(100), cce.NORMAL_VALUE_HIGH_TXT)							AS HighValue, 
			CONVERT(VARCHAR(100), cce.EVENT_TAG_TXT)									AS EventText, 
			CONVERT(VARCHAR(100), ref.code_desc_txt)									AS EventType, 
			CONVERT(VARCHAR(100), TESTnm.code_desc_txt) 								AS EventParent
  FROM BH_RESEARCH.DBO.TempCE cce WITH (NOLOCK)
            LEFT JOIN  BH_RESEARCH.DBO.RDE_Encounter ENC with (nolock)
                ON ENC.ENCNTR_ID = cce.ENCNTR_ID
  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] ref WITH (NOLOCK) on cce.event_cd = ref.CODE_VALUE_CD
  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] urf WITH (NOLOCK) on cce.event_result_units_cd  = urf.CODE_VALUE_CD
  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] nrf WITH (NOLOCK) on cce.normalcy_cd  = nrf.CODE_VALUE_CD
  LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] srf WITH (NOLOCK) on cce.contributor_system_cd  = srf.CODE_VALUE_CD
  LEFT OUTER JOIN BH_RESEARCH.DBO.TempCE  pev with (nolock) ON cce.PARENT_EVENT_ID=pev.EVENT_ID
  LEFT OUTER JOIN  [BH_DATAWAREHOUSE].[dbo]. PI_LKP_CDE_CODE_VALUE_REF TESTnm with (nolock) ON pev.EVENT_CD = TESTnm.CODE_VALUE_CD	
   WHERE (cce.EVENT_RESULT_UNITS_CD > 0
	OR (
 		cce.EVENT_RESULT_NBR = '0' AND cce.EVENT_RESULT_TXT != '0' AND ISNUMERIC(cce.EVENT_RESULT_TXT) != 1
	    AND cce.EVENT_RESULT_STATUS_CD = 25 AND cce.ORDER_ID != '0'
		AND cce.EVENT_RESULT_TXT NOT LIKE '%Comment%'
	)	)
	AND 
     ((cce.CONTRIBUTOR_SYSTEM_CD != '6378204' AND cce.CONTRIBUTOR_SYSTEM_CD != '6141416') OR cce.CONTRIBUTOR_SYSTEM_CD IS NULL)



Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=1180
Set @ErrorMessage='Measurement details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Measurement', @StartDate, @EndDate,@time,@Row_Count) 
	END





---------------------------------------------------------------------------------------------------------
	

	--Emergency Department
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=1200
SET @ErrorMessage='Emergency Department'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_EmergencyD', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_EmergencyD

	CREATE TABLE  BH_RESEARCH.DBO.RDE_EmergencyD (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		Arrival_Dt_Tm						VARCHAR(30),
		Departure_Dt_Tm						VARCHAR(30),
		Dischage_Status_CD					VARCHAR(30),
		Discharge_Status_Desc				VARCHAR(1000),
		Discharge_Dest_CD					VARCHAR(30),
		Discharge_Dest_Desc					VARCHAR(1000),
		Diag_Code							VARCHAR(30),
		SNOMED_CD							VARCHAR(30),
		SNOMED_Desc							VARCHAR(1000)
	
	 )

SET @ErrorPosition=1250
SET @ErrorMessage='Emergency temp table created'

IF @Emergency=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_EmergencyD
        SELECT 
		CONVERT(VARCHAR(14), [DEM].[PERSON_ID])											AS PERSONID,
		DEM.MRN																			AS MRN,	
		DEM.NHS_NUMBER																	AS NHS_NUMBER,
		CONVERT(VARCHAR(30), [AEA].[ARRIVAL_DT_TM])										AS Arrival_Dt_Tm,
		CONVERT(VARCHAR(30), [AEA].[DEPARTURE_TM])										AS Departure_Dt_Tm,
		CONVERT(VARCHAR(30), [AEA].[DISCHARGE_STATUS_CD])								AS Dischage_Status_CD,
		CONVERT(VARCHAR(1000), dbo.csvString([D].[DISCHARGE_STATUS_DESC]))								AS Discharge_Status_Desc,
		CONVERT(VARCHAR(30), [AEA].[Discharge_destination_Cd])									AS Discharge_Dest_CD,
		CONVERT(VARCHAR(1000), dbo.csvString([E].[DISCHARGE_DESTINATION_DESC]))								AS Discharge_Dest_Desc,
		CONVERT(VARCHAR(30), [DIA].[DIAG_CD])											AS Diag_Code,
		CONVERT(VARCHAR(30), [REF].[Diagnosis_Snomed_Cd])											AS SNOMED_CD,
		CONVERT(VARCHAR(1000), dbo.csvString([REF].[Diagnosis_Snomed_Desc]))										AS SNOMED_Desc

		FROM [BH_DATAWAREHOUSE].[dbo].[CDS_AEA] AEA 
		INNER JOIN  BH_RESEARCH.DBO.RDE_Patient_Demographics DEM     ON DEM.MRN=AEA.mrn
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_ECD_REF_DISCHARGE_DESTINATION] e with (nolock) on AEA.Discharge_Destination_Cd = e.Discharge_Destination_Snomed_Cd
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_ECD_MAP_ATT_DISP_DISCH_STAT] d with (nolock) on AEA.Discharge_Status_Cd = d.Discharge_Status_ECD_Cd
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_SITE] ts with (nolock) on AEA.treatment_site_code = ts.site_cd
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[CDS_AEA_DIAG] DIA with (nolock) on AEA.cds_aea_id = DIA.cds_aea_id
		LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[LKP_CDS_ECD_REF_DIAGNOSIS] REF with (nolock) on DIA.Diag_ECD_Cd = ref.diagnosis_Snomed_cd
		

		



Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=1280
Set @ErrorMessage='Emergency details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'Emergency', @StartDate, @EndDate,@time,@Row_Count) 
	END








---------------------------------------------------------------------------------------------------------
	

	--Medicines Administed
---------------------------------------------------------------------------------------------------

SET @ErrorPosition=1300
SET @ErrorMessage='Medicines Administered'

IF OBJECT_ID(N'BH_RESEARCH.DBO.RDE_MedAdmin', N'U') IS NOT NULL DROP TABLE  BH_RESEARCH.DBO.RDE_MedAdmin

	CREATE TABLE  BH_RESEARCH.DBO.RDE_MedAdmin (
		PERSONID							VARCHAR(14),
		MRN									VARCHAR(20),
		NHS_NUMBER							VARCHAR(20),
		EVENT_ID							VARCHAR(20),
		ORDER_ID							VARCHAR(20),
		EVENT_TYPE							VARCHAR(1000),
		ORDER_SYNONYM_ID					VARCHAR(20),
		ORDER_MULTUM						VARCHAR(10),
		Order_Desc							VARCHAR(1000),
		Order_Detail						VARCHAR(MAX),
		ORDER_STRENGTH						FLOAT,
		ORDER_STRENGTH_UNIT					VARCHAR(1000),
		ORDER_VOLUME						FLOAT,
		ORDER_VOLUME_UNIT					VARCHAR(1000),
		ORDER_ACTION_SEQUENCE				INT,
		ADMIN_ROUTE							VARCHAR(1000),
		ADMIN_METHOD						VARCHAR(1000),
		ADMIN_INITIAL_DOSAGE				FLOAT,
		ADMIN_DOSAGE 						FLOAT,
		ADMIN_DOSAGE_UNIT					VARCHAR(1000),
		ADMIN_INITIAL_VOLUME				FLOAT,
		ADMIN_TOTAL_INTAKE_VOLUME			FLOAT,
		ADMIN_DILUENT_TYPE					VARCHAR(1000),
		ADMIN_INFUSION_RATE					FLOAT,
		ADMIN_INFUSION_UNIT					VARCHAR(1000),
		ADMIN_INFUSION_TIME					VARCHAR(1000),
		ADMIN_MEDICATION_FORM				VARCHAR(1000),
		ADMIN_STRENGTH						FLOAT,
		ADMIN_STRENGTH_UNIT					VARCHAR(1000),
		ADMIN_INFUSED_VOLUME			FLOAT,
		ADMIN_INFUSED_VOLUME_UNIT			VARCHAR(1000),
		ADMIN_REMAINING_VOLUME				FLOAT,
		ADMIN_REMAINING_VOLUME_UNIT			VARCHAR(1000),
		ADMIN_IMMUNIZATION_TYPE				VARCHAR(1000),
		ADMIN_REFUSAL 						VARCHAR(1000),
		ADMIN_IV_EVENT 						VARCHAR(1000),
		ADMIN_SYNONYM_ID					VARCHAR(20),
		ADMIN_MULTUM						VARCHAR(10),
		ADMIN_DESC							VARCHAR(1000),
		ADMINISTRATOR						VARCHAR(1000),
		EVENT_DESC							VARCHAR(1000),
		EVENT_DATE							VARCHAR(30),
		ADMIN_START_DATE					VARCHAR(30),
		ADMIN_END_DATE						VARCHAR(30)
	 )

SET @ErrorPosition=1350
SET @ErrorMessage='Med Admin temp table created'

IF @PharmacyOrders=1
   BEGIN

  SELECT @StartDate =GETDATE()

     INSERT INTO  BH_RESEARCH.DBO.RDE_MedAdmin
        SELECT 
		CONVERT(VARCHAR(14),[cce].[PERSON_ID])                                     				AS PERSONID,
		Enc.MRN,
		Enc.NHS_Number																			AS NHS_Number, 
        CONVERT(VARCHAR(20), MAE.EVENT_ID)														AS EVENT_ID, 
		CONVERT(VARCHAR(20), MAE.ORDER_ID)														AS ORDER_ID, 
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), EVENT_TYPE_CD)))) AS EVENT_TYPE,
		CONVERT(VARCHAR(20), OI.SYNONYM_ID) 													AS ORDER_SYNONYM_ID, 
		RIGHT(OCAT.CKI, 6) 																		AS ORDER_MULTUM, 
		CONVERT(VARCHAR(1000), dbo.csvString(ORDER_MNEMONIC))									AS Order_Desc,
		CONVERT(VARCHAR(MAX), dbo.csvString(ORDER_DETAIL_DISPLAY_LINE))							AS Order_Detail,
		OI.STRENGTH 																			AS ORDER_STRENGTH,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), OI.STRENGTH_UNIT)))) AS ORDER_STRENGTH_UNIT,
		OI.VOLUME 																				AS ORDER_VOLUME, 
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), OI.VOLUME_UNIT)))) AS ORDER_VOLUME_UNIT,
		OI.ACTION_SEQUENCE 																		AS ORDER_ACTION_SEQUENCE,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.ADMIN_ROUTE_CD)))) AS ADMIN_ROUTE,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.ADMIN_METHOD_CD)))) AS ADMIN_METHOD,
		MR.INITIAL_DOSAGE 																		AS ADMIN_INITIAL_DOSAGE, 
		MR.ADMIN_DOSAGE, 
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.DOSAGE_UNIT_CD)))) AS ADMIN_DOSAGE_UNIT,
 		MR.INITIAL_VOLUME 																		AS ADMIN_INITIAL_VOLUME,
 		MR.TOTAL_INTAKE_VOLUME 																	AS ADMIN_TOTAL_INTAKE_VOLUME,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.DILUENT_TYPE_CD)))) AS ADMIN_DILUENT_TYPE,
		MR.INFUSION_RATE 																		AS ADMIN_INFUSION_RATE,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.INFUSION_UNIT_CD)))) AS ADMIN_INFUSION_UNIT,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.INFUSION_TIME_CD)))) AS ADMIN_INFUSION_TIME,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.MEDICATION_FORM_CD)))) AS ADMIN_MEDICATION_FORM,
		MR.ADMIN_STRENGTH,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.ADMIN_STRENGTH_UNIT_CD)))) AS ADMIN_STRENGTH_UNIT,
		MR.INFUSED_VOLUME 																		AS ADMIN_INFUSED_VOLUME,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.INFUSED_VOLUME_UNIT_CD)))) AS ADMIN_INFUSED_VOLUME_UNIT,
		MR.REMAINING_VOLUME 																	AS ADMIN_REMAINING_VOLUME,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.REMAINING_VOLUME_UNIT_CD)))) AS ADMIN_REMAINING_VOLUME_UNIT,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.IMMUNIZATION_TYPE_CD)))) AS ADMIN_IMMUNIZATION_TYPE,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.REFUSAL_CD)))) AS ADMIN_REFUSAL,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MR.IV_EVENT_CD)))) AS ADMIN_IV_EVENT,
		CONVERT(VARCHAR(20), MR.SYNONYM_ID)														AS ADMIN_SYNONYM_ID, 
		RIGHT(ACAT.CKI, 6) 																		AS ADMIN_MULTUM, 
		CONVERT(VARCHAR(1000), dbo.csvString(ASYN.MNEMONIC))									AS Admin_Desc,
		CONVERT(VARCHAR(1000), dbo.csvString((SELECT TOP(1) CODE_DISP_TXT FROM [BH_DATAWAREHOUSE].[dbo].[PI_LKP_CDE_CODE_VALUE_REF] with (nolock) WHERE CONVERT(VARCHAR(20), CODE_VALUE_CD) = CONVERT(VARCHAR(20), MAE.POSITION_CD)))) AS ADMINISTRATOR,
		CONVERT(VARCHAR(1000), dbo.csvString(cce.EVENT_TAG_TXT))								AS EVENT_DESC,
	 	CONVERT(VARCHAR(30), cce.CLIN_SIGNIFICANCE_DT_TM) 										AS EVENT_DATE, 
	 	CONVERT(VARCHAR(30), ADMIN_START_DT_TM) 												AS ADMIN_START_DATE, 
		CONVERT(VARCHAR(30), ADMIN_END_DT_TM) 													AS ADMIN_END_DATE

		 FROM BH_RESEARCH.DBO.TempCE  cce 
		 INNER JOIN BH_DATAWAREHOUSE.dbo.MILL_DIR_MED_ADMIN_EVENT MAE with (nolock)
		 ON cce.EVENT_ID = MAE.EVENT_ID
            LEFT JOIN  BH_RESEARCH.DBO.RDE_Encounter ENC with (nolock)
                ON ENC.ENCNTR_ID = cce.ENCNTR_ID
	LEFT JOIN (SELECT *, row_number() over (partition by EVENT_ID order by VALID_FROM_DT_TM DESC) AS RN FROM [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_CE_MED_RESULT] with (nolock)) MR 
		ON (MAE.EVENT_ID = MR.EVENT_ID AND MR.RN = 1)
	LEFT JOIN (SELECT *, row_number() over (partition by ORDER_ID order by ACTION_SEQUENCE ASC) AS RN FROM [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ORDER_INGREDIENT] with (nolock)) OI 
		ON (MAE.TEMPLATE_ORDER_ID = OI.ORDER_ID AND OI.RN = 1)
	LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ORDER_CATALOG_SYNONYM] OSYN ON OSYN.SYNONYM_ID = OI.SYNONYM_ID
	LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ORDER_CATALOG_SYNONYM] ASYN ON ASYN.SYNONYM_ID = MR.SYNONYM_ID
	LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ORDER_CATALOG] OCAT ON OCAT.CATALOG_CD = OSYN.CATALOG_CD
	LEFT JOIN [BH_DATAWAREHOUSE].[dbo].[MILL_DIR_ORDER_CATALOG] ACAT ON ACAT.CATALOG_CD = ASYN.CATALOG_CD
	WHERE MAE.EVENT_ID > 0
		


Select @Row_Count=@@ROWCOUNT


Set @ErrorPosition=1380
Set @ErrorMessage='MedAdmin details inserted into Temptable'
    
SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'MedAdmin', @StartDate, @EndDate,@time,@Row_Count) 
	END



if @Filetype ='text' 

begin
SELECT @StartDate=GETDATE()




if @Anonymous = 1
BEGIN

DROP INDEX IF EXISTS indx_Patho ON  BH_RESEARCH.DBO.RDE_Pathology,
indx_Aria ON  BH_RESEARCH.DBO.RDE_ARIAPharmacy,
indx_PF ON  BH_RESEARCH.DBO.RDE_Powerforms,
indx_Rdio ON  BH_RESEARCH.DBO.RDE_Radiology,
indx_FHist ON  BH_RESEARCH.DBO.RDE_FamilyHistory,
indx_BLOB ON  BH_RESEARCH.DBO.RDE_BLOBDataset,
indx_Proc ON  BH_RESEARCH.DBO.RDE_PC_PROCEDURES,
indx_Diag ON  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS,
indx_Prob ON  BH_RESEARCH.DBO.RDE_PC_PROBLEMS,
indx_MB ON  BH_RESEARCH.DBO.RDE_MSDS_Booking,
indx_CC ON  BH_RESEARCH.DBO.RDE_MSDS_CareContact,
indx_Lab ON  BH_RESEARCH.DBO.RDE_MSDS_Delivery,
indx_MSD ON  BH_RESEARCH.DBO.RDE_MSDS_Diagnosis,
indx_PO ON  BH_RESEARCH.DBO.RDE_PharmacyOrders,
indx_MSD ON  BH_RESEARCH.DBO.RDE_MAT_NNU_Exam,
indx_MSD ON  BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes,
indx_MSD ON  BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS,
indx_Allergy ON  BH_RESEARCH.DBO.RDE_AllergyDetails,
indx_iqemo ON  BH_RESEARCH.dbo.RDE_iQEMO,

indx_Patho ON BH_RESEARCH.DBO.RDE_RAW_Pathology;

ALTER TABLE BH_RESEARCH.dbo.RDE_APC_DIAGNOSIS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_APC_DIAGNOSIS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_APC_DIAGNOSIS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_APC_OPCS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_APC_OPCS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_APC_OPCS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Exam DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Exam DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Exam DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.DBO.RDE_MAT_NNU_Episodes DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MAT_NNU_NCCMDS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_iQEMO DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_iQEMO DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_iQEMO DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_OP_DIAGNOSIS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_OP_DIAGNOSIS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_OP_DIAGNOSIS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_OPA_OPCS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_OPA_OPCS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_OPA_OPCS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.DBO.RDE_RAW_Pathology DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.DBO.RDE_RAW_Pathology DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.DBO.RDE_RAW_Pathology DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_APC DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_APC DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_APC DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_OPA DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_OPA DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_CDS_OPA DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_Pathology DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_Pathology DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_Pathology DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_ARIAPharmacy DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_ARIAPharmacy DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_ARIAPharmacy DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_Powerforms DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_Powerforms DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_Powerforms DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_Radiology DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_Radiology DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_Radiology DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_FamilyHistory DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_FamilyHistory DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_FamilyHistory DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_BLOBDataset DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_BLOBDataset DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_BLOBDataset DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROBLEMS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROBLEMS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROBLEMS DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROCEDURES DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROCEDURES DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_PROCEDURES DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_PC_DIAGNOSIS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_DIAGNOSIS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_PC_DIAGNOSIS DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Booking DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Booking DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Booking DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_CareContact DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_CareContact DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_CareContact DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Diagnosis DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Diagnosis DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Diagnosis DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Delivery DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Delivery DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Delivery DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Delivery DROP COLUMN IF EXISTS Baby_NHS
ALTER TABLE BH_RESEARCH.dbo.RDE_MSDS_Delivery DROP COLUMN IF EXISTS Baby_MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_AllergyDetails DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_AllergyDetails DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_AllergyDetails DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_PharmacyOrders DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_PharmacyOrders DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_PharmacyOrders DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MILL_Powertrials DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MILL_Powertrials DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MILL_Powertrials DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_Aliases DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_Aliases DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_Aliases DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_CritActivity DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_CritActivity DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_CritActivity DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_CritPeriod DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_CritPeriod DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_CritPeriod DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_CritOPCS DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_CritOPCS DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_CritOPCS DROP COLUMN IF EXISTS MRN

ALTER TABLE BH_RESEARCH.dbo.RDE_Measurements DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_Measurements DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_Measurements DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_EmergencyD DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_EmergencyD DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_EmergencyD DROP COLUMN IF EXISTS MRN


ALTER TABLE BH_RESEARCH.dbo.RDE_MedAdmin DROP COLUMN IF EXISTS NHSNumber
ALTER TABLE BH_RESEARCH.dbo.RDE_MedAdmin DROP COLUMN IF EXISTS NHS_Number
ALTER TABLE BH_RESEARCH.dbo.RDE_MedAdmin DROP COLUMN IF EXISTS MRN


END

declare @extract_type varchar(100)
select @extract_type =[Extract_Type] from [RESEARCH_EXTRACT_CONFIG] where Extract_ID=@EXTRACT_ID
Set @ErrorPosition=2000
Set @ErrorMessage='checking file type'


DECLARE @bpccommand VARCHAR(1000);

DECLARE export_cursor CURSOR FOR
SELECT Output_Table, Extract_Path, FileName_Prefix
FROM [BH_RESEARCH].[dbo].[Extract_Files_Config]
WHERE Extract_Type = @extract_type;

Declare @ServerName	VARCHAR(50)
DECLARE @OutputTable VARCHAR(255);
DECLARE @ExtractPath VARCHAR(255);
DECLARE @FileNamePrefix VARCHAR(255);
DECLARE @CurrentDate VARCHAR(10);

SET @CurrentDate = CONVERT(VARCHAR(10), GETDATE(), 112);
Set @ServerName = Convert(Varchar(20),serverproperty('MachineName')) + Case when serverproperty('InstanceName') is null then '' else '\' + Convert(Varchar(20),serverproperty('InstanceName')) end

OPEN export_cursor;
FETCH NEXT FROM export_cursor INTO @OutputTable, @ExtractPath, @FileNamePrefix;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @bpccommand = 'BCP [BH_RESEARCH].[dbo].' + @OutputTable + ' out "' + @ExtractPath + @FileNamePrefix + '_' + @CurrentDate + '.csv" -c -t, -T -C 65001 -S @ServerName';
    EXEC xp_cmdshell @bpccommand;

    FETCH NEXT FROM export_cursor INTO @OutputTable, @ExtractPath, @FileNamePrefix;
END;

CLOSE export_cursor;
DEALLOCATE export_cursor;


--EXEC [bh_datawarehouse].dbo.[sp_Extract_Write_File] @extract_type

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'
INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
	        VALUES (@Extract_id,'CSV-WRITE TO FILE', @StartDate, @EndDate,@time,@Row_Count) 


INSERT INTO BH_RESEARCH.DBO.[Research_Extract_Control] VALUES(@Extract_id,@extract_type,@SPstart,@EndDate ,@Filetype)

-----------------------------------------------------ADDING HEADERS TO FILE----------------------------------
DROP TABLE IF EXISTS  #ALLFILENAMES
DROP TABLE IF EXISTS  #TableName1
CREATE TABLE #ALLFILENAMES(ExtrPath VARCHAR(255),ExtrFilename varchar(255),Table_name VARCHAR(200))
   
    -- variables
    declare @filename varchar(255),
            @path     varchar(255),
            @sql      varchar(8000),
           	@filename1  varchar(255)
------------------------------------------------
DECLARE @colnames          VARCHAR(max)
Declare @TableName         Varchar(200)
declare @cmd			   Varchar(200)
Declare @CMD_String        varchar(8000)
-------------------------------------------
SELECT SUBSTRING(Output_Table, CHARINDEX('.dbo.',Output_Table)+5, len(Output_Table))as tabname,FileName_Prefix,FileNo into #TableName1  FROM   bh_research.dbo.Extract_Files_Config 
		   WHERE  Extract_Type = @Extract_Type

--Save path into the variable
    
SELECT @path=Extract_Path  FROM   bh_research.dbo.Extract_Files_Config WHERE  Extract_Type = @Extract_Type
    
	SET @cmd = 'dir ' + @path + '*.csv /b'
    INSERT INTO  #ALLFILENAMES(ExtrFilename)
    EXEC Master..xp_cmdShell @cmd

	delete from #ALLFILENAMES where ExtrFilename is null
    UPDATE #ALLFILENAMES SET ExtrPath = @path where ExtrPath is null

	 UPDATE #ALLFILENAMES  SET Table_name=  b.tabname  from #ALLFILENAMES a join #TableName1 b on left(a.ExtrFilename,LEN(b.FileName_Prefix))=b.FileName_Prefix

	 
SELECT * FROM #ALLFILENAMES
    --cursor loop
    
	declare c1 cursor for SELECT ExtrPath,ExtrFilename,Table_name FROM #ALLFILENAMES --where ExtrFilename like '%.csv%'
    open c1
    fetch next from c1 into @path,@filename,@TableName
    While (@@fetch_status <>-1)--0
      begin
     
      
	  set @colnames=null
	   SELECT @colnames = COALESCE(@colnames + ',', '') + column_name from BH_RESEARCH.INFORMATION_SCHEMA.COLUMNS where TABLE_NAME=@TableName;
       select @colnames;



              set @cmd_string = 'echo '+@colnames +' >'+@path+'Header.txt '                        
              drop table if exists #CMD_Output2
			  print @cmd_string
              create table #CMD_Output2(line varchar(2000))
              insert into #CMD_Output2
			  exec master..xp_cmdshell @CMD_String
			  --select * from #CMD_Output2
			print 'output2'
			print @cmd_string
			print '****************'
			print @tablename
			print @filename
			print' +++++++++++++++++++'
			
              set @cmd_string = 'Type ' +@path+@filename +' >>'+@path+'Header.txt'
              drop table if exists #CMD_Output3
              create table #CMD_Output3(line varchar(2000))
              insert into #CMD_Output3
              exec master..xp_cmdshell @CMD_String
			  
			  print 'output 3'
			  print @CMD_String
			  print '*******************'
			  print 'path='
			  print @path
			  print 'filename='
			  print @filename
			  set @filename1=substring(@filename, 1, (len(@filename)-4))+'_old.csv'
			  print 'filename 1='
			  print @filename1
			 
              set @cmd_string = 'rename '+ @path+@filename+' '+ @filename1
			  print @CMD_String
              drop table if exists #CMD_Output4
              create table #CMD_Output4(line varchar(2000))
              insert into #CMD_Output4
              exec master..xp_cmdshell @CMD_String

		
			  print 'output 4'
			  print @cmd_string
			  print '__________________________'
              set @cmd_string = 'rename '+ @path+'Header.txt'+' ' +@filename
			  
			  
              drop table if exists #CMD_Output5
              create table #CMD_Output5(line varchar(2000))
              insert into #CMD_Output5
              exec master..xp_cmdshell @CMD_String
			  print 'output 5'
			  print @cmd_string


              set @cmd_string = 'del '+@path+@filename1
			  print 'new string'
			  print @cmd_string
              drop table if exists #CMD_Output6
              create table #CMD_Output6(line varchar(2000))
              insert into #CMD_Output6
              exec master..xp_cmdshell @CMD_String
			  print 'output 6'
			  print @cmd_string
			  --set @cmd_string = 'del '+@path+'header.txt'
			  --exec master..xp_cmdshell @CMD_String
			  --print 'remove header'
    
	--end
	 --set @colnames='';
	
      fetch next from c1 into @path,@filename,@TableName;

      end
    close c1
    deallocate c1

---------------------------------------------------------------------------
end

if @Filetype='JSON'
begin
Set @ErrorPosition=2200
Set @ErrorMessage='Next is JSON select '

--------------------------------------------------------------------------------------------------------------------
---------------GENERATE JSON FILE

SELECT @StartDate=GETDATE()

DECLARE @JSONDATA NVARCHAR(MAX)
  SELECT @JSONDATA= CAST( (
    (SELECT DISTINCT
	 A.[NHS_Number] AS [PatientDetails.NHS_Number]
    ,A.[MRN] AS [PatientDetails.MRN]
	,A.[Date_of_Birth]AS [PatientDetails.Date_of_Birth]
	,A.[Gender_CD] AS [PatientDetails.Gender_CD]
	,A.[Gender] AS [PatientDetails.Gender]
	,A.ETHNIC_CD AS [PatientDetails.Ethnicity_CD]
	,A.[Ethnicity] AS [PatientDetails.Ethnicity]
	,A.[Date_of_Death] AS [PatientDetails.Date_of_Death],

	Aliases= 
		(SELECT 
		ALIAS.[CodeType],
		ALIAS.[Code],
		ALIAS.[IssueDate]
		FROM  BH_RESEARCH.DBO.RDE_Aliases ALIAS WHERE A.[NHS_Number]=ALIAS.NHS_NUMBER FOR JSON PATH),
		          
	 Powertrials= 
		(SELECT 
		PTRIALS.[Study_code],
		PTRIALS.[Study_Name],
		PTRIALS.[Study_Participant_ID],
		PTRIALS.[On_Study_Date],
		PTRIALS.[Off_Study_Date],
		PTRIALS.[Off_Study_Code],
		PTRIALS.[Off_Study_Reason],
		PTRIALS.[Off_Study_Comment]
		
		FROM  BH_RESEARCH.DBO.RDE_MILL_Powertrials PTRIALS WHERE A.[NHS_Number]=PTRIAlS.NHS_NUMBER FOR JSON PATH),

	Inpatient= 
		(SELECT 
		 APC.CDS_APC_ID,
		 ISNULL(APC.ENC_DESC,'Inpatient') [AttendanceType]
		,APC.[CDS_Activity_Dt] [CDSDate]
		,APC.[Adm_Dt]
		,APC.[Disch_Dt]
		,APC.Treat_Func_Cd
		,APC.Spell_HRG_Cd
		,HRG_Desc
		--,[Ptnt_Class]
		,APC.PatClass_Desc
		,APC.[LOS]
		,APC.[Admin_Cat_Cd]
		,APC.[Admin_Cat_Desc]
		,APC.[Admiss_Srce_Cd]
		,APC.[Admiss_Source_Desc]
		,APC.[Disch_Dest]
		,APC.[Disch_Dest_Desc]
		,APC.[Ep_Start_Dt]
		,APC.[Ep_End_Dt]
		,APC.[Ep_Num]
		,APC.[Priority_Cd]
		,APC.[Priority_Desc],

		
	 APCDiagnosis= 
		(SELECT 
		--[CDS_APC_ID]
		 D.[CDS_Activity_Dt] [CDSDate]
		,D.[ICD_DIAGNOSIS_NUM] [ICDNum]
		,D.[ICD_DIAGNOSIS_CD] [ICDCode]
		,D.ICD_Diag_Desc  [ICDDesc]
		
		FROM  BH_RESEARCH.DBO.RDE_APC_DIAGNOSIS D WHERE A.[NHS_Number]=D.NHS_Number AND D.CDS_APC_ID=APC.CDS_APC_ID FOR JSON PATH),
				
	 APCProcedure=
		(SELECT 
		--[CDS_APC_ID]
		 P.[CDS_Activity_Dt] [CDSDate]
		,P.[OPCS_Proc_Num]   [OPCSNum]
		,P.[OPCS_Proc_Cd]   [OPCSCode]
		,P.Proc_Desc  [OPCSDesc]
		,P.OPCS_Proc_Dt [OPCSDT]
		FROM  BH_RESEARCH.DBO.RDE_APC_OPCS P WHERE A.[NHS_Number]=P.NHS_Number AND APC.CDS_APC_ID=P.CDS_APC_ID ORDER BY P.OPCS_Proc_Dt FOR JSON PATH)

		FROM   BH_RESEARCH.DBO.RDE_CDS_APC APC WHERE APC.NHS_NUMBER=A.NHS_Number ORDER BY APC.[Adm_Dt]
		FOR JSON PATH),  --Inpatient ends here

    Outpatient=
		(SELECT 
		 OPA.CDS_OPA_ID,
		 ISNULL (OPA.ENC_DESC,'Outpatient') [AttendanceType]
		 --CDS_OPA_ID  [AttendanceType]
		,OPA.[CDS_Activity_Dt][CDSDate]
		,OPA.[Att_Dt]
		,OPA.[HRG_Cd]
		,OPA.HRG_Desc
		,OPA.Treat_Func_Cd
		,COALESCE (OPA.Atten_TypeDesc,OPA.Att_Type) AS Att_Type
		,OPA.Attended_Desc
		,OPA.Attendance_Outcome_Desc,
		
	  OPDiagnosis=
		(SELECT 
		--[CDS_APC_ID]
		 D1.[CDS_Activity_Dt] [CDSDate]
		,D1.[ICD_DIAGNOSIS_NUM] [ICDNum]
		,D1.[ICD_DIAGNOSIS_CD] [ICDCode]
		,D1.ICD_Diag_Desc  [ICDDesc]
		
		FROM  BH_RESEARCH.DBO.RDE_OP_DIAGNOSIS D1 WHERE A.[NHS_Number]=D1.NHS_Number AND D1.CDS_OPA_ID=OPA.CDS_OPA_ID  FOR JSON PATH),

	  OPProcedure=
		(SELECT 
		 P1.CDS_Activity_Dt [CDSDate]
		,P1.[OPCS_Proc_Cd]  [OPCSCD]
		,P1.[Proc_Desc] [OPCSDesc]
		,P1.[opcs_proc_dt] [OPCSDt]
		,P1.[OPCS_Proc_Num] [OPCSNum]

		FROM  BH_RESEARCH.DBO.RDE_OPA_OPCS P1 WHERE A.NHS_Number=P1.NHS_Number AND OPA.CDS_OPA_ID=P1.CDS_OPA_ID ORDER BY P1.[opcs_proc_dt]
		FOR JSON PATH)

		
		FROM  BH_RESEARCH.DBO.RDE_CDS_OPA OPA WHERE OPA.NHS_NUMBER=A.NHS_Number ORDER BY OPA.[Att_Dt]
		FOR JSON PATH),

	 Pathology= 
		(SELECT 
		PA.ENCNTR_ID
		,PA.[RequestDate] 
		,PA.[ReportDate] 
		,PA.[TestCode]  
		,PA.[TestName]   
		,PA.TestDesc
		,CONVERT(VARCHAR,PA.Result_nbr  ) AS ResultNbr   
		,PA.ResultTxt
        --,JSON_QUERY( RESULTUNIT ,'$.Pathology') as RESULTUNIT
		,PA.ResultUnit
        ,PA.[ResUpper]       
		,PA.[ResLower] 
		,PA.Resultfinding   
		,PA.EventID
		,PA.SnomedCode

		FROM   BH_RESEARCH.DBO.RDE_Pathology PA WHERE PA.NHS_NUMBER=A.NHS_Number --and (PA.Result_nbr is not null or PA.ResultTxt is not null )
		ORDER BY PA.[RequestDate]
		FOR JSON PATH ),

	 Aria= 
		(SELECT 
		PH.AdmnStartDate  
		,PH.ProductDesc 
		,PH.DosageForm
		,PH.DoseLevel
		,PH.RxDose
		,PH.RxTotal
		,PH.AdmnDosageUnit
		,PH.AdmnRoute
		,PH.SetDateTPInit
		,PH.TreatPlan
		FROM  BH_RESEARCH.DBO.RDE_ARIAPharmacy PH WHERE A.[NHS_Number]=PH.NHS_Number AND [ProductDesc] IS NOT NULL ORDER BY AdmnStartDate FOR JSON PATH),
				
	 Powerforms=
		(SELECT distinct
		 PW.PerformDate
		,PW.ENCNTR_ID
		--,PW.DOC_RESPONSE_KEY
		,PW.Form
		,PW.Section,
		FormDetails=(select distinct
		 PW1.Element
		,PW1.[Response] 
		from  BH_RESEARCH.DBO.RDE_Powerforms pw1 WHERE pw1.[NHS_Number]=PW.NHS_Number AND (pw1.ENCNTR_ID=pw.ENCNTR_ID and pw.PerformDate=pw1.PerformDate and pw.Form=pw1.Form) FOR JSON PATH)

		FROM  BH_RESEARCH.DBO.RDE_Powerforms PW WHERE A.[NHS_Number]=PW.NHS_Number AND ([FORM] IS NOT NULL OR [Section] IS NOT NULL)  ORDER BY PW.[PerformDate]  FOR JSON PATH),

	 Imaging=
		(SELECT 
		 R.ENCNTR_ID
	    ,R.[Acitvity type]
	    ,R.TFCode
	    ,R.TFCdesc
	    ,R.ExaminationTypecode
	    ,R.ExaminationTypeName
	    ,R.EXAMNAME
		,R.EventName
		,R.EVENT_TAG_TXT
	    ,R.Modality 
	    ,R.SubModality
	    ,R.RecordStatus 
	    ,R.ExamStart 
	    ,R.ExamEnd
	    ,R.ResultStatus
		,R.ReportText
		,R.EventID
      	FROM  BH_RESEARCH.DBO.RDE_Radiology R  WHERE A.NHS_Number=R.NHS_Number ORDER BY [ExamStart]
		FOR JSON PATH),

		BlobData=
		(SELECT 
		
		  BLOB.ParentEventID AS EventID
		 ,BLOB.ClinicalSignificantDate
		 ,BLOB.MainEventDesc
		 ,BLOB.MainTitleText
		 ,BLOB.MainTagText
		 ,BLOB.ChildEvent
		 ,BLOB.ChildTagText
		 ,BLOB.BlobContents
		 ,BLOB.EventDesc
		 ,BLOB.EventResultText
		 ,BLOB.EventResultNBR
		 ,BLOB.ClassDesc
		 ,BLOB.Status
		 ,BLOB.SourceSys
		 ,BLOB.EventReltnDesc
		FROM  BH_RESEARCH.DBO.RDE_BLOBDataset BLOB WHERE A.[NHS_Number]=BLOB.NHS_Number ORDER BY ClinicalSignificantDate FOR JSON PATH),	   
		
	 FamilyHistory=
		(SELECT 
		   FH.RELATION_CD      AS RelCD
		  ,FH.RelationDesc
		  ,FH.RELATION_TYPE    AS RelTypeCD
		  ,FH.RelationType
		  ,FH.ACTIVITY_NOMEN   AS NomenID
		  ,FH.NomenDesc
		  ,FH.NomenVal
		  ,FH.VOCABULARY_CD    AS VocabCD 
		  ,FH.VocabDesc
		  ,FH.TYPE             AS [Type]
		  ,FH.BegEffectDate
		  ,FH.EndEffectDate
		  ,FH.FHX_VALUE_FLG
		FROM  BH_RESEARCH.DBO.RDE_FamilyHistory FH WHERE A.[NHS_Number]=FH.NHS_Number ORDER BY FH.BegEffectDate FOR JSON PATH),	  
		
	 PCProblems=
		(SELECT 
		    RTRIM (PB.ProbID)                    AS ProbID
		   ,RTRIM (PB.Problem)                   AS Problem
		   ,RTRIM (PB.Annot_Disp)      AS Annot_Disp
		   ,RTRIM (PB.Confirmation)    AS Confirmation
		   ,RTRIM (PB.Classification) AS Classification
		   ,RTRIM (PB.OnsetDate)  AS OnsetDate
		   ,RTRIM (PB.StatusDate) AS StatusDate
		   ,RTRIM (PB.Stat_LifeCycle)AS Stat_LifeCycle
		   ,RTRIM (PB.LifeCycleCancReson)AS LifeCycleCancReson
		   ,RTRIM (PB.Vocab)AS Vocab
		   ,RTRIM (PB.Axis) AS Axis
		   ,RTRIM (PB.SecDesc) AS SecDesc
		   ,RTRIM (PB.ProbCode) AS ProbCode
		FROM  BH_RESEARCH.DBO.RDE_PC_PROBLEMS PB WHERE A.[NHS_Number]=PB.NHS_Number  ORDER BY PB.OnsetDate FOR JSON PATH),
	
	  PCDiagnosis=
		(SELECT 
		    RTRIM (PD.DiagID) AS DiagID
		   ,RTRIM (PD.DiagCode) AS DiagCode
		   ,RTRIM (PD.DiagDt) AS DiagDt
		   ,RTRIM (PD.Diagnosis)AS Diagnosis
		   ,RTRIM (PD.Confirmation) AS Confirmation
		   ,RTRIM (PD.Classification) AS Classification
		   ,RTRIM (PD.ClinService) AS ClinService
		   ,RTRIM (PD.DiagType) AS DiagType
		   ,RTRIM (PD.Vocab) AS Vocab
		   ,RTRIM (PD.Axis) AS Axis
		   
		FROM  BH_RESEARCH.DBO.RDE_PC_DIAGNOSIS PD WHERE A.[NHS_Number]=PD.NHS_Number ORDER BY PD.DiagDt FOR JSON PATH),	     
     PCProcedures=
		(SELECT 
		    RTRIM (PP.ProcType) AS ProcType
		   ,RTRIM (PP.AdmissionDT) AS AdmissionDT
		   ,RTRIM (PP.ProcDt) AS ProcDt
		   ,RTRIM (PP.DischargeDT) AS DischargeDT
		   ,RTRIM (PP.ProcCD) AS ProcCD
		   ,RTRIM (PP.ProcDetails) AS ProcDetails
		   ,RTRIM (PP.TreatmentFunc)  AS TreatmentFunc
		   ,RTRIM (PP.Specialty) AS Specialty
		   ,RTRIM (PP.Comment) AS Comment
		FROM  BH_RESEARCH.DBO.RDE_PC_PROCEDURES PP WHERE A.[NHS_Number]=PP.NHS_Number ORDER BY PP.ProcDt FOR JSON PATH),	  
	/*
	MSDS_Booking= 
		(SELECT 
		  Book.PregnancyID
		 ,Book.AntenatalAPPTDate
		 ,Book.AlcoholUnitsPerWeek
		 ,Book.CigarettesPerDay
		 ,Book.CompSocialFactor
		 ,Book.DisabilityMother
		 ,Book.MatDischargeDate
		 ,Book.DischReason
		 ,Book.[EST_DELIVERYDATE(AGREED)]
		 ,Book.[METH_OF_EST_DELIVERY_DATE(AGREED)]
		 ,Book.FolicAcidSupplement
		 ,Book.PregConfirmed
		 ,Book.LastMensturalPeriodDate
		 ,Book.PrevC_Sections
		 ,Book.PrevLiveBirths
		 ,Book.PrevLossesLessThan24Weeks
		 ,Book.PrevStillBirths
		 ,Book.SmokingStatus
		 ,Book.MothSuppStatusIND,
	
		   MSDS_Diagnosis= 
		     (SELECT 
		             D.DiagPregID
		            ,D.DiagScheme
		            ,D.Diagnosis
					,D.DiagDate
					,D.DiagDesc
					,D.LocalFetalID
					,D.FetalOrder
	
			FROM   BH_RESEARCH.DBO.RDE_MSDS_Diagnosis D WHERE D.NHS_Number=A.NHS_Number AND D.DiagPregID=Book.PregnancyID
		    FOR JSON PATH),  
	        
			MSDS_CareContact= 
		     (SELECT 
		             CC.CareConID
		            ,CC.CareConDate
		            ,CC.AdminCode
					,CC.Duration
					,CC.ConsultType
					,CC.Subject
					,CC.Medium
					,CC.GPTherapyIND
					,CC.AttendCode
					,CC.CancelReason
					,CC.CancelDate
					,CC.RepAppOffDate
	
			FROM   BH_RESEARCH.DBO.RDE_MSDS_CareContact CC WHERE CC.NHS_Number=A.NHS_Number AND CC.PregnancyID=Book.PregnancyID
		    FOR JSON PATH),  

			MSDS_Delivery= 
		     (SELECT 
		            Del.LabourDelID
					,Del.SettingIntraCare
					,Del.ResonChangeDelSettingLab
					,Del.LabourOnsetMeth
					,Del.LabOnsetDate
					,Del.CSectionDate
					,Del.DecDeliveryDate
					,Del.AdmMethCodeMothDelHSP
					,Del.DischDate
					,Del.DischMeth
					,Del.DischDest
					,Del.RomDate
					,Del.RomMeth
					,Del.RomReason
					,Del.EpisiotomyReason
					,Del.PlancentaDelMeth
					,Del.LabOnsetPresentation
	
			FROM   BH_RESEARCH.DBO.RDE_MSDS_Delivery Del WHERE Del.NHS_Number=A.NHS_Number AND Del.PregID=Book.PregnancyID
		    FOR JSON PATH)
			

		FROM   BH_RESEARCH.DBO.RDE_MSDS_Booking Book WHERE Book.NHS_Number=A.NHS_Number ORDER BY MatDischargeDate
		FOR JSON PATH),
	*/	
		 PharmacyOrders=
		(SELECT 
	     Ord.OrderID
		 ,Ord.OrderDate
		 ,Ord.LastOrderStatusDateTime
		 ,Ord.ReqStartDateTime
		 ,Ord.OrderText
		 ,Ord.OrderDetails
		 ,Ord.LastOrderStatus
		 ,Ord.ClinicalCategory
		 ,Ord.ActivityDesc
		 ,Ord.OrderableType
		 ,Ord.PriorityDesc
		 ,Ord.CancelledReason
		 ,Ord.CancelledDT
		 ,Ord.CompletedDT
		 ,Ord.DiscontinuedDT
		 ,Ord.ConceptIdent
      	FROM  BH_RESEARCH.DBO.RDE_PharmacyOrders Ord  WHERE A.NHS_Number=Ord.NHS_Number ORDER BY OrderDate
		FOR JSON PATH),


	  AllergyDetails=
		(SELECT 
	     Al.AllergyID
		 ,Al.SubstanceDesc
		 ,Al.SubstanceFTDesc
		 ,Al.SubstanceDispTxt
		 ,Al.SubstanceValueTxt
		 ,Al.SubstanceType
		 ,Al.ReactionType
		 ,Al.Severity
		 ,Al.SourceInfo
		 ,Al.OnsetDT
		 ,Al.ReactionStatus
		 ,Al.CreatedDT
		 ,Al.CancelReason
		 ,Al.CancelDT
		 ,Al.ActiveStatus
		 ,Al.ActiveDT
		 ,Al.BegEffecDT
		 ,Al.EndEffecDT
		 ,Al.DataStatus
		 ,Al.DataStatusDT
		 ,Al.VocabDesc
		 ,Al.PrecisionDesc
      	FROM  BH_RESEARCH.DBO.RDE_AllergyDetails Al  WHERE A.NHS_Number=Al.NHS_Number ORDER BY CreatedDT
		FOR JSON PATH),

		SCRReferrals=
		(SELECT 
	      R.CancerSite
		  ,R.CareID
		  ,R.PATIENT_ID
		  ,R.PriorityDesc
		  ,R.DecisionDate
		  ,R.ReceiptDate
		  ,R.DateSeenFirst
		  ,R.CancerType
		  ,R.StatusDesc
		  ,R.FirstAppt
		  ,R.DiagDate
		  ,R.DiagCode
		  ,R.DiagDesc
		  ,R.DiagBasis
		  ,R.OtherDiagDate
		  ,R.Laterality
		  ,R.Differentiation
		  ,R.Histology
		  ,R.ClinicalTStage
		  ,R.ClinicalTCertainty
		  ,R.ClinicalNStage
		  ,R.ClinicalNCertainty
		  ,R.ClinicalMStage
		  ,R.ClinicalMCertainty
		  ,R.PathologicalTStage
		  ,R.PathologicalTCertainty
		  ,R.PathologicalNStage
		  ,R.PathologicalNCertainty
		  ,R.PathologicalMStage
		  ,R.PathologicalMCertainty
		  ,R.TumourStatus
		  ,R.TumourDesc
		  ,R.TreatReason
		  ,R.RecSiteID
		  ,R.NewTumourSite
		  ,R.SnomedCD
		  ,R.SubSiteID,

		  SCRTrackingComments= 
		     (SELECT 
			    TC.CareID
				,TC.Date_Time
				,TC.Comments

		     FROM  BH_RESEARCH.DBO.RDE_SCR_TrackingComments TC WHERE A.NHS_Number=TC.NHS_Number 
			 FOR JSON PATH),

		  SCRCarePlan= 
		     (SELECT 
			    C.CareID
				,C.PlanID
				,C.MDTDate
				,C.MDTSite
				,C.CareIntent
				,C.TreatType
				,C.PlanType
				,C.WHOStatus
				,C.AgreedCarePlan
				,C.Network
				,C.NetworkDate
				,C.NetworkFeedback
				,C.NetworkComments
				,C.MDTComments

		     FROM  BH_RESEARCH.DBO.RDE_SCR_CarePlan C WHERE A.NHS_Number=C.NHS_Number 
			 FOR JSON PATH),

		    SCRTreatment= 
		     (SELECT 
			    DT.CareID
				,DT.TreatmentID
				,DT.DecisionDate
				,DT.StartDate
				,DT.Treatment
				,DT.TreatEvent
				,DT.TreatSetting
				,DT.TPriority
				,DT.Intent
				,DT.TreatID
				,DT.TreatNo
				--,DT.Comments
				--,DT.AllComments
				,DT.ChemoRT
				,DT.DelayComments
				,DT.DEPRECATEDComments
				,DT.DEPRECATEDAllComments
				,DT.RootTCIComments
				,DT.ROOT_DATE_COMMENTS

		     FROM  BH_RESEARCH.DBO.RDE_SCR_DefTreatment DT WHERE A.NHS_Number=DT.NHS_Number 
			 FOR JSON PATH),

			 SCRDiagnosis= 
		     (SELECT 
				D.CareID
				,D.CancerSite
				,D.PatientStatus
				,D.PrimCancerSite
				,D.TumourStatus
				,D.NewTumourSite
				,D.DiagDate
				,D.DatePatInformed
				,D.PrimDiagICD
				,D.PrimDiagSnomed
				,D.SecDiag
				,D.Laterality
				,D.NonCancerdet
				,D.DiagBasis
				,D.Histology
				,D.Differentiation
				,D.Comments
				,D.PathwayEndFaster
				,D.PathwayEndReason

		     FROM  BH_RESEARCH.DBO.RDE_SCR_Diagnosis D WHERE A.NHS_Number=D.NHS_Number 
			 FOR JSON PATH),

			 SCRInvestigations= 
		     (SELECT 
				I.CareID
				,I.CancerSite
				,I.DiagInvestigation
				,I.ReqDate
				,I.DatePerformed
				,I.DateReported
				,I.BiopsyTaken
				,I.Outcome
				,I.Comments
				,I.NICIPCode
				,I.SnomedCT
				,I.AnotomicalSite
				,I.AnatomicalSide
				,I.ImagingReport
				,I.StagingLaproscopyPerformed

		     FROM  BH_RESEARCH.DBO.RDE_SCR_Investigations I WHERE A.NHS_Number=I.NHS_Number 
			 FOR JSON PATH),

			  SCRPathology= 
		     (SELECT
				P.CareID
				,P.PathologyID 
				,P.PathologyType
				,P.ResultDate
				,P.ExcisionMargins
				,P.Nodes
				,P.PositiveNodes
				,P.PathTstage
				,P.PathNstage
				,P.PathMstage
				,P.Comments
				,P.SampleDate
				,P.PathologyReport
				,P.SNomedCT
				,P.SNomedID

		     FROM  BH_RESEARCH.DBO.RDE_SCR_Pathology P WHERE A.NHS_Number=P.NHS_Number 
			 FOR JSON PATH),

			   SCRImaging= 
		     (SELECT 
				SI.CareID
				,SI.ImageID
				,SI.RequestDate
				,SI.ImagingDate
				,SI.ReportDate
				,SI.AnatomicalSite
				,SI.AnatomicalSide
				,SI.ImageResult
				,SI.Contrast
				,SI.Result
				,SI.Report
				,SI.StagingProc
				,SI.ImageCD

		     FROM  BH_RESEARCH.DBO.RDE_SCR_Imaging SI WHERE A.NHS_Number=SI.NHS_Number 
			 FOR JSON PATH)

      	FROM  BH_RESEARCH.DBO.RDE_SCR_Referrals R  WHERE A.NHS_Number=R.NHS_Number --ORDER BY [ExamStart]
		FOR JSON PATH)
		
		FROM  BH_RESEARCH.DBO.RDE_Patient_Demographics A WHERE NHS_Number IS NOT NULL -- a.NHSnumber='4445878030' 
		FOR JSON PATH))AS Nvarchar(MAX)) --patientdemogrphics ends here

Set @ErrorPosition=2500
Set @ErrorMessage='JSON select complete,next creating json temp table'

--INSERTING RECORDS INTO A TEMPTABLE BEFORE WRITING INTO THE TABLE
SELECT * INTO #JSONTEMP FROM OPENJSON(@JSONDATA)


IF OBJECT_ID('dbo.EXTRACT_JSON_Output_Temp') IS NOT NULL DROP TABLE dbo.EXTRACT_JSON_Output_Temp

CREATE TABLE dbo.EXTRACT_JSON_Output_Temp([KEY] INT,[JSONDATA] NVARCHAR(MAX))
--TRUNCATE TABLE dbo.EXTRACT_JSON_Output_Temp

Set @ErrorPosition=2510
Set @ErrorMessage='JSON temp table created and nextstep - insert into temptable'

INSERT INTO dbo.EXTRACT_JSON_Output_Temp SELECT J.[KEY], J.[VALUE] FROM #JSONTEMP J

Set @ErrorPosition=2520
Set @ErrorMessage='JSON data inserted into EXTRACT_JSON_Output_Temp table'


DECLARE @Command1 VARCHAR(2000)
DECLARE @Filename2 VARCHAR(2000)
--------------------------
Set @ErrorPosition=2530
Set @ErrorMessage='Reading JSON file path and name'

SELECT @Filename2=(SELECT [Extract_Output_FilePath]+[Extract_Output_Filename]+FORMAT(GETDATE(), '_yyyyMMddHHmm')+'.JSON' FROM [BH_RESEARCH].[dbo].[RESEARCH_EXTRACT_CONFIG] WHERE EXTRACT_ID=@Extract_ID)

SELECT @Command1 = 'bcp "SELECT [JSONDATA] FROM [bh_RESEARCH].dbo.EXTRACT_JSON_Output_Temp " queryout ' + @Filename2 + ' -C 65001 -c -T -t' + @@SERVERNAME

Set @ErrorPosition=2540
Set @ErrorMessage='BCP command next'
EXECUTE master..xp_cmdshell @Command1

SELECT	@EndDate = GETDATE();
select @time= CAST( DATEPART(HOUR,   @EndDate - @StartDate)        AS nvarchar(100)) + ' -  HRS '
            + CAST( DATEPART(MINUTE, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  MINS '
            + CAST( DATEPART(SECOND, @EndDate - @StartDate)        AS nvarchar(100)) + ' -  SECS'

INSERT INTO BH_RESEARCH.dbo.[RESEARCH_AUDIT_LOG] 
			VALUES (@Extract_id,'JSON-WRITE TO FILE', @StartDate, @EndDate,@time,@Row_Count) 

INSERT INTO BH_RESEARCH.DBO.[Research_Extract_Control] VALUES(@Extract_id,@extract_type,@SPstart,@EndDate ,@Filetype)

Set @ErrorPosition=2550
Set @ErrorMessage='JSON file produced and saved in the RESEARCH_EXTRACT folder'

--IF OBJECT_ID('dbo.EXTRACT_JSON_Output_Final') IS NOT NULL DROP TABLE dbo.EXTRACT_JSON_Output_Final

--CREATE TABLE dbo.EXTRACT_JSON_Output_Final(ID INT IDENTITY(1,1) NOT NULL,[KEY] INT,[JSONDATA] NVARCHAR(MAX))

--INSERT INTO EXTRACT_JSON_Output_Final SELECT [KEY], [JSONDATA] FROM EXTRACT_JSON_Output_Temp
--DROP TABLE BH_RESEARCH.dbo.EXTRACT_JSON_Output_Temp

Set @ErrorPosition=2560
Set @ErrorMessage='Delete JSON temp table BH_RESEARCH.dbo.EXTRACT_JSON_Output_Temp'
END
END TRY
	

	BEGIN CATCH 
		EXECUTE BH_DATAWAREHOUSE.dbo.usp_GetErrorInfo @ErrorModule, @ErrorPosition, @ErrorMessage
	END CATCH

End