
DROP TABLE IF EXISTS GamePlayer;
DROP TABLE IF EXISTS Team;
DROP TABLE IF EXISTS PvpLoadout;
DROP TABLE IF EXISTS Nickname;
DROP TABLE IF EXISTS Game;
DROP TABLE IF EXISTS GameType;
DROP TABLE IF EXISTS Season;
DROP TABLE IF EXISTS Player;

CREATE TABLE Player (
	uuid uniqueidentifier PRIMARY KEY,
	discordId BIGINT,
	name NVARCHAR(MAX) NOT NULL,
);

CREATE TABLE Season (
	number INT PRIMARY KEY,
	logo VARBINARY(MAX) NOT NULL,
	color INT NOT NULL,
	championColor INT NOT NULL,
	champion uniqueidentifier FOREIGN KEY REFERENCES Player(uuid),
);

CREATE TABLE Game (
	id INT IDENTITY(1,1) PRIMARY KEY,
	seasonNumber INT FOREIGN KEY REFERENCES Season(number) NOT NULL,
	number INT NOT NULL,
	startDate DATE NOT NULL,
	type NCHAR(3),
	matchTime INT NOT NULL,
);

CREATE TABLE Nickname (
	uuid uniqueidentifier FOREIGN KEY REFERENCES Player(uuid) NOT NULL,
	nickname NVARCHAR(MAX) NOT NULL,
);

CREATE TABLE PvpLoadout (
	uuid uniqueidentifier FOREIGN KEY REFERENCES Player(uuid) NOT NULL,
	slot INT NOT NULL,
	loadoutData NVARCHAR(MAX) NOT NULL,
);

CREATE TABLE Team (
	id INT IDENTITY(1,1) PRIMARY KEY,
	name NVARCHAR(MAX) NOT NULL,
	color0 INT NOT NULL,
	color1 INT NOT NULL,
);

CREATE TABLE GamePlayer (
	place INT NOT NULL,
	timeSurvived INT NOT NULL,
	uuid uniqueidentifier FOREIGN KEY REFERENCES Player(uuid) NOT NULL,
	gameId INT FOREIGN KEY REFERENCES Game(id) NOT NULL,
	teamId INT FOREIGN KEY REFERENCES Team(id) NOT NULL,
	killedBy uniqueidentifier FOREIGN KEY REFERENCES Player(uuid),
);
