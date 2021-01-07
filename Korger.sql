
Use RM_ADCKEY1621t_2
GO 

ALTER PROCEDURE [reporting].[spRptOLR_DueOverdueUpcoming]                                
 (                                
  @UserId   UniqueIdentifier                                
 ,@SessionId   nvarchar(80)                                  
 ,@ProgramId   UniqueIdentifier                                
 ,@SelectedNodeList reporting.RptParam_SelectedNode READONLY                                
 ,@FilteredRoadmaps reporting.ReportData READONLY                                
 ,@BaseImpacts  reporting.RptParam_BaseImpact READONLY                        
 ,@FilterDateStart DATE                          
 ,@FilterDateEnd  DATE                                  
 ,@FilterOneTimeDateStart DATE                                
 ,@FilterOneTimeDateEnd  DATE                               
 ,@FilterRecurringDateStart DATE                                
 ,@FilterRecurringDateEnd DATE                                
 ,@DefaultMilestoneDate  DATE                       
 ,@Today     DATE                                
 ,@MultiplierSetID Int                                
 ,@IM_IncludeOT  bit                                
 ,@IM_IncludeRE  bit                                
 ,@CalculationType varchar(10)                                
 ,@CalculationDateAsOf Date                                
 ,@MultiplierSetIDa Int                                
 ,@MultiplierPerYear Int                                
 ,@FilteredMilestones reporting.RptParam_UniqueIdentifier READONLY                      
 ,@MilestoneDueInNextNDays INT                                  
 ,@ReportCurrency UNIQUEIDENTIFIER                                
 ,@NumericFactor DECIMAL(19,4)                                
 ,@FactorLabelId INT       
 ,@ReportFilterCacheID  INT                          
 ,@ReportCacheID   INT      
 ,@CachedProjectSnapshotInReport reporting.RptParam_ProjectSnapshotCache READONLY          
 ,@CachedProjectSnapshotNeeded reporting.RptParam_ProjectSnapshotCache READONLY          
  )                                 
AS                                
---------------------------------------------------------------------------------------------------------------------                                
-- Object Definition                                
---------------------------------------------------------------------------------------------------------------------                                
-- Name:  [reporting].[spRptOLR_Over02b]                                
-- Description: Standard reports enhancement                                 
-- Created by:  Ishani Chadha                              
-- Created on: Dec 03th 2019                               
-- Version:   001_6.0.0.0                                
---------------------------------------------------------------------------------------------------------------------  
-- Modification History Tracking  
---------------------------------------------------------------------------------------------------------------------  
-- Date        | Author       | Version  | Comments  
-- 17/Dec/2020 | Rahul Verma  | 7.1.2    | Addded Cache to improve perfomance and updated the joins condition 
--------------------------------------------------------------------------------------------------------------------                   
--------------------------------------------------------------------------------------------------------------------          
       
-- Get the tree path sort order so the base impacts can be sorted in a filter dropdown                                
 DECLARE @BaseImpactSortOrder AS TABLE (BaseImpactId uniqueidentifier, SortOrder nvarchar(max), Depth int)                                
 DECLARE @ProgramIdStr VARCHAR(50)                
 SET @ProgramIdStr = LOWER(CONVERT(varchar(50), @ProgramId))      
               
 ;WITH TreePath(ID, PARENTID, SortOrder, Depth)                                
 AS                                
 (                                
  -- Limit by ProgramID (only do the projects in this program)                                
  SELECT                                
   A_ID ID,                                
   A_FK_BASE_IMPACT_PARENT ParentID,                                
   cast('::' + right('000'+ rtrim(CAST(A_SORT_ORDER as int)), 3) as nvarchar(max)) as SortOrder,                                
   1                            
  FROM                                
   TBL_BASE_IMPACT                                
  WHERE         
   A_FK_BASE_IMPACT_PARENT IS NULL                                
   AND A_FK_PROGRAM = @ProgramId                                
                                  
  UNION ALL                                
                                
  -- Recursive                                
  SELECT                                
   p2.A_ID ID,                                
   p2.A_FK_BASE_IMPACT_PARENT ParentID,                                
   cast(SortOrder + '::' + right('000'+ rtrim(CAST(p2.A_SORT_ORDER as int)), 3) as nvarchar(max)),                                
   b.Depth + 1 Depth                                
  FROM                                
   TBL_BASE_IMPACT p2                                
  JOIN                                
   TreePath b                                
   ON p2.A_FK_BASE_IMPACT_PARENT = b.ID                                
 )                                
                                
                                
 INSERT INTO                                
  @BaseImpactSortOrder                                
 SELECT                                
  ID,                                
  SortOrder,                                
  Depth                                
 FROM                                
  TreePath                                
                                  
                                
 SELECT DISTINCT                                
  bi.A_ID BaseImpactID,                                
  bi.A_BASE_IMPACT BaseImpactName,                                
  CAST(IIF(bi.A_FINANCIAL = 1, 1, 0) AS bit) IsFinancial,                                
  CAST(IIF(bi.A_CALCULATED = 1, 1, 0) AS bit) IsCalculated,                                
  CAST(IIF(bi.A_FK_BASE_IMPACT_TIMING = 2, 1, 0) AS bit) IsRecurring,                                
  bi.A_UNIT Unit,                                
  s.Depth BaseImpactLevel,                                
  s.SortOrder BaseImpactPath,                                
  bi.A_FK_BASE_IMPACT_PARENT BaseImpactParentBaseImpactID                                
    into #TBL_BASE_IMPACT_Sorted                                
 FROM                      
  dbo.TBL_BASE_IMPACT bi                                 
 JOIN                                
  @BaseImpactSortOrder s                                
  ON                                 
   s.BaseImpactId = bi.A_ID                                
 WHERE                    
  bi.A_FK_PROGRAM = @ProgramId                                
                                  
