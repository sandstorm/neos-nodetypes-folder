<?php

namespace Neos\Flow\Persistence\Doctrine\Migrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

/**
 * Adds the `hideurisegment` column to the DocumentUriPath projection table.
 *
 * This column stores whether a Folder node hides its URI segment (i.e. the
 * `hideSegmentInUriPath` node property). It is read by
 * DocumentUriPathProjection to decide whether to include the folder's segment
 * when building descendant URI paths.
 *
 * The table name is deterministic for the "default" content repository:
 *   cr_default_p_neos_documenturipath_uri
 */
class Version20260413000000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Add hideurisegment column to DocumentUriPath projection table (Sandstorm.NodeTypes.Folder)';
    }

    public function up(Schema $schema): void
    {
        $this->abortIf(
            !str_contains($this->connection->getDatabasePlatform()->getName(), 'mysql'),
            'Migration can only be executed safely on MySQL/MariaDB.'
        );

        $tableName = 'cr_default_p_neos_documenturipath_uri';

        if (!$schema->hasTable($tableName)) {
            // Table does not exist yet – setUp() will create it including the column.
            return;
        }

        if ($schema->getTable($tableName)->hasColumn('hideurisegment')) {
            // Column already present (e.g. fresh install where setUp() ran first).
            return;
        }

        $this->addSql(
            'ALTER TABLE `' . $tableName . '` ADD COLUMN `hideurisegment` INT UNSIGNED NOT NULL DEFAULT 0'
        );
    }

    public function down(Schema $schema): void
    {
        $this->abortIf(
            !str_contains($this->connection->getDatabasePlatform()->getName(), 'mysql'),
            'Migration can only be executed safely on MySQL/MariaDB.'
        );

        $tableName = 'cr_default_p_neos_documenturipath_uri';

        if (!$schema->hasTable($tableName) || !$schema->getTable($tableName)->hasColumn('hideurisegment')) {
            return;
        }

        $this->addSql('ALTER TABLE `' . $tableName . '` DROP COLUMN `hideurisegment`');
    }
}
