CREATE TABLE `messages` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_user` integer NOT NULL
,  `id_request` integer
,  `subject` varchar(120) DEFAULT NULL
,  `message` text
,  `date_send` datetime DEFAULT CURRENT_TIME
,  `date_read` datetime
);
CREATE INDEX "idx_messages_id_user" ON "messages" (`id_user`);
