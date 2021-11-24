DROP PROCEDURE IF EXISTS uploadSummary;

GO
CREATE PROCEDURE uploadSummary
    @json NVARCHAR(MAX),
    @seasonNumber INT,
    @gameNumber INT
AS
    DECLARE @seasonError NVARCHAR(MAX) = CONCAT('Season ', @seasonNumber, ' does not exist');
    IF NOT EXISTS (SELECT * FROM Season WHERE number = @seasonNumber)
        THROW 51000, @seasonError, 1;

    DELETE FROM Game WHERE number = @gameNumber AND seasonNumber = @seasonNumber;

    DECLARE @date DATETIMEOFFSET = (SELECT TOP 1 value FROM STRING_SPLIT(JSON_VALUE(@json, '$.date'), '['));
    DECLARE @gameType NCHAR(3) = JSON_VALUE(@json, '$.gameType');
    DECLARE @gameLength INT = JSON_VALUE(@json, '$.gameLength');
    DECLARE @teams TABLE (
        name NVARCHAR(MAX),
        color0 INT,
        color1 INT,
        members NVARCHAR(MAX)
    );
    DECLARE @players TABLE (
        name NVARCHAR(MAX),
        place INT,
        timeSurvived INT,
        killedBy UNIQUEIDENTIFIER,
        uuid UNIQUEIDENTIFIER,
        teamId INT
    );

    INSERT INTO @players SELECT * FROM OPENJSON(JSON_QUERY(@json, '$.players')) WITH (
        name NVARCHAR(MAX) '$.name',
        place INT '$.place',
        timeSurvived INT '$.timeSurvived',
        killedBy UNIQUEIDENTIFIER '$.killedBy',
        uuid UNIQUEIDENTIFIER '$.uuid',
        teamID INT
    );
    INSERT INTO @teams SELECT * FROM OPENJSON(JSON_QUERY(@json, '$.teams')) WITH (
        name NVARCHAR(MAX) '$.name',
        color0 INT '$.color0',
        color1 INT '$.color1',
        members NVARCHAR(MAX) '$.members' AS JSON
    );

    -- add the game
    INSERT INTO Game (seasonNumber, number, startDate, type, matchTime) VALUES (@seasonNumber, @gameNumber, @date, @gameType, @gameLength)
    DECLARE @gameId INT = @@IDENTITY;

    DECLARE @tname NVARCHAR(MAX);
    DECLARE @color0 INT;
    DECLARE @color1 INT;
    DECLARE @membersString NVARCHAR(MAX);
    DECLARE @teamId INT;
    DECLARE @membersTable TABLE ( uuid UNIQUEIDENTIFIER );

    -- add teams
    DECLARE @teamIterator CURSOR;
    SET @teamIterator = CURSOR FOR SELECT [name], color0, color1, members FROM @teams;
    OPEN @teamIterator;
    FETCH NEXT FROM @teamIterator INTO @tname, @color0, @color1, @membersString;
    WHILE @@FETCH_STATUS = 0 BEGIN
        -- create the team
        INSERT INTO Team (name, color0, color1) VALUES (@tname, @color0, @color1);
        SET @teamId = @@IDENTITY;

        DELETE FROM @membersTable;
        INSERT INTO @membersTable SELECT * FROM OPENJSON(@membersString) WITH (
            uuid UNIQUEIDENTIFIER '$'
        );

        -- mark temporary players as belonging to the team
        UPDATE ps SET ps.teamId = @teamId FROM @players ps WHERE ps.uuid IN (SELECT ms.uuid FROM @membersTable ms);

        FETCH NEXT FROM @teamIterator INTO @tname, @color0, @color1, @membersString;
    END;
    CLOSE @teamIterator;
    DEALLOCATE @teamIterator;

    DECLARE @iterUuid UNIQUEIDENTIFIER;
    DECLARE @iterName NVARCHAR(MAX);
    DECLARE @iterPlace INT;
    DECLARE @iterTimeSurvived INT;
    DECLARE @iterKilledBy UNIQUEIDENTIFIER;
    DECLARE @iterTeamId INT;

    -- first add the uuids and names of players into the database
    -- ignore game specific rankings
    DECLARE @playerIterator CURSOR;
    SET @playerIterator = CURSOR FOR SELECT p.uuid, p.name FROM @players p;
    OPEN @playerIterator;
    FETCH NEXT FROM @playerIterator INTO @iterUuid, @iterName;
    WHILE @@FETCH_STATUS = 0 BEGIN
        EXECUTE updatePlayer @iterUuid, @iterName;
        FETCH NEXT FROM @playerIterator INTO @iterUuid, @iterName;        
    END;
    CLOSE @playerIterator;
    DEALLOCATE @playerIterator;

    -- create the gameplayers
    SET @playerIterator = CURSOR FOR SELECT p.place, p.timeSurvived, p.killedBy, p.uuid, p.teamId FROM @players p;
    OPEN @playerIterator;
    FETCH NEXT FROM @playerIterator INTO @iterPlace, @iterTimeSurvived, @iterKilledBy, @iterUuid, @iterTeamId;
    WHILE @@FETCH_STATUS = 0 BEGIN
        INSERT INTO GamePlayer (place, timeSurvived, uuid, gameId, teamId, killedBy) VALUES (@iterPlace, @iterTimeSurvived, @iterUuid, @gameId, @iterTeamId, @iterKilledBy);
        FETCH NEXT FROM @playerIterator INTO @iterPlace, @iterTimeSurvived, @iterKilledBy, @iterUuid, @iterTeamId;
    END;
    CLOSE @playerIterator;
    DEALLOCATE @playerIterator;
