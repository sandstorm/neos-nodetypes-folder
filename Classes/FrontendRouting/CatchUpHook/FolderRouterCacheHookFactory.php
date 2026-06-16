<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\CatchUpHook;

use Neos\ContentRepository\Core\Projection\CatchUpHook\CatchUpHookFactoryDependencies;
use Neos\ContentRepository\Core\Projection\CatchUpHook\CatchUpHookFactoryInterface;
use Neos\ContentRepository\Core\Projection\CatchUpHook\CatchUpHookInterface;
use Neos\Flow\Mvc\Routing\RouterCachingService;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;

/**
 * @implements CatchUpHookFactoryInterface<DocumentUriPathFinder>
 */
final class FolderRouterCacheHookFactory implements CatchUpHookFactoryInterface
{
    public function __construct(
        private readonly RouterCachingService $routerCachingService,
    ) {
    }

    public function build(CatchUpHookFactoryDependencies $dependencies): CatchUpHookInterface
    {
        return new FolderRouterCacheHook(
            $dependencies->projectionState,
            $this->routerCachingService,
        );
    }
}
