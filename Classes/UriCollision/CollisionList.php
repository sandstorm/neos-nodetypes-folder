<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

/**
 * @implements \IteratorAggregate<int, Collision>
 */
final readonly class CollisionList implements \IteratorAggregate, \Countable
{
    /** @var list<Collision> */
    private array $items;

    public function __construct(Collision ...$items)
    {
        $this->items = array_values($items);
    }

    public static function empty(): self
    {
        return new self();
    }

    public function isEmpty(): bool
    {
        return $this->items === [];
    }

    public function with(Collision $collision): self
    {
        return new self(...[...$this->items, $collision]);
    }

    public function merge(self $other): self
    {
        return new self(...[...$this->items, ...$other->items]);
    }

    public function getIterator(): \Traversable
    {
        return new \ArrayIterator($this->items);
    }

    public function count(): int
    {
        return count($this->items);
    }
}