GO


-- RESET SWITCH
UPDATE Season SET champion = NULL;
DELETE FROM GamePlayer;
DELETE FROM Game;
DELETE FROM Nickname;
DELETE FROM PvpLoadout;
DELETE FROM Player;
DELETE FROM Team;
-- =============

DECLARE @json VARCHAR(MAX) = '{
  "date": "2021-11-20T21:11:58.408272124-07:00[America/Denver]",
  "gameType": "UHC",
  "gameLength": 95773,
  "teams": [
      {
        "name": "Bubble column",
        "color1": 2154720,
        "color0": 10510368,
        "members": [
            "b8fc1a7c-73e1-4ca3-977f-956688442a69",
            "b461e129-0166-4237-9ed7-abb5853501c1"
        ]
      },
      {
        "name": "Castle",
        "color1": 2154720,
        "color0": 10510368,
        "members": [
            "619dff6e-2718-4e75-bd08-9b5ce683e071",
            "6ab842cd-242b-412a-bccb-aee79fc89798"
        ]
      },
      {
        "name": "Titanic",   
        "color1": 2154720,
        "color0": 10510368,
        "members": [
            "94a6f68c-6755-4a8a-9453-d0242a90e6b3",
            "90ef297a-c5f8-491c-a1c4-861bd143b543"
        ]
      },
      {
        "name": "Meat",   
        "color1": 2154720,
        "color0": 10510368,
        "members": [
            "479b7374-dff6-4cb0-a49b-dc1faaf11070",
            "dd7a995f-eb19-4ac5-9f11-6cb0d6e50a0d"
        ]
      },
      {
        "name": "lifeboat",   
        "color1": 2154720,
        "color0": 10510368,
        "members": [
            "42c2b8a9-e43e-40a9-8dac-a284adf6c998"
        ]
      }
  ],
  "players": [
    {
      "name": "mclonergan",
      "place": 1,
      "timeSurvived": 95773,
      "uuid": "b8fc1a7c-73e1-4ca3-977f-956688442a69"
    },
    {
      "name": "a4955",
      "place": 2,
      "timeSurvived": 95773,
      "killedBy": "b8fc1a7c-73e1-4ca3-977f-956688442a69",
      "uuid": "619dff6e-2718-4e75-bd08-9b5ce683e071"
    },
    {
      "name": "slyzian",
      "place": 3,
      "timeSurvived": 91025,
      "killedBy": "b8fc1a7c-73e1-4ca3-977f-956688442a69",
      "uuid": "6ab842cd-242b-412a-bccb-aee79fc89798"
    },
    {
      "name": "shiverisbjorn",
      "place": 4,
      "timeSurvived": 81956,
      "killedBy": "6ab842cd-242b-412a-bccb-aee79fc89798",
      "uuid": "94a6f68c-6755-4a8a-9453-d0242a90e6b3"
    },
    {
      "name": "Lightshad",
      "place": 5,
      "timeSurvived": 80290,
      "uuid": "90ef297a-c5f8-491c-a1c4-861bd143b543"
    },
    {
      "name": "Whmsy",
      "place": 6,
      "timeSurvived": 74647,
      "uuid": "479b7374-dff6-4cb0-a49b-dc1faaf11070"
    },
    {
      "name": "Carrotorch",
      "place": 7,
      "timeSurvived": 64523,
      "uuid": "dd7a995f-eb19-4ac5-9f11-6cb0d6e50a0d"
    },
    {
      "name": "roobley",
      "place": 8,
      "timeSurvived": 63608,
      "uuid": "b461e129-0166-4237-9ed7-abb5853501c1"
    },
    {
      "name": "JStrudel",
      "place": 9,
      "timeSurvived": 54700,
      "uuid": "42c2b8a9-e43e-40a9-8dac-a284adf6c998"
    }
  ]
}';

