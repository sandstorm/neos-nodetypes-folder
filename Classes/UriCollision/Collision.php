<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;

final readonly class Collision
{
    public function __construct(
        public DimensionSpacePoint $dimensionSpacePoint,
        public string $uriPath,
        public NodeAggregateId $otherNodeAggregateId,
        public string $otherNodeTypeName,
        public ?string $otherNodeLabel,
    ) {
    }
}
