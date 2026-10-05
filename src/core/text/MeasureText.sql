CREATE OR ALTER FUNCTION viz.MeasureText(@Text nvarchar(max),@Size float)
RETURNS TABLE AS RETURN
SELECT Width=CASE WHEN N=0 THEN 0 ELSE (N-1)*viz.TextAdvance(@Size)+0.6*@Size+1.5 END,
       Height=CASE WHEN N=0 THEN 0 ELSE @Size+1.5 END,DisplayText,
       WasSubstituted=CONVERT(bit,CASE WHEN DisplayText COLLATE Latin1_General_100_BIN2=@Text COLLATE Latin1_General_100_BIN2 AND DATALENGTH(DisplayText)=DATALENGTH(@Text) THEN 0 ELSE 1 END)
FROM (SELECT DisplayText=viz.DisplayText(@Text)) d
CROSS APPLY(SELECT N=LEN(DisplayText+N'!')-1) n
WHERE @Size BETWEEN 6 AND 40 AND @Text IS NOT NULL AND DATALENGTH(@Text)<=2400;