EXECUTE uploadSummary @json, 7, 2;

SELECT * FROM Player;
SELECT * FROM Game;
SELECT * FROM Team;
SELECT * FROM GamePlayer;


---------------------------------------------------------

DECLARE @players TABLE (
    name NVARCHAR(MAX),
    place INT,
    timeSurvived INT,
    killedBy UNIQUEIDENTIFIER,
    uuid UNIQUEIDENTIFIER
);

INSERT INTO @players SELECT * FROM OPENJSON(JSON_QUERY(@json, '$.players')) WITH (
    name NVARCHAR(MAX) '$.name',
    place INT '$.place',
    timeSurvived INT '$.timeSurvived',
    killedBy UNIQUEIDENTIFIER '$.killedBy',
    uuid UNIQUEIDENTIFIER '$.uuid'
);

-- first add all players into the database, ignore game stuff
DECLARE playerIterator CURSOR FOR SELECT p.uuid, p.name FROM @players p;
OPEN playerIterator;
WHILE @@FETCH_STATUS = 0 BEGIN
    DECLARE @uuid UNIQUEIDENTIFIER;
    DECLARE @name NVARCHAR(MAX);

    FETCH NEXT FROM playerIterator INTO @uuid, @name;

    EXECUTE updatePlayer @uuid, @name, NULL;
END;
CLOSE playerIterator;
DEALLOCATE playerIterator;

SELECT * FROM Player;
--------------------------------------------

DECLARE @date DATETIMEOFFSET = (SELECT TOP 1 value FROM STRING_SPLIT(JSON_VALUE(@json, '$.date'), '['));
DECLARE @gameType INT = (SELECT g.id FROM GameType g WHERE g.name = JSON_VALUE(@json, '$.gameType'));
DECLARE @gameLength INT = JSON_VALUE(@json, '$.gameLength');

SELECT @date, @gameType, @gameLength;



----------------------------------------\

SELECT CONVERT(DATETIMEOFFSET, '2021-10-30T22:40:11.599852748-04:00');

SELECT TOP 1 value FROM STRING_SPLIT('2021-10-30T22:40:11.599852748-04:00[America/New_York]', '[');


DECLARE @json VARCHAR(MAX) = '{ "date": "2021-10-30T22:40:11.599852748-04:00[America/New_York]" }';
DECLARE @rawDate DATETIMEOFFSET = (SELECT TOP 1 value FROM STRING_SPLIT(JSON_VALUE(@json, '$.date'), '['));
SELECT @rawDate;

