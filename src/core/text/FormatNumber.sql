CREATE OR ALTER FUNCTION viz.FormatNumber(@Value float,@Format varchar(24),@Decimals tinyint) RETURNS nvarchar(80) AS
BEGIN
    IF @Value IS NULL OR ABS(@Value)>1e16 OR @Decimals IS NULL OR @Decimals>6 OR @Format IS NULL OR @Format COLLATE Latin1_General_100_BIN2 NOT IN('number','compact','integer','percent','duration-ms','bytes-iec') RETURN NULL;
    DECLARE @Suffix nvarchar(8)=N'',@Divisor float=1,@A float=ABS(@Value),@Text nvarchar(80);
    IF @Format='integer' SET @Decimals=0;
    IF @Format='percent' BEGIN SET @Value*=100; SET @Suffix=N'%'; END;
    IF @Format='compact' BEGIN
      SELECT TOP(1) @Divisor=D,@Suffix=S FROM (VALUES(1e15,N'P'),(1e12,N'T'),(1e9,N'G'),(1e6,N'M'),(1e3,N'k'),(1e0,N'')) v(D,S) WHERE @A>=D OR D=1 ORDER BY D DESC;
    END;
    IF @Format='bytes-iec' BEGIN
      SELECT TOP(1) @Divisor=D,@Suffix=S FROM (VALUES(1125899906842624e0,N'PiB'),(1099511627776e0,N'TiB'),(1073741824e0,N'GiB'),(1048576e0,N'MiB'),(1024e0,N'KiB'),(1e0,N'B')) v(D,S) WHERE @A>=D OR D=1 ORDER BY D DESC;
    END;
    IF @Format='duration-ms' BEGIN
      SELECT TOP(1) @Divisor=D,@Suffix=S FROM (VALUES(86400000e0,N'd'),(3600000e0,N'h'),(60000e0,N'min'),(1000e0,N's'),(1e0,N'ms')) v(D,S) WHERE @A>=D OR D=1 ORDER BY D DESC;
    END;
    SET @Value=ROUND(@Value/@Divisor,@Decimals);
    IF @Value=0 SET @Value=0;
    SET @Text=LTRIM(STR(@Value,60,@Decimals));
    IF CHARINDEX('.',@Text)>0 BEGIN
      WHILE RIGHT(@Text,1)=N'0' SET @Text=LEFT(@Text,LEN(@Text)-1);
      IF RIGHT(@Text,1)=N'.' SET @Text=LEFT(@Text,LEN(@Text)-1);
    END;
    RETURN @Text+@Suffix;
END;
