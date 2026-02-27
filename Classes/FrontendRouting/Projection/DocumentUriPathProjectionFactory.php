<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\Projection;

use Doctrine\DBAL\Connection;
use Neos\ContentRepository\Core\Factory\SubscriberFactoryDependencies;
use Neos\ContentRepository\Core\Projection\ProjectionFactoryInterface;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathProjectionFactory as NeosCoreDocumentUriPathProjectionFactory;

/**
 * @implements ProjectionFactoryInterface<DocumentUriPathProjection>
 * @internal implementation detail to manage document node uris. For resolving please use the NodeUriBuilder and for matching the Router.
 */
final class DocumentUriPathProjectionFactory implements ProjectionFactoryInterface
{
    public function __construct(
        private readonly Connection $dbal,
        private readonly ContentRepositoryRegistry $contentRepositoryRegistry,
    ) {}

    public static function projectionTableNamePrefix(
        ContentRepositoryId $contentRepositoryId
    ): string {
        return NeosCoreDocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId);
    }

    public function build(
        SubscriberFactoryDependencies $projectionFactoryDependencies,
        array $options,
    ): DocumentUriPathProjection {
        $contentRepositoryId = $projectionFactoryDependencies->contentRepositoryId;

        return new DocumentUriPathProjection(
            $projectionFactoryDependencies->nodeTypeManager,
            $this->dbal,
            self::projectionTableNamePrefix($contentRepositoryId),
            $this->contentRepositoryRegistry,
            $contentRepositoryId,
        );
    }
}
