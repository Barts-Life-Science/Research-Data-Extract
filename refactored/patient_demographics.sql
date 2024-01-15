USE [BH_RESEARCH]
GO

SELECT
    gend.alias_nhs_cd_alias AS gender_cd,
    gend.code_disp_txt AS gender,
    eth.alias_nhs_cd_alias AS ethnic_cd,
    eth.code_desc_txt AS ethnicity,
    pat.deceased_dt_tm AS date_of_death,
    pat.person_id,
    pat.local_patient_ident AS mrn,
    marital_status_cd AS marital_status_cd,
    mart.code_desc_txt AS marital_status,
    language_cd AS language_cd,
    lang.code_desc_txt AS language,
    religion_cd AS religion_cd,
    reli.code_desc_txt AS religion,
    REPLACE(pat.nhs_nbr_ident, '-', '') AS nhs_number,
    CAST(pat.birth_dt_tm AS DATE) AS date_of_birth,
    (
        SELECT TOP (1) postcode_txt
        FROM bh_datawarehouse.dbo.pi_cde_person_patient_address AS a
        WHERE a.person_id = pat.person_id
        ORDER BY end_effective_dt_tm DESC
    ) AS postcode,
    (
        SELECT TOP (1) city_txt
        FROM bh_datawarehouse.dbo.pi_cde_person_patient_address AS a
        WHERE a.person_id = pat.person_id
        ORDER BY end_effective_dt_tm DESC
    ) AS city
INTO bh_research.dbo.refactored_rde_patient_demographics

FROM bh_datawarehouse.dbo.pi_cde_person_patient AS pat WITH (NOLOCK)
INNER JOIN bh_research.dbo.research_patients AS res
    --ON  REPLACE(Pat.[NHS_NBR_IDENT],'-','')=Res.NHS_Number
    ON pat.person_id = res.personid
LEFT OUTER JOIN
    bh_datawarehouse.dbo.pi_lkp_cde_code_value_ref AS eth WITH (NOLOCK)
    ON pat.ethnic_group_cd = eth.code_value_cd
LEFT OUTER JOIN
    bh_datawarehouse.dbo.pi_lkp_cde_code_value_ref AS gend WITH (NOLOCK)
    ON pat.gender_cd = gend.code_value_cd
LEFT OUTER JOIN
    bh_datawarehouse.dbo.pi_lkp_cde_code_value_ref AS mart WITH (NOLOCK)
    ON pat.marital_status_cd = mart.code_value_cd
LEFT OUTER JOIN
    bh_datawarehouse.dbo.pi_lkp_cde_code_value_ref AS lang WITH (NOLOCK)
    ON pat.language_cd = lang.code_value_cd
LEFT OUTER JOIN
    bh_datawarehouse.dbo.pi_lkp_cde_code_value_ref AS reli WITH (NOLOCK)
    ON pat.religion_cd = reli.code_value_cd
WHERE res.extract_id = @EXTRACT_ID
