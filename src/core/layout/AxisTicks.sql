CREATE OR ALTER FUNCTION viz.AxisTicks(@Min float,@Max float,@Start float,@End float,@Scale varchar(12),@Format varchar(24))
RETURNS @Ticks TABLE(TickOrder int PRIMARY KEY,Position float,Label nvarchar(400)) AS
BEGIN
    DECLARE @Values TABLE(TickOrder int PRIMARY KEY,Value float,Label nvarchar(400));
    IF @Format='utc-time' INSERT @Values SELECT TickOrder,Value,NULL FROM viz.TicksTime(@Min,@Max,6);
    ELSE IF @Scale='log' INSERT @Values SELECT TickOrder,Value,NULL FROM viz.TicksLog(@Min,@Max);
    ELSE IF @Format='duration-ms' INSERT @Values SELECT TickOrder,Value,NULL FROM viz.TicksDuration(@Min,@Max,6);
    ELSE IF @Format='bytes-iec' INSERT @Values SELECT TickOrder,Value,NULL FROM viz.TicksBytes(@Min,@Max,6);
    ELSE INSERT @Values SELECT TickOrder,Value,NULL FROM viz.TicksLinear(@Min,@Max,6);
    DECLARE @Decimals tinyint=2;
    IF @Format='utc-time' BEGIN
      UPDATE @Values SET Label=CASE WHEN CONVERT(date,viz.EpochToTime(@Min))<>CONVERT(date,viz.EpochToTime(@Max))
        THEN SUBSTRING(CONVERT(nvarchar(23),viz.EpochToTime(Value),121),6,CASE WHEN @Max-@Min<1000 THEN 18 ELSE 14 END)
        WHEN @Max-@Min<1000 THEN SUBSTRING(CONVERT(nvarchar(23),viz.EpochToTime(Value),121),12,12) ELSE viz.FormatTime(Value,'utc-time') END;
    END ELSE BEGIN
      UPDATE @Values SET Label=viz.FormatNumber(Value,@Format,@Decimals);
      WHILE EXISTS(SELECT Label FROM @Values GROUP BY Label HAVING COUNT(*)>1) AND @Decimals<6 BEGIN
        SET @Decimals+=1; UPDATE @Values SET Label=viz.FormatNumber(Value,@Format,@Decimals);
      END;
    END;
    IF EXISTS(SELECT 1 FROM @Values WHERE Label IS NULL) OR EXISTS(SELECT Label FROM @Values GROUP BY Label HAVING COUNT(*)>1) RETURN;
    INSERT @Ticks SELECT TickOrder,CASE WHEN @Scale='log' THEN viz.ScaleLog(Value,@Min,@Max,@Start,@End,10) ELSE viz.ScaleLinear(Value,@Min,@Max,@Start,@End,0) END,Label FROM @Values;
    RETURN;
END;
