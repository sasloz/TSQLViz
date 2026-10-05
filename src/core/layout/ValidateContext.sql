CREATE OR ALTER PROCEDURE viz.ValidateContext
    @Context viz.Context_v1 READONLY,@Items viz.ItemLabel_v1 READONLY
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM @Context) BEGIN
      IF EXISTS(SELECT 1 FROM @Items) THROW 51001,'Item labels require Context_v1.',1;
      RETURN; -- Legacy calls remain compatible; they do not satisfy K01-K10.
    END;
    IF (SELECT COUNT(*) FROM @Context)<>7 OR EXISTS(SELECT 1 FROM @Context WHERE
      FieldKey NOT IN('marks','source','time','population','reading','observation','limitation') OR
      NULLIF(LTRIM(RTRIM(viz.DisplayText(Content))),N'') IS NULL OR DATALENGTH(Content)>700)
      THROW 51001,'Context requires marks, source, time, population, reading, observation and limitation.',1;
    IF EXISTS(SELECT 1 FROM @Items WHERE Code='' OR Code LIKE '%[^A-Z0-9]%' COLLATE Latin1_General_100_BIN2 OR
      DATALENGTH(Code)<>DATALENGTH(RTRIM(Code)) OR NULLIF(LTRIM(RTRIM(viz.DisplayText(Name))),N'') IS NULL)
      THROW 51001,'Item codes require 1..12 uppercase ASCII letters/digits and a nonempty name.',1;
END;
