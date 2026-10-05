CREATE TABLE viz.LibraryVersion (
    Singleton bit NOT NULL PRIMARY KEY CHECK (Singleton=1),
    Version varchar(32) NOT NULL,
    InstalledUtc datetime2(3) NOT NULL
);