---------------------------------------------                                 
                                          
 DECLARE @CurrencyCode nchar(3)                                
                                
 Select                                
  @CurrencyCode = c.A_CODE                                
 From                                
  TBL_PROGRAM_CURRENCY pc                                
 JOIN                                
  TBL_CURRENCY c                                
 ON c.A_ID = pc.A_FK_CURRENCY                                
 WHERE                                
  pc.A_ID = @ReportCurrency                                
                          
                          
 DECLARE @BaseImpactID uniqueidentifier                            
 SELECT @BaseImpactID = A_FK_BASE_IMPACT FROM @BaseImpacts                            
 DECLARE @NumberOfRecords INT                            
 DECLARE @NoneBaseImpactSelected bit = IIF(@BaseImpactID = '00000000-0000-0000-0000-000000000000', 1, 0)                                
                        
    
 ---------------------- Temp table for initiatives filtered on the basis of the selected date range ---------                    
IF OBJECT_ID('tempdb..#FilteredRoadmaps') IS NOT NULL DROP TABLE #FilteredRoadmaps                    
select distinct                     
 RMi.A_FK_roadmap,RMi.A_FK_Program,Rmi.A_FK_Project,rmi.TreeOrder ,msv.A_FK_MILESTONE ,im.A_FK_BASE_IMPACT,msv.A_MILESTONE, datediff(day, msv.A_FORECAST, @Today) as datedif,
  MSU_MSO.A_TEXTBOX_VALUE as [Milestone_Owner]  ,
  MSU_SR.A_TEXTBOX_VALUE   as [Project_Status_Rationale],                                 
  MSU_DN.A_TEXTBOX_VALUE   as [Project_Decisions_Needed],                                
  MSU_TMOC.A_TEXTBOX_VALUE as [Project_TMO_Comments],                                
  MSU_ANW.A_TEXTBOX_VALUE  as [Project_Actions_for_Next_Week],                      
  MSU_ALW.A_TEXTBOX_VALUE  as [Project_Actions_from_Last_Week],                               
  MSU_IND.A_TEXTBOX_VALUE  as [Roadmap_Interdependency]
 into #FilteredRoadmaps                     
