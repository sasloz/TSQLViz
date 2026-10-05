CREATE TYPE viz.Tick_v1 AS TABLE(
    TickOrder int NOT NULL PRIMARY KEY,Position float NOT NULL,Label nvarchar(400) NOT NULL
);
