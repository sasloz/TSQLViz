-- Synthetic observations: negative, observed zero, positive and missing.
DECLARE @Data viz.CategoryValue_v1;
INSERT @Data VALUES
 (N'a',N'a',N'Negative',1,N'value',N'Value',1,-5,NULL),
 (N'b',N'b',N'Observed zero',2,N'value',N'Value',1,0,NULL),
 (N'c',N'c',N'Positive',3,N'value',N'Value',1,10,NULL),
 (N'd',N'd',N'Missing',4,N'value',N'Value',1,NULL,NULL);
DECLARE @Context viz.Context_v1;
INSERT @Context VALUES
 ('marks',N'One category is one synthetic signed observation.'),
 ('source',N'Synthetic fixture; four categories a..d.'),
 ('time',N'Demonstration values; no measurement interval.'),
 ('population',N'All four supplied categories; no filtering or aggregation.'),
 ('reading',N'Compare direction and length from zero; a missing value is unknown.'),
 ('observation',N'placeholder'),
 ('limitation',N'Synthetic values illustrate encoding; they do not describe a server.');
DECLARE @Labels viz.ItemLabel_v1;
INSERT @Labels SELECT ItemKey,CONCAT(N'B',CategoryOrder),CategoryLabel FROM @Data;
UPDATE @Context SET Content=CONCAT(N'Observed sum=',(SELECT SUM(Value) FROM @Data),N'; zero categories=',(SELECT COUNT(*) FROM @Data WHERE Value=0),N'; missing=',(SELECT COUNT(*) FROM @Data WHERE Value IS NULL),N'.') WHERE FieldKey='observation';
EXEC viz.BarChart @Data=@Data,@Title=N'Which categories increased or decreased?',@ValueLabel=N'Change (units)',@Context=@Context,@ItemLabels=@Labels;