from                     
 @FilteredRoadmaps RMi                                    
 join reporting.VIEW_MILESTONE msv on msv.A_FK_ROADMAP=rmi.A_FK_Roadmap  
 LEFT JOIN @FilteredMilestones fm on fm.A_FK_UniqueIdentifier=msv.A_FK_MILESTONE  
 left join reporting.VIEW_IMPACT im with (NOEXPAND) on im.A_FK_ROADMAP = RMi.A_FK_ROADMAP AND (im.A_FK_BASE_IMPACT = @BaseImpactID OR @NoneBaseImpactSelected = 1)
  Left  Join TBL_Milestone_UDF MSU_SR on msv.A_FK_Milestone = MSU_SR.A_FK_Milestone and MSU_SR.A_FK_UDF = 'ABD5E81A-0B25-478B-8AB9-0395C365A241'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_SR on MSU_SR.A_FK_UDF_VALUE = MSV_SR.A_ID                                  
  Left  Join TBL_Milestone_UDF MSU_DN on msv.A_FK_Milestone = MSU_DN.A_FK_Milestone and MSU_DN.A_FK_UDF = 'C02AA2B6-DFA5-4F8B-BDAA-E889AD0F82F6'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_DN on MSU_DN.A_FK_UDF_VALUE = MSV_DN.A_ID                                 
  Left  Join TBL_Milestone_UDF MSU_TMOC on msv.A_FK_Milestone = MSU_TMOC.A_FK_Milestone and MSU_TMOC.A_FK_UDF = '6AB651B5-E128-441F-85FF-3A54C20C3E29'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_TMOC on MSU_TMOC.A_FK_UDF_VALUE = MSV_TMOC.A_ID                                  
  Left  Join TBL_Milestone_UDF MSU_ANW on msv.A_FK_Milestone = MSU_ANW.A_FK_Milestone and MSU_ANW.A_FK_UDF = '5FBD2D3F-27C3-4626-BCF6-FF101B09D6B4'                                             
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_ANW on MSU_ANW.A_FK_UDF_VALUE = MSV_ANW.A_ID                       
  Left  Join TBL_Milestone_UDF MSU_ALW on msv.A_FK_Milestone = MSU_ALW.A_FK_Milestone and MSU_ALW.A_FK_UDF = '05F9D974-2CC8-48B8-932C-A7BEAC1C4EC3'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_ALW on MSU_ALW.A_FK_UDF_VALUE = MSV_ALW.A_ID                               
  Left  Join TBL_Milestone_UDF MSU_IND on msv.A_FK_Milestone = MSU_IND.A_FK_Milestone and MSU_IND.A_FK_UDF = 'ECDB71D8-E95B-495B-B64B-081CEE21D264'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_IND on MSU_IND.A_FK_UDF_VALUE = MSV_IND.A_ID                               
  Left  Join TBL_Milestone_UDF MSU_MSO on msv.A_FK_Milestone = MSU_MSO.A_FK_Milestone and MSU_MSO.A_FK_UDF = '1B606719-DC7F-4F2B-8E04-75B4F677DCDE'                                                      
  Left  Join dbo.TBL_UDF_LIST_VALUES MSV_MSO on MSU_MSO.A_FK_UDF_VALUE = MSV_MSO.A_ID                   
Where                 
   (( (@NoneBaseImpactSelected =0 and im.A_FK_ROADMAP is not null) OR  @BaseImpactID is null) OR ( @NoneBaseImpactSelected =1 and im.A_FK_ROADMAP is null))                             
   and datediff(day, msv.A_FORECAST, @Today) >= -@MilestoneDueInNextNDays and msv.A_Plan >= @FilterDateStart and   msv.A_Plan <= @FilterDateEnd and msv.[Milestone_TL_Overall] <> '1'  and msv.A_PLAN is not null             
--------------------------- 
        
