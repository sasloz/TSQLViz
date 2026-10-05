CREATE OR ALTER FUNCTION viz.DisplayText(@Text nvarchar(max)) RETURNS nvarchar(max) AS
BEGIN
    IF @Text IS NULL RETURN NULL;
    DECLARE @Result nvarchar(max)=N'',@I int=1,@C nvarchar(2),@N int;
    WHILE @I<=LEN(@Text COLLATE Latin1_General_100_CI_AS_SC+N'!')-1 BEGIN
        SET @C=SUBSTRING(@Text COLLATE Latin1_General_100_CI_AS_SC,@I,1);
        SET @N=UNICODE(@C COLLATE Latin1_General_100_CI_AS_SC);
        SET @Result+=CASE
          WHEN @N BETWEEN 65 AND 90 OR @N BETWEEN 97 AND 122 OR @N BETWEEN 48 AND 57 THEN @C
          WHEN CHARINDEX(@C COLLATE Latin1_General_100_BIN2,N' .,:;!?%/\-+()[]_=<>#*' COLLATE Latin1_General_100_BIN2)>0 THEN @C
          WHEN @N IN(9,10,13) THEN N' '
          WHEN @N=196 THEN N'Ae' WHEN @N=214 THEN N'Oe' WHEN @N=220 THEN N'Ue'
          WHEN @N=228 THEN N'ae' WHEN @N=246 THEN N'oe' WHEN @N=252 THEN N'ue'
          WHEN @N=223 THEN N'ss' WHEN @N=181 THEN N'u'
          WHEN @N IN(8211,8212,8722) THEN N'-' WHEN @N=8230 THEN N'...' ELSE N'?' END;
        SET @I+=1;
    END;
    RETURN @Result;
END;
