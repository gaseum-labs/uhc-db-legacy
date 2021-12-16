DROP PROCEDURE IF EXISTS updateLoadout;
DROP PROCEDURE IF EXISTS updateLink;
DROP PROCEDURE IF EXISTS updatePlayer;
DROP PROCEDURE IF EXISTS updateNickname;
DROP PROCEDURE IF EXISTS removeNickname;
DROP PROCEDURE IF EXISTS updateSeason;
DROP PROCEDURE IF EXISTS uploadSummary;

GO
CREATE PROCEDURE updateLoadout
    @uuid UNIQUEIDENTIFIER,
    @slot INT,
    @data NVARCHAR(MAX)
AS
    IF NOT EXISTS (SELECT p.uuid FROM Player p WHERE p.uuid = @uuid)
        INSERT INTO Player (uuid, name) VALUES (@uuid, 'Unnamed');

    IF EXISTS (SELECT uuid, slot FROM PvpLoadout WHERE uuid = @uuid AND slot = @slot)
        UPDATE PvpLoadout SET loadoutData = @data WHERE uuid = @uuid AND slot = @slot;
    ELSE
        INSERT INTO PvpLoadout (uuid, slot, loadoutData) VALUES (@uuid, @slot, @data);
GO

GO
CREATE PROCEDURE updateLink
    @discordId BIGINT,
    @uuid UNIQUEIDENTIFIER,
	@name NVARCHAR(MAX)
AS
    -- NAME is not used for link removal

    -- remove linked discord account from a player
    IF @discordId IS NULL
        UPDATE Player SET @discordId = NULL WHERE uuid = @uuid;

    -- remove linked discord account from a discord accout
    ELSE IF @uuid IS NULL
        UPDATE Player SET @discordId = NULL WHERE discordId = @discordId;

    -- adding a link
    ELSE BEGIN
        -- this doesn't care if a minecraft account has already been linked to some other discordid
        -- it will overwrite that link and set the original minecraft account to be unlinked

        -- the minecraft player that used to be attached to this 
        DECLARE @oldUuid UNIQUEIDENTIFIER = (SELECT uuid FROM Player WHERE discordId = @discordId);

        SELECT @oldUuid AS oldUUID

        IF @oldUuid IS NOT NULL
            UPDATE Player SET discordId = NULL WHERE uuid = @oldUuid;

        IF EXISTS (SELECT * FROM Player WHERE uuid = @uuid)
            UPDATE Player SET discordId = @discordId WHERE uuid = @uuid;
        ELSE
            INSERT INTO Player (uuid, name, discordId) VALUES (@uuid, ISNULL(@name, 'Unknown'), @discordId);
    END;
GO

GO
CREATE PROCEDURE updatePlayer
    @uuid UNIQUEIDENTIFIER,
	@name NVARCHAR(MAX)
AS
    IF EXISTS (SELECT uuid FROM Player WHERE uuid = @uuid)
        UPDATE Player SET name = @name WHERE uuid = @uuid;
    ELSE
        INSERT INTO Player (uuid, name, discordId) VALUES (@uuid, ISNULL(@name, 'Unknown'), NULL);
GO

GO
CREATE PROCEDURE updateNickname
    @uuid UNIQUEIDENTIFIER,
    @nickname NVARCHAR(MAX)
AS
    INSERT INTO Nickname (uuid, nickname) VALUES (@uuid, @nickname);
GO

GO
CREATE PROCEDURE removeNickname
    @uuid UNIQUEIDENTIFIER,
    @nickname NVARCHAR(MAX)
AS
    DELETE FROM Nickname WHERE uuid = @uuid AND nickname = @nickname;
GO

GO
CREATE PROCEDURE updateSeason
    @number INT,
    @logo VARBINARY(MAX),
    @color INT,
    @championColor INT,
    @champion UNIQUEIDENTIFIER
AS
    IF EXISTS (SELECT number FROM Season WHERE number = @number) BEGIN
        IF @logo IS NOT NULL
            UPDATE Season SET logo = @logo WHERE number = @number;
        IF @color IS NOT NULL
            UPDATE Season SET color = @color WHERE number = @number;
        IF @championColor IS NOT NULL
            UPDATE Season SET championColor = @championColor WHERE number = @number;
        IF @champion IS NOT NULL
            UPDATE Season SET champion = @champion WHERE number = @number;
    END;
    ELSE BEGIN
        INSERT INTO Season (number, logo, color, championColor, champion) 
        VALUES (@number, ISNULL(@logo, CONVERT(VARBINARY(MAX), '')), ISNULL(@color, 0xffffff), ISNULL(@championColor, 0xffffff), @champion);
    END;

    SELECT s.number, s.logo, s.color, s.championColor, p.name FROM Season s
        LEFT JOIN Player p ON p.uuid = s.champion
        WHERE s.number = @number;
GO

GO
CREATE PROCEDURE uploadSummary
    @json NVARCHAR(MAX),
    @seasonNumber INT,
    @gameNumber INT
AS
    DECLARE @seasonError NVARCHAR(MAX) = CONCAT('Season ', @seasonNumber, ' does not exist');
    IF NOT EXISTS (SELECT * FROM Season WHERE number = @seasonNumber)
        THROW 51000, @seasonError, 1;

    DELETE FROM gp FROM GamePlayer gp WHERE gp.gameId IN (SELECT g.id FROM Game g WHERE g.number = @gameNumber AND g.seasonNumber = @seasonNumber);
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