DELETE FROM Nickname WHERE uuid = '94a6f68c-6755-4a8a-9453-d0242a90e6b3' AND nickname = 's';

GO
CREATE FUNCTION kills (@uuid UNIQUEIDENTIFIER, @gameId INT)
RETURNS INT
AS
BEGIN
    RETURN(
        SELECT COUNT(*) FROM GamePlayer gp
        WHERE gp.gameId = @gameId AND gp.killedBy = @uuid
    );
END;
GO

GO
CREATE FUNCTION gameSize (@gameId INT)
RETURNS INT
AS
BEGIN
    RETURN(
        SELECT COUNT(*) FROM GamePlayer gp
        WHERE gp.gameId = @gameId
    );
END;
GO

-- ssssssssssssssssssssssssssssssssssssssssssssssssssssss

GO
CREATE PROCEDURE calcStats
    @seasonNumber INT
AS
    SELECT gp.uuid, AVG(
        1 - CAST(gp.place - 1 - kills(gp.uuid, gp.gameId) AS FLOAT)/CAST(gameSize(gp.gameId) - 1 AS FLOAT)
    ) FROM GamePlayer gp
    INNER JOIN Game g ON g.id = gp.gameId
    INNER JOIN Season s ON s.number = g.seasonNumber AND s.number = @seasonNumber
    GROUP BY gp.uuid, gp.gameId;
GO

SELECT uuid, discordId FROM Player;

SELECT * FROM Nickname;

SELECT * FROM Player;

DELETE FROM Nickname;
DELETE FROM Player;
DELETE FROM Player WHERE uuid = '504a4dfa-2ec6-40e4-80d2-46b92c9f3164' AND discordId = 371515332252139520;

DECLARE @discordId BIGINT = 32;
DECLARE @oldUuid UNIQUEIDENTIFIER = (SELECT uuid FROM Player WHERE discordId = @discordId);
SELECT @oldUuid;

SELECT * FROM Player;
EXECUTE updateLink 258485243038662657, 'fdc2d9bf-23a8-48a3-8a60-a1b513d33259', NULL;
SELECT * FROM Player;

SELECT * FROM PvpLoadout;

SELECT * FROM Nickname;

SELECT DISTINCT p.uuid, slot0 FROM PvpLoadout p
    INNER JOIN (SELECT uuid, slot, loadoutData AS slot0 FROM PvpLoadout) p0 ON p.uuid = p0.uuid AND p0.slot = 0

INSERT INTO PvpLoadout (uuid, slot, loadoutData) VALUES ('597d3f03-7a52-49bd-9c19-0d451e002894', 1, 'dw');

SELECT DISTINCT p.uuid, slot0, slot1, slot2 FROM PvpLoadout p
    LEFT JOIN (SELECT uuid, slot, loadoutData AS slot0 FROM PvpLoadout) p0 ON p.uuid = p0.uuid AND p0.slot = 0
    LEFT JOIN (SELECT uuid, slot, loadoutData AS slot1 FROM PvpLoadout) p1 ON p.uuid = p1.uuid AND p1.slot = 1
    LEFT JOIN (SELECT uuid, slot, loadoutData AS slot2 FROM PvpLoadout) p2 ON p.uuid = p2.uuid AND p2.slot = 2;

SELECT p.uuid, NULL AS slot0, NULL AS slot1 FROM PvpLoadout p
UNION
SELECT p0.uuid, p0.loadoutData, NULL FROM PvpLoadout p0 WHERE p0.slot = 0
UNION
SELECT p1.uuid, NULL, p1.loadoutData FROM PvpLoadout p1 WHERE p1.slot = 1

SELECT s.number, s.logo, s.color, s.championColor, p.name FROM Season s
        LEFT JOIN Player p ON p.uuid = s.champion
        WHERE s.number = 7;

SELECT * FROM Season;

SELECT * FROM Game;