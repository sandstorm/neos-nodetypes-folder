<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\Projection;

use Doctrine\DBAL\Connection;
use Doctrine\DBAL\Exception as DBALException;
use Doctrine\DBAL\Schema\Schema;
use Doctrine\DBAL\Schema\SchemaException;
use Doctrine\DBAL\Types\Types;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathSchemaBuilder;

/**
 * Wraps the core DocumentUriPathSchemaBuilder and adds the folder-specific
 * `hideurisegment` column — without touching any Neos.Neos core files.
 *
 * @internal
 */
final class FolderAwareDocumentUriPathSchemaBuilder
{
    public function __construct(
        private readonly string $tableNamePrefix,
    ) {
    }

    /**
     * @throws DBALException
     * @throws SchemaException
     */
    public function buildSchema(Connection $connection): Schema
    {
        $schema = (new DocumentUriPathSchemaBuilder($this->tableNamePrefix))->buildSchema($connection);

        $table = $schema->getTable($this->tableNamePrefix . '_uri');
        if (!$table->hasColumn('hideurisegment')) {
            $table->addColumn('hideurisegment', Types::INTEGER)
                ->setLength(4)
                ->setUnsigned(true)
                ->setDefault(0)
                ->setNotnull(true);
        }

        return $schema;
    }
}
