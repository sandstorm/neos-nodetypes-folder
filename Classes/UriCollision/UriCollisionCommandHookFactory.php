<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Neos\ContentRepository\Core\CommandHandler\CommandHookInterface;
use Neos\ContentRepository\Core\Factory\CommandHookFactoryInterface;
use Neos\ContentRepository\Core\Factory\CommandHooksFactoryDependencies;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;

final readonly class UriCollisionCommandHookFactory implements CommandHookFactoryInterface
{
    public function __construct(
        private UriCollisionCheck $uriCollisionCheck,
        private ContentRepositoryRegistry $contentRepositoryRegistry,
    ) {
    }

    public function build(CommandHooksFactoryDependencies $commandHooksFactoryDependencies): CommandHookInterface
    {
        return new UriCollisionCommandHook(
            $this->uriCollisionCheck,
            $this->contentRepositoryRegistry,
            $commandHooksFactoryDependencies->contentRepositoryId,
        );
    }
}
