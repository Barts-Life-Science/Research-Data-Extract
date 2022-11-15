-- Cleans a string for inclusion in a csv file


IF OBJECT_ID (N'dbo.csvString', N'FN') IS NOT NULL
    DROP FUNCTION csvString;
  GO
  CREATE FUNCTION dbo.csvString(@instring varchar(MAX))
  RETURNS VARCHAR(MAX)
  AS

  BEGIN
	DECLARE @replace_character VARCHAR(10)
	SELECT @replace_character = ''''
    IF(@instring IS NOT NULL)
	    BEGIN
		  SELECT @instring = RTRIM(LTRIM(@instring))
	      IF(LEN(@instring) > 100 OR @instring LIKE '%,%' OR @instring LIKE '%' + CHAR(10) + '%' OR @instring LIKE '%' + CHAR(13) + '%' OR @instring LIKE '%' + '"' + '%')
	        BEGIN
	          IF(LEFT(@instring, 1) = '"')
		        SELECT @instring = right(@instring, len(@instring)-1)
		      IF(RIGHT(@instring, 1)= '"')
			    SELECT  @instring = left(@instring, len(@instring)-1)
              SELECT @instring = REPLACE(@instring, '"', @replace_character)
			  SELECT @instring = '"' + @instring + '"'
			  return @instring  COLLATE SQL_Latin1_General_CP1_CS_AS
		    END
		   ELSE
              return @instring  COLLATE SQL_Latin1_General_CP1_CS_AS
	    END
    return ''
  END;