select * into #temp22                          
from                          
(select * from                             
		(select A_ID  as [A_FK_roadmap]                          
				,A_FK_Traffic_Light_Overall                             
				,rank() over (partition by A_ID order by A_audit_time desc) as [TL_Rank]                            
				from audit_tbl_roadmap arm  
				join (SELECT dISTINCT A_FK_roadmap FROM #FilteredRoadmaps ) fms on fms.A_FK_Roadmap=arm.A_ID  
				where datediff(day,A_Audit_time,Getdate())>=14                            
		) tbl3                            
where TL_Rank=1   ) tb4                            
                          
                           
						   
select * into #temp33                          
from                          
(select * from                             
(	select   
		A_ID  as [A_FK_roadmap]                          
		,A_FK_Traffic_Light_Overall                             
		,rank() over (partition by A_ID order by A_audit_time desc) as [TL_Rank]                            
		from audit_tbl_roadmap arm  
		join (SELECT dISTINCT A_FK_roadmap FROM #FilteredRoadmaps ) fms on fms.A_FK_Roadmap=arm.A_ID  
		where datediff(day,A_Audit_time,Getdate())>=7                            
	) tbl5                           
	where TL_Rank=1   
) tb6                          
                          
                            
    
             
 IF EXISTS (SELECT 1 FROM @CachedProjectSnapshotNeeded)          
 BEGIN          
select     
	RMi.A_FK_Program,  
	RMi.A_FK_PROJECT,    
	RMi.A_FK_BASE_IMPACT,  
	RMi.A_FK_Roadmap, 
	RMi.A_FK_MILESTONE ,
-- PLAN                                
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_PLAN, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @FilterOneTimeDateEnd                                
    AND                                
    @IM_IncludeOT = 1                                
   ,                                
    im.A_PLAN_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiPlan.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                                
  +  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_PLAN, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @FilterRecurringDateEnd                                
    AND                                
    @IM_IncludeRE = 1                                
   ,                                
    im.A_PLAN_SLOPE * IIF(im.A_FINANCIAL = 1, multiPlan.A_Financial_Multiplier, multiPlan.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [Plan],                                
                          
  -- Actual                                
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_ACTUAL, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @FilterOneTimeDateEnd                              
    AND                                
    @IM_IncludeOT = 1                                
   ,        
    im.A_ACTUAL_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiActual.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                                
  +                                
  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_ACTUAL, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @FilterRecurringDateEnd                       
    AND                                
    @IM_IncludeRE = 1                                
   ,                                
    im.A_ACTUAL_SLOPE * IIF(im.A_FINANCIAL = 1, multiActual.A_Financial_Multiplier, multiActual.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [Actual],                                
                                
                                  
  -- Forecast                                
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_FORECAST, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @FilterOneTimeDateEnd                                
    AND                                
    @IM_IncludeOT = 1                                
   ,                                
    im.A_FORECAST_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiForecast.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                                
  +                                
  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_FORECAST, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @FilterRecurringDateEnd                                
    AND                                
    @IM_IncludeRE = 1                                
   ,                                
    im.A_FORECAST_SLOPE * IIF(im.A_FINANCIAL = 1, multiForecast.A_Financial_Multiplier, multiForecast.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [UPDATE],                                
                                
                                
  -------------------------------------------------------------                             
  -- Plan to Date                                
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_PLAN, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @CalculationDateAsOf                                
    AND                                
    @IM_IncludeOT = 1                                
   ,                                
    im.A_PLAN_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiPlanToDate.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                                
  +                                
  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_PLAN, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @CalculationDateAsOf                                
    AND                                
  @IM_IncludeRE = 1                                
   ,                                
    im.A_PLAN_SLOPE * IIF(im.A_FINANCIAL = 1, multiPlanToDate.A_Financial_Multiplier, multiPlanToDate.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [Plan_To_Date],                       
                                
                                
  -- Actual to Date                                
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_ACTUAL, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @CalculationDateAsOf                                
    AND                                
    @IM_IncludeOT = 1                                
   ,                                
    im.A_ACTUAL_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiActualToDate.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                                
  +                                
  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_ACTUAL, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @CalculationDateAsOf                                
    AND                                
    @IM_IncludeRE = 1                                
   ,                                
    im.A_ACTUAL_SLOPE * IIF(im.A_FINANCIAL = 1, multiActualToDate.A_Financial_Multiplier, multiActualToDate.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [Actual_To_Date],                                
                                
                                
  -- Forecast to Date                  
  (ISNULL(SUM(                                
   IIF(                                
    ISNULL(im.A_FORECAST, @DefaultMilestoneDate) BETWEEN @FilterOneTimeDateStart AND @CalculationDateAsOf                                
    AND                                
    @IM_IncludeOT = 1                                
   ,                                
    im.A_FORECAST_INTERCEPT * IIF(im.A_FINANCIAL = 1, multiForecastToDate.A_EXCHANGE_RATE, 1)                                
   ,                                
    NULL                                
   )                                
  ),0)                            +                                
  ISNULL((SUM(                                
   IIF(                                
    ISNULL(im.A_FORECAST, @DefaultMilestoneDate) BETWEEN @FilterRecurringDateStart AND @CalculationDateAsOf                                
   AND                                
    @IM_IncludeRE = 1                                
   ,                                
    im.A_FORECAST_SLOPE * IIF(im.A_FINANCIAL = 1, multiForecastToDate.A_Financial_Multiplier, multiForecastToDate.A_MULTIPLIER)                                
   ,                                
    NULL                                
   )                                
  )/@MultiplierPerYear),0)) / ISNULL(@NumericFactor, biF.A_NUMERIC_FACTOR) AS [Update_To_Date]    
   
  into #tempImpactData    
  FROM    
  (SELECT DISTINCT 
  	A_FK_Program,  
	A_FK_PROJECT,    
	A_FK_Roadmap, 
	A_FK_MILESTONE, 
	A_FK_BASE_IMPACT
  FROM #FilteredRoadmaps ) RMi                                         
  left join reporting.view_milestone msv on  msv.A_FK_Roadmap =rmi.A_FK_Roadmap and msv.A_FK_MILESTONE=RMi.A_FK_MILESTONE and msv.A_FK_program=@programID                                   
  LEFT Join reporting.VIEW_IMPACT im with(NOEXPAND) on im.A_FK_ROADMAP = rmi.A_FK_Roadmap  AND (im.A_FK_BASE_IMPACT = @BaseImpactID OR @NoneBaseImpactSelected = 1) and im.A_FK_program=@programID                          
  LEFT Join reporting.VIEW_BASE_IMPACT_FACTOR biF with(NOEXPAND) on biF.A_FK_BASE_IMPACT = im.A_FK_BASE_IMPACT AND bif.A_FK_PROGRAM_CURRENCY = @ReportCurrency                                
  left JOIN @FilteredMilestones fm ON fm.[A_FK_UniqueIdentifier] = im.A_FK_MILESTONE                           
                          
  Left  Join -- Plan                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiPlan                                
   ON                                
    multiPlan.[A_Date] = ISNULL(im.A_PLAN, @DefaultMilestoneDate)                             
    AND            multiPlan.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiPlan.A_FK_MULTIPLIER_SET = @MultiplierSetID                                
                                
  Left Outer Join -- Actual                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiActual                                
   ON                                
    multiActual.[A_Date] = ISNULL(im.A_Actual, @DefaultMilestoneDate)                                
    AND                                
    multiActual.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiActual.A_FK_MULTIPLIER_SET = @MultiplierSetID                                
            
        Left Outer Join -- Forecast                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiForecast                                
   ON                  
    multiForecast.[A_Date] = ISNULL(im.A_Forecast, @DefaultMilestoneDate)                                
    AND                                
    multiForecast.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiForecast.A_FK_MULTIPLIER_SET = @MultiplierSetID                                
                                
        -------------------------------------------------------------                                
                                
  Left Outer Join -- Plan to Date                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiPlanToDate                                
   ON                                
    multiPlanToDate.[A_Date] = ISNULL(im.A_Plan, @DefaultMilestoneDate)                                
    AND                           
    multiPlanToDate.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiPlanToDate.A_FK_MULTIPLIER_SET = @MultiplierSetIDa                                 
                                    
  Left Outer Join -- Actual to Date                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiActualToDate                                
   ON                                
    multiActualToDate.[A_Date] = ISNULL(im.A_Actual, @DefaultMilestoneDate)                                
   AND                                
    multiActualToDate.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiActualToDate.A_FK_MULTIPLIER_SET = @MultiplierSetIDa                                 
                                
        Left Outer Join -- Forecast to Date                                
   [reporting].[TBL_MULTIPLIER_SET_DAY] multiForecastToDate                                
   ON                                
    multiForecastToDate.[A_Date] = ISNULL(im.A_Forecast, @DefaultMilestoneDate)                                
    AND                                
    multiForecastToDate.[A_FK_PROGRAM_CURRENCY] = im.A_FK_PROGRAM_CURRENCY                                
    AND                                
    multiForecastToDate.A_FK_MULTIPLIER_SET = @MultiplierSetIDa       
       
  group by     
    RMi.A_FK_Program,  
	RMi.A_FK_PROJECT,    
	RMi.A_FK_BASE_IMPACT,  
	RMi.A_FK_Roadmap, 
	RMi.A_FK_MILESTONE , 
    biF.A_NUMERIC_FACTOR   
   
    
    
 Select  distinct  
  Case When PJ.A_ID = Null Then PG.A_PROGRAM Else PJ.A_PROJECT End AS [PROJ_PARENT],                                
  PJ.A_ID AS P_ID,            
  Concat(U_WSO.A_LAST_NAME, Case When U_WSO.A_FIRST_NAME IS NULL or LTrim(RTRIM(U_WSO.A_FIRST_NAME)) = '' Then '' Else ', ' END , U_WSO.A_FIRST_NAME ) AS [WS_OWNER],                                 
  PJ.A_Number as [PJ_Num],                                
  RM.A_ID AS [RM_ID],                                
  (case                           
 when rmV.[Roadmap_TL_DICE] = 1 then 'Black'                
 when rmV.[Roadmap_TL_DICE] = 2 then 'White'                          
 when rmV.[Roadmap_TL_DICE] = 3 then 'Green'                          
 when rmV.[Roadmap_TL_DICE] = 4 then 'Yellow'                          
 else 'Red' end  )           AS [RM_TL_DICE],                                
  (case                           
 when rmV.[Roadmap_TL_Milestone] = 1 then 'Black'                          
 when rmV.[Roadmap_TL_Milestone] = 2 then 'White'                          
 when rmV.[Roadmap_TL_Milestone] = 3 then 'Green'                          
 when rmV.[Roadmap_TL_Milestone] = 4 then 'Yellow'                          
 else 'Red' end   )           AS [RM_TL_MS],                           
  (case                           
 when rmV.[Roadmap_TL_Impact]  =1 then 'Black'                          
 when rmV.[Roadmap_TL_Impact]  =2 then 'White'                          
 when rmV.[Roadmap_TL_Impact]  =3 then 'Green'                          
 when rmV.[Roadmap_TL_Impact]  =4 then 'Yellow'                          
 else 'Red' end   ) as [RM_TL_IM],                          
(case                           
 when  rmV.[Roadmap_TL_Overall]=1 then 'Black'                          
 when  rmV.[Roadmap_TL_Overall]=2 then 'White'                          
 when  rmV.[Roadmap_TL_Overall]=3 then 'Green'                          
 when  rmV.[Roadmap_TL_Overall]=4 then 'Yellow'                          
 else 'Red' end ) as     [RM_TL_OVERALL],                                
  rmV.[A_ROADMAP_NUMBER]         AS [RM_NUMBER],                          
  Concat(U_RMO.A_LAST_NAME, Case When U_RMO.A_FIRST_NAME IS NULL or LTrim(RTRIM(U_RMO.A_FIRST_NAME)) = '' Then '' Else ', ' END , U_RMO.A_FIRST_NAME ) AS [RM_OWNER],                                
Concat(U_RMA.A_LAST_NAME, Case When U_RMA.A_FIRST_NAME IS NULL or LTrim(RTRIM(U_RMA.A_FIRST_NAME)) = '' Then '' Else ', ' END , U_RMA.A_FIRST_NAME ) AS [RM_APPROVER],                                
  RM.A_ROADMAP           AS [MEMBER_NAME],                               
  Convert(nvarchar(max),dbo.StripHTML(RM.A_DESCRIPTION)) as [ROADMAP_DESCRIPTION],                           
  (case                           
 when #temp22.A_FK_Traffic_Light_Overall = 1 then 'Black'                          
 when #temp22.A_FK_Traffic_Light_Overall = 2 then 'White'                          
 when #temp22.A_FK_Traffic_Light_Overall = 3 then 'Green'                          
 when #temp22.A_FK_Traffic_Light_Overall = 4 then 'Yellow'                          
 else 'Red' end ) as [Status_2Weeks_ago],                          
  (case                           
 when #temp33.A_FK_Traffic_Light_Overall = 1 then 'Black'                          
 when #temp33.A_FK_Traffic_Light_Overall = 2 then 'White'                          
 when #temp33.A_FK_Traffic_Light_Overall = 3 then 'Green'                          
 when #temp33.A_FK_Traffic_Light_Overall = 4 then 'Yellow'                          
 else 'Red' end ) as [Status_1Weeks_ago],                              
  msv.A_Milestone as [A_Milestone],                          
  msv.[A_Sort_order] as [Milestone_Sort_order],                          
  CAST(IIF(year(msv.[A_Plan]) > '1900', msv.[A_Plan], NULL) AS datetime) as [A_Plan],                          
  CAST(IIF(year(msv.[A_Update]) > '1900', msv.[A_Update], NULL) AS datetime) as [A_Forecast],                      
  datediff(day, msv.A_Plan, @Today)             AS [DELAY_OVERDUE],                      
  @MilestoneDueInNextNDays as MilestoneDueInNextNDays  ,                          
  bi.A_BASE_IMPACT          AS [BI_NAME],                                
  bi.A_UNIT  AS [BI_UNIT],                                
  CASE WHEN bi.A_FINANCIAL=1 THEN @CurrencyCode  ELSE '' END AS [CURRENCY_CODE],                                
  STG.A_STAGE                                             AS [RM_STAGE],                          
  CAST(IIF(year(RSTG.[A_Plan]) > '1900', RSTG.[A_Plan], NULL) AS datetime) as [G4_DueDate]  ,                              
  Year(PG.A_START_DATE)    AS [PG_START_YEAR],                                
  Year(PG.A_END_DATE)                                     AS [PG_END_YEAR],  
  imp.[Plan],  
  imp.[Update],  
  imp.[Actual],  
  imp.[Plan_To_Date],    
  imp.[Actual_To_Date],    
  imp.[Update_To_Date],  
  msv.A_FK_Milestone,  
  imp.A_FK_Project,  
  imp.A_FK_BASE_IMPACT,  
  PG.A_DICE_ENABLED,   
  frms.[Milestone_Owner],
  frms.[Project_Status_Rationale],       
  frms.[Project_Decisions_Needed],       
  frms.[Project_TMO_Comments],           
  frms.[Project_Actions_for_Next_Week],  
  frms.[Project_Actions_from_Last_Week], 
  frms.[Roadmap_Interdependency],
  'ng-program-tree/project?programId=' + @ProgramIdStr + '&projectId=' + IIF(pj.A_FK_PROJECT_PARENT IS NULL, '', CONVERT(VARCHAR(50), pj.A_ID)) AS ProjectURL,              
  'ng-program-tree/initiative?programId=' + @ProgramIdStr + '&roadmapId=' + LOWER(CONVERT(VARCHAR(50), RM.A_ID )) as RoadmapURL              
  into #result         
 From  #tempImpactData imp                         
  left Join TBL_ROADMAP RM on imp.A_FK_Roadmap = RM.A_ID                                
  left Join reporting.VIEW_ROADMAP rmV ON rmV.A_FK_ROADMAP = imp.A_FK_roadmap                              
  left join reporting.view_milestone msv on  imp.A_FK_roadmap = msv.A_FK_Roadmap   and  imp.A_FK_Milestone = msv.A_FK_Milestone   
  left join TBL_BASE_IMPACT bi on bi.A_ID=imp.A_FK_BASE_IMPACT  
  left join #temp22  on #temp22.A_FK_roadmap=imp.A_FK_roadmap                          
  left join #temp33  on #temp33.A_FK_roadmap=imp.A_FK_roadmap                         
  left join #FilteredRoadmaps frms  on frms.A_FK_roadmap=imp.A_FK_roadmap  and  frms.A_FK_MILESTONE=imp.A_FK_MILESTONE and  frms.A_FK_BASE_IMPACT=imp.A_FK_BASE_IMPACT                                  
  Left  Join TBL_STAGE STG on RM.A_FK_STAGE = STG.A_ID                             
  left join  tbl_roadmap_stage RSTG on RSTG.A_FK_Roadmap=rmv.A_FK_roadmap and RSTG.A_FK_Stage='00DE18B3-4D98-4D31-A419-028FF4E8E1F0'                               
  Left  Join TBL_PROGRAM PG on imp.A_FK_Program = PG.A_ID               
  Left  Join TBL_PROJECT PJ on imp.A_FK_Project = PJ.A_ID                          
  Left  Join TBL_USER_ROLE UR_RMO on imp.A_FK_Roadmap = UR_RMO.A_FK_ROADMAP and UR_RMO.A_FK_ROLE = 5                                
  Left  Join TBL_USER U_RMO on UR_RMO.A_FK_USER = U_RMO.A_ID                                
  Left  Join TBL_USER_ROLE UR_RMA on imp.A_FK_Roadmap = UR_RMA.A_FK_ROADMAP and UR_RMA.A_FK_ROLE = 6                                
  Left  Join TBL_USER U_RMA on UR_RMA.A_FK_USER = U_RMA.A_ID                                 
  Left  Join TBL_USER_ROLE UR_WSO on PJ.A_ID = UR_WSO.A_FK_PROJECT and UR_WSO.A_FK_ROLE = 4                              
  Left  Join TBL_USER U_WSO on UR_WSO.A_FK_USER = U_WSO.A_ID                               
 where imp.A_FK_Program=@programID    
     
    

  BEGIN TRY          
   BEGIN TRANSACTION       
    
    MERGE INTO [reporting].[TBL_CACHE_DueOverdueUpcomingMSLevel] AS TARGET          
     USING (          
      SELECT          
			@ReportCacheID A_FK_REPORT_CACHE,          
			@ReportFilterCacheID A_FK_REPORT_FILTER_CACHE,          
			n.[A_FK_SNAPSHOT],    
			n.[A_LAST_MODIFIED_FOR_CACHE_UTC],    
			n.[A_ROADMAP_SUBSET_HASH],    
			vr.PROJ_PARENT,  
			vr.P_ID,  
			vr.WS_OWNER,  
			vr.PJ_Num,  
			vr.RM_ID,  
			vr.RM_TL_DICE,  
			vr.RM_TL_MS,  
			vr.RM_TL_IM,  
			vr.RM_TL_OVERALL,  
			vr.RM_NUMBER,  
			vr.RM_OWNER,  
			vr.RM_APPROVER,  
			vr.MEMBER_NAME,  
			vr.ROADMAP_DESCRIPTION,  
			vr.Status_2Weeks_ago,  
			vr.Status_1Weeks_ago,  
			vr.A_Milestone,  
			vr.Milestone_Sort_order,  
			vr.A_Plan,  
			vr.A_Forecast,  
			vr.DELAY_OVERDUE,  
			vr.MilestoneDueInNextNDays,  
			vr.Milestone_Owner,  
			vr.BI_NAME,  
			vr.BI_UNIT,  
			vr.CURRENCY_CODE,  
			vr.RM_STAGE,  
			vr.G4_DueDate,  
			vr.PG_START_YEAR,  
			vr.PG_END_YEAR,  
			vr.Project_Status_Rationale,  
			vr.Project_Decisions_Needed,  
			vr.Project_TMO_Comments,  
			vr.Project_Actions_for_Next_Week,  
			vr.Project_Actions_from_Last_Week,  
			vr.Roadmap_Interdependency, 
			vr.[Plan],  
			vr.Actual,  
			vr.[UPDATE],  
			vr.Plan_To_Date,  
			vr.Actual_To_Date,  
			vr.Update_To_Date,  
			vr.A_FK_Milestone,
			vr.A_FK_BASE_IMPACT,
			vr.A_DICE_ENABLED,
			vr.ProjectURL,  
			vr.RoadmapURL
      FROM          
       #result vr        
      JOIN  @CachedProjectSnapshotNeeded n  ON n.A_FK_PROJECT = vr.A_FK_PROJECT          
     ) AS Src           
     ON           
     (          
		   Target.A_FK_REPORT_CACHE = Src.A_FK_REPORT_CACHE           
		   AND Target.A_FK_REPORT_FILTER_CACHE = Src.A_FK_REPORT_FILTER_CACHE          
		   AND Target.A_FK_SNAPSHOT = Src.A_FK_SNAPSHOT          
		   AND Target.A_LAST_MODIFIED_FOR_CACHE_UTC = Src.A_LAST_MODIFIED_FOR_CACHE_UTC          
		   AND Target.A_ROADMAP_SUBSET_HASH = Src.A_ROADMAP_SUBSET_HASH          
		   AND Target.P_ID = Src.P_ID       
		   AND Target.[A_FK_MILESTONE] = Src.[A_FK_MILESTONE]          
		   AND Target.[A_FK_BASE_IMPACT] = Src.[A_FK_BASE_IMPACT]          
     )             
     WHEN NOT MATCHED BY TARGET THEN          
    INSERT          
    VALUES (    
			Src.[A_FK_REPORT_CACHE]  ,    
			Src.[A_FK_REPORT_FILTER_CACHE]  ,    
			Src.[A_FK_SNAPSHOT]  ,    
			Src.[A_LAST_MODIFIED_FOR_CACHE_UTC],    
			Src.[A_ROADMAP_SUBSET_HASH],    
			Src.PROJ_PARENT,  
			Src.P_ID,  
			Src.WS_OWNER,  
			Src.PJ_Num,  
			Src.RM_ID,  
			Src.RM_TL_DICE,  
			Src.RM_TL_MS,  
			Src.RM_TL_IM,  
			Src.RM_TL_OVERALL,  
			Src.RM_NUMBER,  
			Src.RM_OWNER,  
			Src.RM_APPROVER,  
			Src.MEMBER_NAME,  
			Src.ROADMAP_DESCRIPTION,  
			Src.Status_2Weeks_ago,  
			Src.Status_1Weeks_ago,  
			Src.A_Milestone,  
			Src.Milestone_Sort_order,  
			Src.A_Plan,  
			Src.A_Forecast,  
			Src.DELAY_OVERDUE,  
			Src.MilestoneDueInNextNDays,  
			Src.Milestone_Owner,  
			Src.BI_NAME,  
			Src.BI_UNIT,  
			Src.CURRENCY_CODE,  
			Src.RM_STAGE,  
			Src.G4_DueDate,  
			Src.PG_START_YEAR,  
			Src.PG_END_YEAR,  
			Src.Project_Status_Rationale,  
			Src.Project_Decisions_Needed,  
			Src.Project_TMO_Comments,  
			Src.Project_Actions_for_Next_Week,  
			Src.Project_Actions_from_Last_Week,  
			Src.Roadmap_Interdependency, 
			Src.[Plan],  
			Src.Actual,  
			Src.[UPDATE],  
			Src.Plan_To_Date,  
			Src.Actual_To_Date,  
			Src.Update_To_Date,  
			Src.A_FK_Milestone,
			Src.A_FK_BASE_IMPACT,
			Src.A_DICE_ENABLED,
			Src.ProjectURL,  
			Src.RoadmapURL
		)  ;        
    
  -- Mark these projects as having the cached value saved          
    EXEC reporting.spMarkReportProjectsCached                 
     @ReportFilterCacheID = @ReportFilterCacheID,          
     @ReportCacheID = @ReportCacheID,          
     @CachedProjectSnapshotNeeded = @CachedProjectSnapshotNeeded          
   COMMIT TRANSACTION          
  END TRY          
  BEGIN CATCH          
   ROLLBACK TRANSACTION          
   DECLARE @ErrorMessage NVARCHAR(4000);          
   DECLARE @ErrorSeverity INT;          
   DECLARE @ErrorState INT;          
          
   SELECT           
    @ErrorMessage = ERROR_MESSAGE(),          
    @ErrorSeverity = ERROR_SEVERITY(),          
    @ErrorState = ERROR_STATE();          
   RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)          
  END CATCH          
    
 END      
      
     
   SELECT                          
   o.*                          
  INTO                          
   #CachedFinalResult                          
  FROM                          
   @CachedProjectSnapshotInReport r                          
  JOIN                          
   reporting.TBL_CACHE_DueOverdueUpcomingMSLevel o                          
   ON                          
    o.A_FK_REPORT_CACHE = @ReportCacheID AND                      
    o.A_FK_REPORT_FILTER_CACHE = @ReportFilterCacheID AND                          
    o.A_FK_SNAPSHOT = r.A_FK_SNAPSHOT AND                          
    o.A_LAST_MODIFIED_FOR_CACHE_UTC = r.A_LAST_MODIFIED_FOR_CACHE_UTC AND                          
    o.A_ROADMAP_SUBSET_HASH = r.A_ROADMAP_SUBSET_HASH AND                          
    o.P_ID = r.A_FK_PROJECT      
    
     
   SELECT  r.* 
   from   #CachedFinalResult   r   
   join TBL_TREE  Rmi on r.P_ID=Rmi.A_FK_PROJECT
   order by Rmi.A_PATH,r.delay_overdue
      
