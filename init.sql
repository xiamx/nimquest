CREATE TABLE "state" (
	"key" VARCHAR(255) NOT NULL PRIMARY KEY,
	"val" TEXT NOT NULL
)
;
INSERT INTO "db"."state" ("key") VALUES ('last_notification');

CREATE TABLE "rel" (
	"answerer" VARCHAR(255) NOT NULL,
	"asker" VARCHAR(255) NOT NULL,
	"allow" TINYINT NOT NULL,
    PRIMARY KEY (answerer, asker)
)
;

CREATE INDEX rel_answerer_idx ON "rel" ("answerer"); 
CREATE INDEX rel_asker_idx ON "rel" ("asker");

CREATE TABLE "questions" (
	"status_id" BIGINT NOT NULL PRIMARY KEY,
    "asker" VARCHAR(255) NOT NULL DEFAULT '',
    "answerer" VARCHAR(255) NOT NULL DEFAULT '',
	"question" TEXT NOT NULL DEFAULT '',
	"answer" TEXT NULL DEFAULT NULL,
	"created_at" DATETIME NOT NULL DEFAULT NOW,
	"answered_at" DATETIME NULL DEFAULT NULL
)
;

CREATE TABLE "optouts" (
    "username" VARCHAR(255) NOT NULL PRIMARY KEY,
    "created_at" DATETIME NOT NULL DEFAULT NOW
);

CREATE TABLE "processed_notifications" (
    "status_id" BIGINT NOT NULL PRIMARY KEY,
    "created_at" DATETIME NOT NULL DEFAULT NOW
);