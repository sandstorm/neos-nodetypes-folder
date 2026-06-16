<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

/**
 * Thrown by the command hook (and the HTTP endpoint) when a command would
 * write a node whose effective uriPath already exists in the projection for
 * the same dimension space point. Aborts the command before any event is
 * appended.
 */
final class UriPathCollisionDetected extends \DomainException
{
    public function __construct(public readonly CollisionList $collisions)
    {
        $first = null;
        foreach ($collisions as $c) {
            $first = $c;
            break;
        }
        $message = $first === null
            ? 'URI path collision detected.'
            : sprintf(
                'URI path "%s" would collide with node %s in dimension %s.',
                $first->uriPath,
                $first->otherNodeAggregateId->value,
                $first->dimensionSpacePointHash,
            );
        parent::__construct($message, 1747000001);
    }
}
