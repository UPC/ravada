CREATE TABLE `bases_vm` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer NOT NULL
,  `id_vm` integer
,  `enabled` integer DEFAULT 1
,  UNIQUE (`id_domain`,`id_vm`)
);
CREATE INDEX "idx_bases_vm_id_domain" ON "bases_vm" (`id_domain`);
CREATE INDEX "idx_bases_vm_id_vm" ON "bases_vm" (`id_vm`);
